//
//  BluetoothMonitor.swift
//  Knobler
//
//  AirPods no notch: conexão detectada por notificação event-driven do
//  IOBluetooth (sem polling parado); bateria lida do system_profiler no
//  connect + poll de 60s enquanto conectado. system_profiler é a fonte de
//  verdade tanto pra "há AirPods?" quanto pros níveis — o IOBluetooth só
//  dispara a checagem, evitando poll quando nada mudou.
//

import Foundation
import IOBluetooth

final class BluetoothMonitor: NSObject {
    /// Connect novo ou bateria cruzando o limite baixo → card transitório.
    var onAnnounce: ((AirPodsBattery) -> Void)?
    /// Refresh silencioso (mantém a faixa de bateria atual).
    var onUpdate: ((AirPodsBattery) -> Void)?
    /// AirPods desconectaram → limpar o estado no notch.
    var onDisconnect: (() -> Void)?

    private var connectNote: IOBluetoothUserNotification?
    private var disconnectNotes: [IOBluetoothUserNotification] = []
    private var pollTimer: Timer?
    private var present = false
    private var warnedLow = false

    private let lowThreshold = 10   // avisa ao cair pra ≤10%
    private let recoverThreshold = 20  // rearma o aviso ao voltar >20%

    func start() {
        guard connectNote == nil else { return }   // idempotente (sink chama sempre)
        connectNote = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(bluetoothConnected(_:device:)))
        // AirPods já conectados ao subir: registra disconnect e popula sem card
        for d in (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [])
        where d.isConnected() {
            registerDisconnect(d)
        }
        refresh(announce: false)
    }

    func stop() {
        connectNote?.unregister()
        connectNote = nil
        disconnectNotes.forEach { $0.unregister() }
        disconnectNotes.removeAll()
        pollTimer?.invalidate()
        pollTimer = nil
        if present { present = false; onDisconnect?() }
        warnedLow = false
    }

    @objc private func bluetoothConnected(_ note: IOBluetoothUserNotification,
                                          device: IOBluetoothDevice) {
        registerDisconnect(device)
        refresh(announce: true)
    }

    @objc private func bluetoothDisconnected(_ note: IOBluetoothUserNotification,
                                             device: IOBluetoothDevice) {
        refresh(announce: true)
    }

    private func registerDisconnect(_ device: IOBluetoothDevice) {
        if let n = device.register(forDisconnectNotification: self,
                                   selector: #selector(bluetoothDisconnected(_:device:))) {
            disconnectNotes.append(n)
        }
    }

    /// Lê a bateria e reconcilia o estado. `announce` = evento de usuário
    /// (connect/disconnect) que pode mostrar card; poll usa announce=false.
    private func refresh(announce: Bool) {
        readBattery { [weak self] battery in
            guard let self else { return }
            guard let battery else {
                if self.present {
                    self.present = false
                    self.warnedLow = false
                    self.stopPolling()
                    self.onDisconnect?()
                }
                return
            }

            let wasPresent = self.present
            self.present = true
            self.startPolling()
            self.onUpdate?(battery)   // sempre atualiza a faixa

            if !wasPresent, announce {
                self.onAnnounce?(battery)   // primeira conexão → card
            }

            // aviso de bateria baixa, uma vez por ciclo (rearma ao recarregar)
            if let min = battery.minLevel {
                if min <= self.lowThreshold, !self.warnedLow {
                    self.warnedLow = true
                    self.onAnnounce?(battery)
                } else if min > self.recoverThreshold {
                    self.warnedLow = false
                }
            }
        }
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        // ponytail: poll fixo de 60s só enquanto conectado; subir se a bateria
        // parecer defasada demais no card.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) {
            [weak self] _ in self?.refresh(announce: false)
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Roda system_profiler fora da main e devolve o parse na main.
    private func readBattery(_ completion: @escaping (AirPodsBattery?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            task.arguments = ["SPBluetoothDataType", "-json"]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice
            var battery: AirPodsBattery?
            do {
                try task.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                battery = AirPodsBattery.parse(from: data)
            } catch {
                NSLog("knobler bluetooth: %@", error.localizedDescription)
            }
            DispatchQueue.main.async { completion(battery) }
        }
    }
}
