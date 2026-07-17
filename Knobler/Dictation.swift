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
import AVFoundation
import FluidAudio

// MARK: - Engines

protocol TranscriptionEngine {
    func transcribe(_ samples: [Float]) async throws -> String
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
        guard inputFormat.sampleRate > 0 else {
            throw NSError(domain: "MicRecorder", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "input indisponível"])
        }
        let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate,
            channels: 1, interleaved: false)!
        converter = AVAudioConverter(from: inputFormat, to: outFormat)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) {
            [weak self] buffer, _ in
            self?.append(buffer, outFormat: outFormat)
        }
        engine.prepare()
        try engine.start()
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

final class DictationController {
    /// nil = pílula some. Chamado sempre na main queue.
    var onState: ((DictationPhase?) -> Void)?

    private let recorder = MicRecorder()
    private let parakeet = ParakeetEngine()
    private var keyMonitor: Any?
    private var recording = false
    private var transcribing = false
    private var preparing = false
    private(set) var modelReady = false

    /// Pré-aquece o modelo local e dispara o prompt de microfone no launch —
    /// o primeiro ditado não pode esperar 600MB de download.
    func start() {
        guard AppSettings.shared.dictation else { return }
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        prepareLocalEngine()
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
        guard AppSettings.shared.dictation else { return }
        if pressed { begin() } else { finish() }
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
        if !AppSettings.shared.dictationCloud, !modelReady {
            prepareLocalEngine()
            flash(.preparing)
            return
        }
        do {
            try recorder.start()
        } catch {
            flash(.error("Sem acesso ao microfone"))
            return
        }
        recording = true
        recorder.onLevel = { [weak self] level in
            DispatchQueue.main.async {
                guard self?.recording == true else { return }
                self?.onState?(.recording(level: level))
            }
        }
        onState?(.recording(level: 0))
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
        _ = recorder.stop()
        removeKeyMonitor()
        onState?(nil)
    }

    private func finish() {
        guard recording else { return }
        recording = false
        removeKeyMonitor()
        let samples = recorder.stop()
        // toque acidental: menos de 0,5s de áudio não vira transcrição
        guard samples.count >= Int(MicRecorder.sampleRate / 2) else {
            onState?(nil)
            return
        }
        transcribing = true
        onState?(.transcribing)
        Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await self.activeEngine().transcribe(samples)
                DispatchQueue.main.async {
                    self.transcribing = false
                    self.onState?(nil)
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { Self.insert(trimmed) }
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

    private func activeEngine() -> TranscriptionEngine {
        if AppSettings.shared.dictationCloud {
            let key = DeepgramKeyStore.load()
            if !key.isEmpty { return DeepgramEngine(apiKey: key) }
        }
        return parakeet
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Pílula de aviso por 2s (erro, modelo baixando).
    private func flash(_ phase: DictationPhase) {
        onState?(phase)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.onState?(nil)
        }
    }

    // MARK: - Inserção no cursor

    /// Pasteboard + ⌘V sintético: único método robusto com acentos/IME.
    /// O clipboard anterior volta 0,5s depois do paste.
    private static func insert(_ text: String) {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .combinedSessionState)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)!
        vDown.flags = .maskCommand
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)!
        vUp.flags = .maskCommand
        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            pasteboard.clearContents()
            if let saved { pasteboard.setString(saved, forType: .string) }
        }
    }
}
