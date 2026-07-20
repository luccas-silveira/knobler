//
//  DictationModelProvisioner.swift
//  Knobler
//
//  Modo headless: `Knobler --download-model` baixa o modelo Parakeet (~600MB)
//  pro cache default do FluidAudio e encerra, SEM subir o NSApp. Chamado pelo
//  `postflight` do cask no `brew install` pra deixar o 1º ditado instantâneo.
//  Best-effort: se falhar (offline no install), o pré-aquecimento do launch
//  (`DictationController.start`) baixa depois — mesmo cache, sem download duplo.
//

import Foundation
import FluidAudio

enum DictationModelProvisioner {
    /// Flag de linha de comando que dispara o modo headless.
    static let flag = "--download-model"

    /// Baixa o modelo pro cache default e encerra o processo. Nunca retorna:
    /// roda antes do `NSApplication`, então é um CLI puro (sem UI/menu/API).
    static func runAndExit() -> Never {
        // ponytail: semáforo pra esperar o async num main sincrono; o Task roda no
        // pool cooperativo (fora da main), então progride e sinaliza.
        let sem = DispatchSemaphore(value: 0)
        var code: Int32 = 0
        Task {
            do {
                // Mesma versão/variante (v3/int8, os defaults que o Dictation usa no
                // launch) → mesmo cache. Idempotente: se já existe, é no-op.
                let dir = try await AsrModels.download(version: .v3)
                print("Knobler: modelo de ditado pronto em \(dir.path)")
            } catch {
                FileHandle.standardError.write(
                    Data("Knobler: download do modelo falhou: \(error.localizedDescription)\n".utf8))
                code = 1
            }
            sem.signal()
        }
        sem.wait()
        exit(code)
    }
}
