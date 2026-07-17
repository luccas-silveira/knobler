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

final class MirrorController {
    static let shared = MirrorController()

    private var session: AVCaptureSession?
    // ponytail: refcount porque dois monitores podem exibir o mesmo preview
    private var useCount = 0

    func acquire() -> AVCaptureSession? {
        useCount += 1
        if let session { return session }
        let session = AVCaptureSession()
        session.sessionPreset = .medium
        guard let device = Self.preferredDevice(),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            NSLog("knobler mirror: câmera indisponível")
            return nil
        }
        session.addInput(input)
        self.session = session
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        return session
    }

    func release() {
        useCount = max(0, useCount - 1)
        guard useCount == 0, let session else { return }
        self.session = nil
        DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
    }

    /// A default(for:) pode devolver uma capturadora USB sem sinal —
    /// prefere a câmera embutida (FaceTime HD).
    private static func preferredDevice() -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
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
        ]
    }
}

/// Preview espelhado horizontalmente, como espelho de verdade.
struct MirrorPreviewView: NSViewRepresentable {
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
        }
        return view
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {}

    static func dismantleNSView(_ nsView: PreviewNSView, coordinator: ()) {
        MirrorController.shared.release()
    }
}
