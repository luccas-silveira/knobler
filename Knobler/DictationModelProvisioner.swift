//
//  DictationModelProvisioner.swift
//  Knobler
//
//  Modo headless: `Knobler --download-model` baixa o modelo Parakeet (~461MB)
//  pro cache default do FluidAudio e encerra, SEM subir o NSApp. Chamado pelo
//  `postflight` do cask no `brew install` pra deixar o 1º ditado instantâneo.
//  Best-effort: se falhar (offline no install), o pré-aquecimento do launch
//  (`DictationController.start`) baixa depois — mesmo cache, sem download duplo.
//
//  Imprime progresso streaming (stdout unbuffered) pra o `brew install` não ficar
//  mudo por minutos: % monotônico durante o download, "compilando <modelo>…" na
//  fase de compilação do CoreML (que sozinha leva ~17s em silêncio). O cask mostra
//  isso ao vivo via `system_command print_stdout: true`.
//

import Foundation
import FluidAudio

enum DictationModelProvisioner {
    /// Flag de linha de comando que dispara o modo headless.
    static let flag = "--download-model"

    /// Traduz o progresso do FluidAudio em linhas limpas. O handler é @Sendable e
    /// vem de qualquer task; @unchecked + NSLock protege o estado. Monotônico (o
    /// FluidAudio reseta a fração por modelo na compilação — sem isso viraria um
    /// sawtooth "100%… 50%… 100%").
    private final class ProgressPrinter: @unchecked Sendable {
        private let lock = NSLock()
        private var maxPct = -1
        private var compiled = Set<String>()

        func report(_ progress: DownloadProgress) {
            switch progress.phase {
            case .listing:
                break
            case .downloading:
                // ponytail: o FluidAudio pesa o download em 0.5 do total (compilação
                // é o resto), então ×2 pra "baixando" ler 0→100%. Se mudarem o peso,
                // satura antes/depois — é só cosmético.
                let pct = max(0, min(100, Int(progress.fractionCompleted * 200)))
                lock.lock(); let show = pct > maxPct; if show { maxPct = pct }; lock.unlock()
                if show { print("    baixando modelo de ditado… \(pct)%") }
            case .compiling(let modelName):
                let name = modelName.replacingOccurrences(of: ".mlmodelc", with: "")
                    .trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { break }
                lock.lock(); let show = compiled.insert(name).inserted; lock.unlock()
                if show { print("    compilando \(name)…") }
            }
        }
    }

    /// Baixa o modelo pro cache default e encerra o processo. Nunca retorna:
    /// roda antes do `NSApplication`, então é um CLI puro (sem UI/menu/API).
    static func runAndExit() -> Never {
        setvbuf(stdout, nil, _IONBF, 0)   // unbuffered: as linhas de progresso streamam
        print("==> Baixando o modelo de ditado do Knobler (~461MB) — pode levar alguns minutos…")
        let printer = ProgressPrinter()
        // ponytail: semáforo pra esperar o async num main sincrono; o Task roda no
        // pool cooperativo (fora da main), então progride e sinaliza.
        let sem = DispatchSemaphore(value: 0)
        var code: Int32 = 0
        Task {
            do {
                // Mesma versão/variante (v3/int8, os defaults que o Dictation usa no
                // launch) → mesmo cache. Idempotente: se já existe, é no-op.
                _ = try await AsrModels.download(version: .v3, progressHandler: { progress in
                    printer.report(progress)
                })
                print("==> Modelo de ditado pronto.")
            } catch {
                // stdout (não stderr) pra sobreviver ao print_stderr:false do cask.
                print("Knobler: download do modelo falhou: \(error.localizedDescription)")
                code = 1
            }
            sem.signal()
        }
        sem.wait()
        exit(code)
    }
}
