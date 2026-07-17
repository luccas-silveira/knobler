//
//  MicMonitor.swift
//  Knobler
//
//  Indicador de microfone: pontinho laranja no notch enquanto algum app
//  captura o input padrão (kAudioDevicePropertyDeviceIsRunningSomewhere).
//  Só observa metadados do CoreAudio — não toca no áudio, não pede permissão.
//

import CoreAudio
import Foundation

final class MicMonitor {
    var onChange: ((Bool) -> Void)?

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var runningAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private var defaultAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private lazy var runningListener: AudioObjectPropertyListenerBlock = {
        [weak self] _, _ in self?.publish()
    }
    private lazy var defaultListener: AudioObjectPropertyListenerBlock = {
        [weak self] _, _ in self?.attachToDefaultDevice()
    }

    func start() {
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &defaultAddress,
            .main, defaultListener)
        attachToDefaultDevice()
    }

    var isRunning: Bool {
        guard device != kAudioObjectUnknown else { return false }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(
            device, &runningAddress, 0, nil, &size, &value) == noErr
        else { return false }
        return value == 1
    }

    func publish() {
        onChange?(isRunning)
    }

    private func attachToDefaultDevice() {
        if device != kAudioObjectUnknown {
            AudioObjectRemovePropertyListenerBlock(
                device, &runningAddress, .main, runningListener)
        }
        device = Self.defaultInputDevice()
        if device != kAudioObjectUnknown {
            AudioObjectAddPropertyListenerBlock(
                device, &runningAddress, .main, runningListener)
        }
        publish()
    }

    private static func defaultInputDevice() -> AudioObjectID {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return deviceID
    }
}
