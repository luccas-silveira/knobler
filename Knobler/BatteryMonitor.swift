//
//  BatteryMonitor.swift
//  Knobler
//
//  Live activity de energia: dispara quando o carregador conecta/desconecta
//  e uma vez ao cruzar 20% na bateria. IOKit power sources — em desktops sem
//  bateria a lista vem vazia e nada acontece.
//

import Foundation
import IOKit.ps

final class BatteryMonitor {
    var onEvent: ((_ level: Float, _ charging: Bool) -> Void)?

    private var lastPlugged: Bool?
    private var warnedLow = false

    func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
                .check(fireEvents: true)
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        check(fireEvents: false) // estado inicial sem HUD
    }

    private func check(fireEvents: Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let battery = list.first,
              let description = IOPSGetPowerSourceDescription(info, battery)?
                  .takeUnretainedValue() as? [String: Any]
        else { return }

        let plugged = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
        let maximum = max(1, description[kIOPSMaxCapacityKey] as? Int ?? 100)
        let level = Float(current) / Float(maximum)
        defer { lastPlugged = plugged }

        guard fireEvents else { return }
        if let last = lastPlugged, plugged != last {
            onEvent?(level, plugged)
            if plugged { warnedLow = false }
        } else if !plugged, level <= 0.2, !warnedLow {
            warnedLow = true
            onEvent?(level, false)
        }
    }
}
