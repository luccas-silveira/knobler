//
//  Dictation.swift
//  Knobler
//
//  Ditado estilo Superwhisper: segurar ⌥ direita grava o mic, soltar
//  transcreve (Parakeet v3 local via FluidAudio; Deepgram opcional) e
//  insere o texto no app ativo via pasteboard + ⌘V sintético.
//  ponytail: sem modos de formatação com LLM — o Parakeet já pontua.
//

import AppKit
import ApplicationServices
import AVFoundation
import FluidAudio

// MARK: - Engines

protocol TranscriptionEngine {
    func transcribe(_ samples: [Float]) async throws -> String
}

enum TranscriptionSelection: Equatable {
    case local
    case deepgram(apiKey: String)
    case missingDeepgramKey
}

/// Parakeet TDT v3 (multilíngue) em CoreML no Neural Engine.
/// Modelo (~600MB) baixado do HuggingFace no primeiro prepare().
actor ParakeetEngine: TranscriptionEngine {
    private var manager: AsrManager?

    func prepare() async throws {
        guard manager == nil else { return }
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        let m = AsrManager(config: .default)
        try await m.loadModels(models)
        manager = m
    }

    var ready: Bool { manager != nil }

    func transcribe(_ samples: [Float]) async throws -> String {
        try await prepare()
        guard let manager else { return "" }
        // FluidAudio 0.15.5: transcribe(_:) exige um decoderState inout.
        var decoderState = try TdtDecoderState()
        return try await manager.transcribe(samples, decoderState: &decoderState).text
    }
}

/// Deepgram nova-3 (pre-recorded). PCM cru linear16/16kHz — sem container WAV.
struct DeepgramEngine: TranscriptionEngine {
    let apiKey: String

    func transcribe(_ samples: [Float]) async throws -> String {
        var components = URLComponents(string: "https://api.deepgram.com/v1/listen")!
        components.queryItems = [
            .init(name: "model", value: "nova-3"),
            .init(name: "smart_format", value: "true"),
            .init(name: "language", value: "multi"),
            .init(name: "encoding", value: "linear16"),
            .init(name: "sample_rate", value: "16000"),
            .init(name: "channels", value: "1"),
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        var pcm = Data(capacity: samples.count * 2)
        for sample in samples {
            var value = Int16(max(-1, min(1, sample)) * 32767)
            withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
        }
        request.httpBody = pcm

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "Deepgram", code: code,
                          userInfo: [NSLocalizedDescriptionKey: "Deepgram HTTP \(code)"])
        }

        struct DGResponse: Decodable {
            struct Results: Decodable { let channels: [Channel] }
            struct Channel: Decodable { let alternatives: [Alternative] }
            struct Alternative: Decodable { let transcript: String }
            let results: Results
        }
        let decoded = try JSONDecoder().decode(DGResponse.self, from: data)
        return decoded.results.channels.first?.alternatives.first?.transcript ?? ""
    }
}

// MARK: - Gravador

/// Mic → Float32 mono 16kHz (formato que Parakeet e Deepgram esperam).
final class MicRecorder {
    static let sampleRate: Double = 16000

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    // append() roda na thread de áudio do AVAudioEngine e stop() lê na main:
    // Array sob mutação concorrente é UB, então serializamos com este lock.
    private let samplesLock = NSLock()
    var onLevel: ((Float) -> Void)?

    func start() throws {
        samplesLock.lock()
        samples.removeAll()
        samplesLock.unlock()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        // Sem microfone (ex.: Mac mini sem mic externo) ou permissão negada, o
        // inputNode reporta um formato INVÁLIDO — 0 canais, e às vezes sampleRate
        // herdado da saída (> 0). installTap com esse formato lança uma NSException
        // do ObjC (não capturável por try) e aborta o processo. channelCount é a
        // condição que realmente valida o formato pro tap, então checamos os dois.
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw NSError(domain: "MicRecorder", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "microfone indisponível"])
        }
        let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate,
            channels: 1, interleaved: false)!
        converter = AVAudioConverter(from: inputFormat, to: outFormat)
        // installTap lança NSException do ObjC (não capturável por `try`) em alguns
        // devices cujo formato passa no guard acima mas o tap rejeita (Bluetooth,
        // áudio virtual/agregado). O shim @try/@catch converte em Error → o begin()
        // mostra "microfone indisponível" em vez de abortar o app.
        // removeTap defensivo: se um start() anterior deixou tap pendurado, um novo
        // installTap na mesma bus também lançaria NSException.
        // catching(_:) é importado como `throws` (BOOL + NSError** do ObjC): se o
        // installTap lançar NSException, vira Error de Swift → o catch do begin().
        try ObjCException.catching {
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) {
                [weak self] buffer, _ in
                self?.append(buffer, outFormat: outFormat)
            }
        }
        engine.prepare()
        try engine.start()
    }

    /// Prova que o shim ObjC captura NSException (determinístico, independe do
    /// device): se retornar false, o crash-proofing do installTap não vale nada.
    /// Rodável via `Knobler --selfcheck` (sem UI) e no assert de DEBUG no launch.
    static func exceptionGuardWorks() -> Bool {
        let catchesThrow: Bool
        do {
            try ObjCException.catching {
                NSException(name: .genericException, reason: "selfcheck", userInfo: nil).raise()
            }
            catchesThrow = false   // devia ter lançado
        } catch {
            catchesThrow = true
        }
        let passesClean: Bool
        do { try ObjCException.catching { }; passesClean = true }
        catch { passesClean = false }
        return catchesThrow && passesClean
    }

    private func append(_ buffer: AVAudioPCMBuffer, outFormat: AVAudioFormat) {
        guard let converter else { return }
        let ratio = Self.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity)
        else { return }
        var fed = false
        converter.convert(to: out, error: nil) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard let channel = out.floatChannelData?[0], out.frameLength > 0 else { return }
        let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
        samplesLock.lock()
        samples.append(contentsOf: chunk)
        samplesLock.unlock()
        let rms = sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count))
        // ponytail: ganho empírico pra barra de nível ler bem em voz normal
        onLevel?(min(1, rms * 12))
    }

    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        samplesLock.lock()
        let captured = samples
        samplesLock.unlock()
        return captured
    }
}

// MARK: - Controller

enum DictationDestination: Equatable {
    case ask(id: String)
    case application(pid: pid_t)
}

final class DictationController {
    /// nil = pílula some. Chamado sempre na main queue.
    var onState: ((DictationPhase?) -> Void)?

    var destinationProvider: (() -> DictationDestination?)?
    /// Retorna true se o destino Ask capturado ainda consumiu o texto.
    var transcriptSink: ((String, DictationDestination) -> Bool)?

    private let recorder = MicRecorder()
    private let parakeet = ParakeetEngine()
    private var keyMonitor: Any?
    private var recording = false
    private var transcribing = false
    private var preparing = false
    private var recordingEngine: (any TranscriptionEngine)?
    private var recordingDestination: DictationDestination?
    private var flashWorkItem: DispatchWorkItem?
    private var flashGeneration: UInt64 = 0
    private(set) var modelReady = false

    static func _flashSelfCheck() -> Bool {
        let controller = DictationController()
        var states: [DictationPhase?] = []
        controller.onState = { states.append($0) }
        controller.flash(.preparing, duration: 60)
        guard let work = controller.flashWorkItem else { return false }
        controller.setState(.recording(level: 0))
        work.perform()
        return states == [.preparing, .recording(level: 0)]
    }

    static func _enginePolicySelfCheck() -> Bool {
        guard shouldPrepareLocalEngine(cloud: false),
              !shouldPrepareLocalEngine(cloud: true),
              transcriptionSelection(cloud: false, key: "") == .local,
              transcriptionSelection(cloud: true, key: "  ") == .missingDeepgramKey,
              transcriptionSelection(cloud: true, key: "abc") == .deepgram(apiKey: "abc")
        else { return false }
        return true
    }

    static func shouldPrepareLocalEngine(cloud: Bool) -> Bool {
        !cloud
    }

    static func transcriptionSelection(cloud: Bool, key: String) -> TranscriptionSelection {
        guard cloud else { return .local }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? .missingDeepgramKey : .deepgram(apiKey: trimmed)
    }

    /// Pré-aquece o modelo local e dispara o prompt de microfone no launch —
    /// o primeiro ditado não pode esperar 600MB de download.
    func start() {
        guard AppSettings.shared.dictation else { return }
        // Sem Acessibilidade o CGEventTap nem é criado, então o flagsChanged da
        // ⌥ direita nunca chega aqui — o ditado morre 100% silencioso. Como o
        // release é assinado ad-hoc, o TCC ancora a permissão no cdhash e a
        // revoga a CADA update. Avisa e leva o usuário pro painel.
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.flash(.error("Ditado precisa de Acessibilidade"))
            }
        }
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        if Self.shouldPrepareLocalEngine(cloud: AppSettings.shared.dictationCloud) {
            prepareLocalEngine()
        }
        #if DEBUG
        TranscriptFormatter._selfCheck()
        assert(MicRecorder.exceptionGuardWorks(), "shim ObjC não captura NSException")
        #endif
        if AppSettings.shared.formatTranscript {
            Task { await formatter().prewarm() }
        }
    }

    private func formatter() -> TranscriptFormatter {
        TranscriptFormatter(endpoint: AppSettings.shared.formatEndpoint,
                            model: AppSettings.shared.formatModel)
    }

    /// Baixa/carrega o Parakeet. Reentrante: o start() no launch pode nem rodar
    /// (toggle desligado) ou falhar (rede caiu), então o begin() também chama
    /// isto pra que o hold do usuário vire o gatilho de download/retry.
    private func prepareLocalEngine() {
        guard !preparing, !modelReady else { return }
        preparing = true
        Task { [weak self] in
            try? await self?.parakeet.prepare()
            let ready = await self?.parakeet.ready ?? false
            DispatchQueue.main.async {
                self?.modelReady = ready
                self?.preparing = false
            }
        }
    }

    func rightOptionChanged(_ pressed: Bool) {
        if pressed {
            guard AppSettings.shared.dictation else { return }
            begin()
        } else if recording {
            finish()
        }
    }

    var diagnostics: [String: Any] {
        [
            "enabled": AppSettings.shared.dictation,
            "cloud": AppSettings.shared.dictationCloud,
            "modelReady": modelReady,
            "recording": recording,
            "transcribing": transcribing,
        ]
    }

    private func begin() {
        guard !recording, !transcribing else { return }
        switch Self.transcriptionSelection(
            cloud: AppSettings.shared.dictationCloud,
            key: DeepgramKeyStore.load()
        ) {
        case .missingDeepgramKey:
            flash(.error("Configure a chave do Deepgram"))
            return
        case .local:
            guard modelReady else {
                prepareLocalEngine()
                flash(.preparing)
                return
            }
            recordingEngine = parakeet
        case .deepgram(let apiKey):
            recordingEngine = DeepgramEngine(apiKey: apiKey)
        }
        recordingDestination = destinationProvider?()
        do {
            try recorder.start()
        } catch {
            recordingEngine = nil
            recordingDestination = nil
            flash(.error("Sem acesso ao microfone"))
            return
        }
        recording = true
        recorder.onLevel = { [weak self] level in
            DispatchQueue.main.async {
                guard self?.recording == true else { return }
                self?.setState(.recording(level: level))
            }
        }
        setState(.recording(level: 0))
        // outra tecla durante o hold = combo ⌥+tecla de verdade → cancela e
        // deixa o evento passar; Esc (53) também cai aqui
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) {
            [weak self] _ in
            self?.cancel()
        }
    }

    private func cancel() {
        guard recording else { return }
        recording = false
        recordingEngine = nil
        recordingDestination = nil
        _ = recorder.stop()
        removeKeyMonitor()
        setState(nil)
    }

    private func finish() {
        guard recording else { return }
        recording = false
        let destination = recordingDestination
        recordingDestination = nil
        removeKeyMonitor()
        let samples = recorder.stop()
        // toque acidental: menos de 0,5s de áudio não vira transcrição
        guard samples.count >= Int(MicRecorder.sampleRate / 2) else {
            recordingEngine = nil
            setState(nil)
            return
        }
        guard let engine = recordingEngine else {
            setState(nil)
            return
        }
        recordingEngine = nil
        transcribing = true
        setState(.transcribing)
        Task { [weak self] in
            guard let self else { return }
            do {
                var text = try await engine.transcribe(samples)
                // Formatação por IA local: falha/timeout → mantém o cru (nunca perde o ditado).
                let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !raw.isEmpty, AppSettings.shared.formatTranscript {
                    text = (try? await self.formatter().format(raw)) ?? raw
                }
                DispatchQueue.main.async {
                    self.transcribing = false
                    self.setState(nil)
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    switch destination {
                    case .some(.ask(let id)):
                        if self.transcriptSink?(trimmed, .ask(id: id)) != true {
                            Self.copy(trimmed)
                            self.flash(.error("Pergunta mudou — texto copiado"))
                        }
                    case .some(.application(let pid)):
                        if !Self.insert(trimmed, expectedPID: pid) {
                            self.flash(.error("App mudou — texto copiado"))
                        }
                    case .none:
                        Self.copy(trimmed)
                        self.flash(.error("Sem destino — texto copiado"))
                    }
                }
            } catch {
                NSLog("knobler ditado: %@", error.localizedDescription)
                DispatchQueue.main.async {
                    self.transcribing = false
                    self.flash(.error("Falha na transcrição"))
                }
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func setState(_ phase: DictationPhase?) {
        flashWorkItem?.cancel()
        flashWorkItem = nil
        flashGeneration &+= 1
        onState?(phase)
    }

    /// Pílula de aviso por 2s (erro, modelo baixando).
    private func flash(_ phase: DictationPhase, duration: TimeInterval = 2) {
        flashWorkItem?.cancel()
        flashGeneration &+= 1
        let generation = flashGeneration
        onState?(phase)
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.flashGeneration == generation else { return }
            self.flashWorkItem = nil
            self.onState?(nil)
        }
        flashWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    // MARK: - Inserção no cursor

    private static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func _clipboardSelfCheck() -> Bool {
        let pasteboard = NSPasteboard(name: .init("knobler.dictation.selfcheck"))
        let customType = NSPasteboard.PasteboardType("com.zoi.knobler.selfcheck")
        let original = Data([0x01, 0x02, 0x03])

        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setData(original, forType: customType)
        pasteboard.writeObjects([item])

        _ = insert(
            "temporário",
            expectedPID: nil,
            pasteboard: pasteboard,
            restoreDelay: 0,
            postPaste: {})
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        guard pasteboard.data(forType: customType) == original else { return false }

        _ = insert(
            "temporário",
            expectedPID: nil,
            pasteboard: pasteboard,
            restoreDelay: 0.02,
            postPaste: {})
        pasteboard.clearContents()
        pasteboard.setString("copiado depois", forType: .string)
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        return pasteboard.string(forType: .string) == "copiado depois"
    }

    /// Pasteboard + ⌘V sintético: único método robusto com acentos/IME.
    @discardableResult
    private static func insert(
        _ text: String,
        expectedPID: pid_t?,
        pasteboard: NSPasteboard = .general,
        restoreDelay: TimeInterval = 0.5,
        postPaste: () -> Void = postCommandV
    ) -> Bool {
        if let expectedPID,
           NSWorkspace.shared.frontmostApplication?.processIdentifier != expectedPID {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return false
        }

        let savedItems: [NSPasteboardItem] = pasteboard.pasteboardItems?.map { source in
            let copy = NSPasteboardItem()
            for type in source.types {
                if let data = source.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        } ?? []

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let temporaryChangeCount = pasteboard.changeCount
        postPaste()

        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) { [pasteboard, savedItems, temporaryChangeCount] in
            guard pasteboard.changeCount == temporaryChangeCount else { return }
            pasteboard.clearContents()
            if !savedItems.isEmpty {
                pasteboard.writeObjects(savedItems)
            }
        }
        return true
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)!
        let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)!
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
