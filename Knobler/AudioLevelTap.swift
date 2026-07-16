//
//  AudioLevelTap.swift
//  Knobler
//
//  Níveis de áudio reais do Spotify via CoreAudio process tap (macOS 14.2+),
//  como o Dynamic Island do iPhone: tap no processo → FFT (Accelerate) →
//  5 bandas de frequência normalizadas em 0…1. Mecânica do AudioCap/rtaudio.
//  Pede permissão de "gravação de áudio do sistema" no primeiro uso; sem
//  permissão, `bands` fica nil e a UI cai no visualizador sintético.
//

import Accelerate
import AudioToolbox
import Combine
import CoreAudio
import Foundation

final class SystemAudioLevels: ObservableObject {
    /// 5 bandas (graves → agudos), 0…1, publicadas a ~30Hz. nil = sem tap.
    @Published private(set) var bands: [Float]?

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var running = false

    // FFT
    private static let fftSize = 1024
    private static let log2n = vDSP_Length(10)
    private let fftSetup = vDSP_create_fftsetup(vDSP_Length(10), FFTRadix(kFFTRadix2))
    private var window = [Float](repeating: 0, count: fftSize)
    private var ring = [Float](repeating: 0, count: fftSize)
    private var ringFill = 0

    // suavização + auto-gain POR BANDA (graves têm sempre mais energia; sem
    // normalização individual as barras dos agudos ficam permanentemente baixas)
    private var smoothed = [Float](repeating: 0, count: 5)
    private var runningMax = [Float](repeating: -6, count: 5)
    private var lastPublish = Date.distantPast

    // bordas das bandas em bins de FFT (~47Hz/bin a 48kHz):
    // 47–140, 140–420, 420–1.2k, 1.2k–4k, 4k–12k Hz
    private static let bandEdges = [1, 3, 9, 26, 85, 256]

    init() {
        vDSP_hann_window(&window, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_NORM))
    }

    // MARK: - Ciclo de vida

    func start(pid: pid_t) {
        guard !running else { return }

        var processObj = AudioObjectID(kAudioObjectUnknown)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var qualifier = pid
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address,
            UInt32(MemoryLayout<pid_t>.size), &qualifier, &size, &processObj
        ) == noErr, processObj != kAudioObjectUnknown else {
            NSLog("knobler tap: processo de áudio não encontrado para pid %d", pid)
            return
        }

        let description = CATapDescription(stereoMixdownOfProcesses: [processObj])
        description.name = "Knobler Tap"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr,
              tapID != kAudioObjectUnknown else {
            NSLog("knobler tap: AudioHardwareCreateProcessTap falhou (permissão?)")
            return
        }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Knobler Levels",
            kAudioAggregateDeviceUIDKey: "com.zoi.knobler.levels",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true,
                ]
            ],
        ]
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID) == noErr
        else {
            NSLog("knobler tap: aggregate device falhou")
            teardown()
            return
        }

        let status = AudioDeviceCreateIOProcIDWithBlock(
            &ioProcID, aggregateID, DispatchQueue(label: "knobler.tap")
        ) { [weak self] _, inputData, _, _, _ in
            self?.process(inputData)
        }
        guard status == noErr, let ioProcID else {
            NSLog("knobler tap: IOProc falhou")
            teardown()
            return
        }
        guard AudioDeviceStart(aggregateID, ioProcID) == noErr else {
            NSLog("knobler tap: start falhou")
            teardown()
            return
        }

        running = true
        NSLog("knobler tap: capturando áudio do pid %d", pid)
    }

    func stop() {
        guard running else { return }
        running = false
        teardown()
        DispatchQueue.main.async { [weak self] in
            self?.bands = nil
            self?.smoothed = [0, 0, 0, 0, 0]
            self?.runningMax = [Float](repeating: -6, count: 5)
        }
    }

    private func teardown() {
        if let ioProcID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
    }

    deinit {
        teardown()
        vDSP_destroy_fftsetup(fftSetup)
    }

    // MARK: - Áudio → bandas (thread do IOProc)

    private func process(_ list: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: list))
        guard let buffer = buffers.first, let data = buffer.mData else { return }
        let channels = max(1, Int(buffer.mNumberChannels))
        let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float32>.size * channels)
        guard frames > 0 else { return }
        let samples = data.assumingMemoryBound(to: Float32.self)

        // mono (canal 0) no ring buffer; FFT a cada enchida
        var index = 0
        while index < frames {
            let take = min(frames - index, Self.fftSize - ringFill)
            for offset in 0..<take {
                ring[ringFill + offset] = samples[(index + offset) * channels]
            }
            ringFill += take
            index += take
            if ringFill == Self.fftSize {
                analyze()
                ringFill = 0
            }
        }
    }

    private func analyze() {
        var windowed = [Float](repeating: 0, count: Self.fftSize)
        vDSP_vmul(ring, 1, window, 1, &windowed, 1, vDSP_Length(Self.fftSize))

        let half = Self.fftSize / 2
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)

        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(
                    realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                windowed.withUnsafeBytes {
                    vDSP_ctoz(
                        $0.bindMemory(to: DSPComplex.self).baseAddress!, 2,
                        &split, 1, vDSP_Length(half))
                }
                vDSP_fft_zrip(fftSetup!, &split, 1, Self.log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }

        // energia média por banda, escala log
        var levels = [Float](repeating: 0, count: 5)
        for band in 0..<5 {
            let lo = Self.bandEdges[band], hi = Self.bandEdges[band + 1]
            var sum: Float = 0
            for bin in lo..<hi { sum += magnitudes[bin] }
            levels[band] = log10(sum / Float(hi - lo) + 1e-9)
        }

        // por banda: janela de ~22dB abaixo do pico recente vira 0…1 — assim a
        // barra vive no meio e só a batida encosta no topo (pico decai devagar)
        let window: Float = 2.2 // décadas de energia (log10)
        for band in 0..<5 {
            runningMax[band] = max(runningMax[band] - 0.001, levels[band])
            let normalized = (levels[band] - (runningMax[band] - window)) / window
            let clamped = min(1, max(0, normalized))
            // curva côncava espalha as alturas; sem ela fica tudo cravado no topo
            let shaped = pow(clamped, 1.8) * 0.92
            // ataque rápido, queda suave — o "pulo" na batida vem daqui
            let previous = smoothed[band]
            smoothed[band] = shaped > previous
                ? previous + (shaped - previous) * 0.55
                : previous + (shaped - previous) * 0.18
        }

        // publica a ~30Hz na main
        let now = Date()
        guard now.timeIntervalSince(lastPublish) > 1.0 / 30.0 else { return }
        lastPublish = now
        let snapshot = smoothed
        DispatchQueue.main.async { [weak self] in
            self?.bands = snapshot
        }
    }
}
