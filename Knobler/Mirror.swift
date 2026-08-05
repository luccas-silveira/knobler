//
//  Mirror.swift
//  Knobler
//
//  Espelho: preview da câmera no notch expandido pra se checar antes de
//  entrar em reunião. A sessão AVCapture liga quando o preview aparece e
//  desliga quando ele some — nada roda com o notch fechado.
//

import AVFoundation
import SwiftUI

final class MirrorController: ObservableObject {
    static let shared = MirrorController()

    /// Abrir o dispositivo falhou (sem webcam, USB fora, câmera tomada por
    /// outro app). Sem isso o preview esperava pra sempre um
    /// `AVCaptureSessionDidStartRunning` que nunca vem.
    @Published private(set) var falhou = false

    private var session: AVCaptureSession?
    // ponytail: refcount porque dois monitores podem exibir o mesmo preview
    private var useCount = 0

    /// Devolve a sessão na hora, ainda sem entrada: abrir a câmera custa cerca
    /// de um segundo e, feito na main, congelava o card inteiro antes de ele
    /// conseguir desenhar o "ligando…". A entrada entra depois, no background.
    func acquire() -> AVCaptureSession? {
        useCount += 1
        if let session { return session }
        let session = AVCaptureSession()
        session.sessionPreset = .medium
        self.session = session
        falhou = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let device = Self.preferredDevice(),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                NSLog("knobler mirror: câmera indisponível")
                DispatchQueue.main.async { self?.falhou = true }
                return
            }
            session.addInput(input)
            // soltaram o espelho enquanto a câmera abria — não liga nada
            guard DispatchQueue.main.sync(execute: { self?.session === session }) else { return }
            session.startRunning()
        }
        return session
    }

    func release() {
        useCount = max(0, useCount - 1)
        guard useCount == 0, let session else { return }
        self.session = nil
        falhou = false
        DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
    }

    /// Troca a câmera com o espelho já aberto. Sem sessão viva não faz nada —
    /// o próximo acquire() já pega a nova.
    func switchDevice() {
        guard let session else { return }
        guard let device = Self.preferredDevice(),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        if session.canAddInput(input) { session.addInput(input) }
        session.commitConfiguration()
    }

    /// Câmeras oferecidas no Picker dos Ajustes (embutida, USB, Continuity…).
    static func availableDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
            mediaType: .video, position: .unspecified
        ).devices
    }

    /// A escolhida nos Ajustes; se ela sumiu (USB desconectado) ou está em
    /// "automática", a default(for:) pode devolver uma capturadora sem sinal —
    /// então prefere a embutida (FaceTime HD).
    private static func preferredDevice() -> AVCaptureDevice? {
        let chosen = AppSettings.shared.mirrorDeviceID
        if !chosen.isEmpty,
           let device = availableDevices().first(where: { $0.uniqueID == chosen }) {
            return device
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
            ?? AVCaptureDevice.default(for: .video)
    }

    /// Pede a permissão de câmera se preciso; completion sempre na main.
    static func requestAccess(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }

    /// Liga o espelho num view model (auto-open e API), pedindo permissão antes.
    static func activate(on vm: NotchViewModel, expand: Bool = false) {
        requestAccess { granted in
            guard granted else { return }
            if expand { vm.setExpandedDirect(true) }
            vm.mirrorOn = true
        }
    }

    /// Self-check headless do `release()`: prova que soltar a câmera zera a
    /// sessão sem passar por hardware de verdade (câmera real exige permissão
    /// TCC, que trava num Mac sem ela concedida — rodável via `--selfcheck`).
    /// Só a metade "solta a câmera" da peça (`MirrorServico.parar()` abaixo)
    /// é provada aqui; a outra metade, "desfaz a abertura automática", é
    /// fechamento emprestado do `AppDelegate` (como `registrarWake` nas
    /// peças anteriores) e não tem tipo próprio pra self-check isolado.
    static func _releaseSelfCheck() -> Bool {
        let c = MirrorController()
        c.session = AVCaptureSession()
        c.useCount = 1
        c.release()
        return c.session == nil && c.useCount == 0
    }

    /// Diagnóstico pro GET /status.
    var diagnostics: [String: Any] {
        let auth: String
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: auth = "authorized"
        case .denied: auth = "denied"
        case .restricted: auth = "restricted"
        case .notDetermined: auth = "notDetermined"
        @unknown default: auth = "unknown"
        }
        return [
            "cameraAuth": auth,
            "cameraDevice": Self.preferredDevice()?.localizedName ?? "none",
            "mirrorSessionRunning": session?.isRunning ?? false,
            "mirrorUseCount": useCount,
            "mirrorFailed": falhou,
        ]
    }
}

/// A oitava conversão (tarefa 7): `MirrorController` é `.shared` (singleton —
/// as views seguem lendo `.shared` direto, converter em peça não vira
/// instância), mas ao contrário do Desenho ele não pode conformar
/// `PluginServico` sozinho — soltar a câmera é só metade do "morrer" da
/// peça, a outra metade (desarmar o auto-open por calendário,
/// `mirrorAutoOpened` no `AppDelegate`) não é dele. `MirrorServico` é a
/// borda pequena que junta as duas, no mesmo desenho do `DescansoServico`
/// (`Plugin.swift`): o `AppDelegate` empresta o fechamento no `nascer` do
/// `EspelhoEfeitos`.
final class MirrorServico: PluginServico {
    private let desligarTudo: () -> Void

    init(desligarTudo: @escaping () -> Void) { self.desligarTudo = desligarTudo }

    func parar() {
        desligarTudo()
        MirrorController.shared.release()
    }
}

/// Preview espelhado horizontalmente, como espelho de verdade.
struct MirrorPreviewView: NSViewRepresentable {
    /// Chamado quando a sessão começa a rodar — a câmera leva ~1 s pra acordar
    /// e até lá o preview é um retângulo preto sem explicação.
    var onReady: () -> Void = {}

    final class Coordinator {
        var token: NSObjectProtocol?
        deinit { if let token { NotificationCenter.default.removeObserver(token) } }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class PreviewNSView: NSView {
        var previewLayer: AVCaptureVideoPreviewLayer?

        // frame explícito no layout: autoresizing de CALayer partindo de
        // bounds zero (makeNSView) deixava o preview degenerado (tela preta)
        override func layout() {
            super.layout()
            previewLayer?.frame = bounds
        }
    }

    func makeNSView(context: Context) -> PreviewNSView {
        let view = PreviewNSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        if let session = MirrorController.shared.acquire() {
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.connection?.automaticallyAdjustsVideoMirroring = false
            layer.connection?.isVideoMirrored = true
            view.layer?.addSublayer(layer)
            view.previewLayer = layer
            if session.isRunning {
                DispatchQueue.main.async { onReady() }
            } else {
                context.coordinator.token = NotificationCenter.default.addObserver(
                    forName: .AVCaptureSessionDidStartRunning, object: session,
                    queue: .main) { _ in onReady() }
            }
        } else {
            // sem câmera não há o que esperar: solta a espera pra não travar no spinner
            DispatchQueue.main.async { onReady() }
        }
        return view
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {}

    static func dismantleNSView(_ nsView: PreviewNSView, coordinator: Coordinator) {
        MirrorController.shared.release()
    }
}
