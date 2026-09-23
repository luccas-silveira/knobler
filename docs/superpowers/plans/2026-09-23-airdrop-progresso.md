# AirDrop: progresso, módulo e card — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Anel com % no recebimento de AirDrop, destino no envio, card final com miniatura e ações, e todo o código de AirDrop em `Knobler/AirDrop/`.

**Architecture:** Regras puras (`AirDropRegras`) testadas por harness; três peças com efeito (envio, progresso de recebimento, coordenador) que só traduzem sinais do sistema pras regras e das regras pro notch. `KnoblerApp` só instancia o coordenador e liga closures. O interceptor passa a delegar alertas de AirDrop.

**Tech Stack:** Swift 5, AppKit/SwiftUI, `Progress.addSubscriber(forFileURL:)`, Accessibility (`AXUIElement`), XcodeGen (glob de pasta — subpasta nova entra sozinha após `xcodegen generate`).

**Spec:** `docs/superpowers/specs/2026-09-23-airdrop-progresso-design.md` (ler a seção "Decisões do grill" — ela prevalece sobre o corpo). Dossiê com as árvores AX reais: `docs/superpowers/research/2026-09-23-airdrop-progresso-research.md`.

## Global Constraints

- Deployment target macOS 14.2; nada de API 15+ sem `#available`.
- Comentários e strings de UI em pt-BR; simplificação deliberada marcada `// ponytail:`.
- Não editar `Knobler.xcodeproj`; rodar `xcodegen generate` após criar/mover arquivos.
- Harness novo = entrada em `tools/check.sh`. Arquivo novo usado pela `NotchView` = linha em `tools/notchview-fontes.txt`.
- O alerta "Recebendo" do sistema **nunca** é fechado nem tocado (fechar interrompe a transferência). Só o "AirDrop Concluído" é fechado.
- `revealsDownloads`/`openURL`: não alargar esquemas; caminhos de arquivo vão por `URL` do `FileManager`, nunca por string de payload.
- Cancelamento de envio continua silencioso (sem card).
- CHANGELOG em `## [Unreleased]`; não mexer em `MARKETING_VERSION`.

## Review Focus

1. Vários arquivos recebidos de uma vez (álbum do iPhone): um anel só com a média, rótulo "N arquivos", um card no fim — testado em Task 1 (`testAgregacao`) e Task 5 (verificação ao vivo).
2. Recebimento interrompido (iPhone cancela no meio): `UNPUBLISH` com fração < 1 limpa o anel e não mostra "Recebido" — testado em Task 1 (`testInterrompido`).
3. Arquivo apagado/movido antes de clicar Abrir/Finder/Prateleira: ação ignora URLs que não existem mais, sem crash — `Sharing.existing` no `perform` da Task 5.
4. App sem Acessibilidade: envio cai no texto sem destino; alerta "Concluído" não é fechado e não há mirror duplicado — Task 2 (`destinoAtual` devolve nil) e Task 5.
5. Dois monitores: um card só no histórico (notificação construída **fora** do laço por tela) — Task 5 usa `publicar`, que já recebe a notificação pronta.

---

### Task 1: Regras puras + harness

**Files:**
- Create: `Knobler/AirDrop/AirDropRegras.swift`
- Create: `tools/airdropcheck.swift`
- Modify: `Knobler/NotificationRules.swift:15-30` (remover `airdropMarker`/`isAirDrop`)
- Modify: `tools/sharingcheck.swift:120-128` (remover os testes de `isAirDrop`, que migram)
- Modify: `tools/check.sh:94` (+ nova linha)

**Interfaces — Produces:**
```swift
enum AirDropFaseAlerta: Equatable { case recebendo, concluido }
enum AirDropRegras {
    static func isAirDrop(appName: String?, title: String) -> Bool
    static func faseDoAlerta(appName: String?, title: String) -> AirDropFaseAlerta?
    static func destino(deDescricao: String) -> (aparelho: String, enviado: Bool)?
    static func rotulo(_ urls: [URL]) -> String
}
struct AirDropRecebimentoEstado {   // acumula NSProgress por arquivo
    mutating func atualizar(_ url: URL, fracao: Double)
    /// devolve o evento de fim quando o último arquivo sai
    mutating func encerrar(_ url: URL) -> AirDropFim?
    var progresso: Double? { get }   // média; nil sem arquivo ativo
    var rotulo: String? { get }
}
enum AirDropFim: Equatable { case recebido([URL]), interrompido }
enum AirDropTexto {
    static func atividadeRecebendo() -> String            // "Recebendo por AirDrop"
    static func atividadeEnviando(destino: String?) -> String
    static func cardEnviado(destino: String?) -> String   // título do card
    static let acoesRecebido: [String]                   // ["Abrir", "Mostrar no Finder", "Prateleira"]
    static let acoesEnviado: [String]                    // ["Mostrar no Finder"]
}
```

- [ ] **Step 1: Escrever o harness que falha**

`tools/airdropcheck.swift`:
```swift
//
//  tools/airdropcheck.swift — regras puras do AirDrop: fase do alerta, destino
//  do envio lido por AX, agregação do progresso de recebimento e textos.
//  NÃO faz parte do alvo do app.
//
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/AirDrop/AirDropRegras.swift tools/airdropcheck.swift -o /tmp/airdropcheck \
//    && /tmp/airdropcheck
//
import Foundation

@main
struct AirDropCheck {
    static func expect(_ ok: Bool, _ msg: String) {
        if !ok { print("FALHOU: \(msg)"); exit(1) }
    }
    static func main() {
        testFase(); testDestino(); testAgregacao(); testInterrompido(); testTextos()
        print("airdropcheck ok")
    }
    // strings reais do dossiê (axdump de 2026-09-23)
    static func testFase() {
        expect(AirDropRegras.faseDoAlerta(appName: "AirDrop", title: "Recebendo um vídeo") == .recebendo, "recebendo")
        expect(AirDropRegras.faseDoAlerta(appName: "AirDrop Concluído", title: "Recebido: um vídeo") == .concluido, "concluído pt")
        expect(AirDropRegras.faseDoAlerta(appName: "AirDrop Completed", title: "Received: a video") == .concluido, "concluído en")
        expect(AirDropRegras.faseDoAlerta(appName: "Mensagens", title: "Oi") == nil, "não é AirDrop")
        expect(AirDropRegras.isAirDrop(appName: "Mensagens", title: "AirDrop, Recebendo uma foto"), "marca no título")
    }
    static func testDestino() {
        let a = AirDropRegras.destino(deDescricao: "iPhone (2), Enviando")
        expect(a?.aparelho == "iPhone (2)" && a?.enviado == false, "enviando")
        let b = AirDropRegras.destino(deDescricao: "iPhone (2), Enviado")
        expect(b?.aparelho == "iPhone (2)" && b?.enviado == true, "enviado")
        expect(AirDropRegras.destino(deDescricao: "Mana") == nil, "sem fase = não é destino ativo")
    }
    static func testAgregacao() {
        var e = AirDropRecebimentoEstado()
        let a = URL(fileURLWithPath: "/tmp/a.mov"), b = URL(fileURLWithPath: "/tmp/b.jpg")
        e.atualizar(a, fracao: 0.2); e.atualizar(b, fracao: 0.6)
        expect(abs((e.progresso ?? -1) - 0.4) < 0.0001, "média")
        expect(e.rotulo == "2 arquivos", "rótulo plural")
        e.atualizar(a, fracao: 1); expect(e.encerrar(a) == nil, "ainda há arquivo ativo")
        e.atualizar(b, fracao: 1)
        expect(e.encerrar(b) == .recebido([a, b]), "fim com os dois")
        expect(e.progresso == nil, "limpo depois do fim")
    }
    static func testInterrompido() {
        var e = AirDropRecebimentoEstado()
        let a = URL(fileURLWithPath: "/tmp/a.mov")
        e.atualizar(a, fracao: 0.3)
        expect(e.encerrar(a) == .interrompido, "fração < 1 = interrompido")
        expect(e.progresso == nil, "limpo")
    }
    static func testTextos() {
        expect(AirDropTexto.atividadeEnviando(destino: "iPhone") == "Enviando pra iPhone", "com destino")
        expect(AirDropTexto.atividadeEnviando(destino: nil) == "Enviando por AirDrop", "sem destino")
        expect(AirDropTexto.cardEnviado(destino: nil) == "Enviado", "card sem destino")
        expect(AirDropRegras.rotulo([URL(fileURLWithPath: "/x/foto.png")]) == "foto.png", "rótulo 1")
    }
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `xcrun swiftc -parse-as-library -swift-version 5 Knobler/AirDrop/AirDropRegras.swift tools/airdropcheck.swift -o /tmp/airdropcheck`
Expected: erro "no such file" / tipos não encontrados.

- [ ] **Step 3: Implementar `Knobler/AirDrop/AirDropRegras.swift`**

```swift
//
//  AirDropRegras.swift
//  Knobler
//
//  Regras puras do AirDrop — sem AppKit, compilam isoladas no airdropcheck.
//  As strings vêm de árvores AX reais (ver docs/superpowers/research/
//  2026-09-23-airdrop-progresso-research.md).
//

import Foundation

enum AirDropFaseAlerta: Equatable { case recebendo, concluido }

enum AirDropFim: Equatable {
    case recebido([URL])
    /// o outro lado cancelou ou a conexão caiu: sem card de "Recebido"
    case interrompido
}

enum AirDropRegras {
    /// Nome de marca: o alerta diz "AirDrop" em qualquer idioma.
    static let marca = "airdrop"

    static func isAirDrop(appName: String?, title: String) -> Bool {
        [appName, title].contains { $0?.lowercased().contains(marca) == true }
    }

    /// O alerta "Recebendo" acompanha a transferência viva; o "Concluído" só
    /// nasce depois do fim — é o único que pode ser fechado.
    static func faseDoAlerta(appName: String?, title: String) -> AirDropFaseAlerta? {
        guard isAirDrop(appName: appName, title: title) else { return nil }
        let texto = "\(appName ?? "") \(title)".lowercased()
        // ponytail: pt/en só; outro idioma cai em .recebendo (seguro: nunca fecha)
        let fim = ["concluído", "concluido", "completed", "recebido:", "received:"]
        return fim.contains { texto.contains($0) } ? .concluido : .recebendo
    }

    /// `AXButton desc="iPhone (2), Enviando"` na janela "AirDrop".
    static func destino(deDescricao desc: String) -> (aparelho: String, enviado: Bool)? {
        guard let virgula = desc.range(of: ", ", options: .backwards) else { return nil }
        let aparelho = String(desc[..<virgula.lowerBound])
        switch desc[virgula.upperBound...].lowercased() {
        case "enviando", "sending": return (aparelho, false)
        case "enviado", "sent": return (aparelho, true)
        default: return nil
        }
    }

    static func rotulo(_ urls: [URL]) -> String {
        urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) arquivos"
    }
}

/// Progresso de recebimento agregado: o iPhone manda um álbum como N arquivos,
/// cada um com seu `NSProgress`. O notch mostra um anel só, com a média.
struct AirDropRecebimentoEstado {
    private var fracoes: [URL: Double] = [:]
    private var ordem: [URL] = []

    mutating func atualizar(_ url: URL, fracao: Double) {
        if fracoes[url] == nil { ordem.append(url) }
        fracoes[url] = fracao
    }

    mutating func encerrar(_ url: URL) -> AirDropFim? {
        guard fracoes[url] != nil else { return nil }
        let pendentes = fracoes.filter { $0.key != url && $0.value < 1 }
        guard pendentes.isEmpty else { return nil }
        let completo = fracoes.values.allSatisfy { $0 >= 1 }
        let urls = ordem
        fracoes = [:]; ordem = []
        return completo ? .recebido(urls) : .interrompido
    }

    var progresso: Double? {
        fracoes.isEmpty ? nil : fracoes.values.reduce(0, +) / Double(fracoes.count)
    }

    var rotulo: String? { ordem.isEmpty ? nil : AirDropRegras.rotulo(ordem) }
}

enum AirDropTexto {
    static func atividadeRecebendo() -> String { "Recebendo por AirDrop" }
    static func atividadeEnviando(destino: String?) -> String {
        destino.map { "Enviando pra \($0)" } ?? "Enviando por AirDrop"
    }
    static func cardEnviado(destino: String?) -> String {
        destino.map { "Enviado pra \($0)" } ?? "Enviado"
    }
    static let acoesRecebido = ["Abrir", "Mostrar no Finder", "Prateleira"]
    static let acoesEnviado = ["Mostrar no Finder"]
}
```

Nota: em `encerrar`, o arquivo que sai com fração < 1 enquanto outros seguem ativos fica no dicionário e torna o lote `.interrompido` no fim — comportamento aceito.

- [ ] **Step 4: Rodar e ver passar**

Run: `xcrun swiftc -parse-as-library -swift-version 5 Knobler/AirDrop/AirDropRegras.swift tools/airdropcheck.swift -o /tmp/airdropcheck && /tmp/airdropcheck`
Expected: `airdropcheck ok`

- [ ] **Step 5: Migrar `isAirDrop`**

Em `Knobler/NotificationRules.swift` apagar `airdropMarker` e `isAirDrop` (linhas ~15-30). Em `tools/sharingcheck.swift` apagar a função de teste que chama `NotificationRules.isAirDrop` (linhas ~120-128) e sua chamada em `main()`. Em `Knobler/NotificationInterceptor.swift:131` trocar `NotificationRules.isAirDrop(` por `AirDropRegras.isAirDrop(` (a Task 5 reescreve esse trecho; aqui só mantém compilando). Adicionar `Knobler/AirDrop/AirDropRegras.swift` em `tools/notchview-fontes.txt` (o interceptor está na lista).

Em `tools/check.sh`, logo após a linha do `sharingcheck`:
```bash
swift_check airdropcheck          Knobler/AirDrop/AirDropRegras.swift tools/airdropcheck.swift
```

- [ ] **Step 6: Gate**

Run: `./tools/check.sh`
Expected: todos passam, incluindo `airdropcheck` e `sharingcheck`.

- [ ] **Step 7: Commit**

```bash
git add Knobler/AirDrop/AirDropRegras.swift tools/airdropcheck.swift tools/check.sh \
  tools/sharingcheck.swift tools/notchview-fontes.txt Knobler/NotificationRules.swift \
  Knobler/NotificationInterceptor.swift
git commit -m "feat: regras puras do AirDrop com harness próprio"
```

---

### Task 2: Envio no módulo + destino lido por AX

**Files:**
- Create: `Knobler/AirDrop/AirDropEnvio.swift` (recebe `AirDropState`, `AirDropSession`, `airdrop`, `airdropFromPanel` de `Knobler/Sharing.swift`)
- Modify: `Knobler/Sharing.swift` (fica só `existing`, `share`, `anchorView`)
- Modify: `Knobler/Shelf.swift:173`, `Knobler/KnoblerApp.swift:161,1673`
- Modify: `tools/check.sh` (linha do `sharingcheck` passa a compilar também `Knobler/AirDrop/AirDropEnvio.swift Knobler/AirDrop/AirDropRegras.swift`), `tools/sharingcheck.swift:8-10` (comentário), `tools/notchview-fontes.txt` (+ `Knobler/AirDrop/AirDropEnvio.swift`)

**Interfaces:**
- Consumes: `AirDropRegras.destino(deDescricao:)`, `AirDropRegras.rotulo(_:)`
- Produces:
```swift
enum AirDropState: Equatable {
    case enviando(label: String, destino: String?)
    case enviado(label: String, destino: String?, urls: [URL])
    case cancelado
    case falhou(String)
}
enum AirDropEnvio {
    static func enviar(_ urls: [URL], onState: ((AirDropState) -> Void)? = nil)
    static func enviarDoPainel(onState: ((AirDropState) -> Void)? = nil)
    /// destino "<aparelho>" lido da janela "AirDrop" do próprio processo; nil sem AX
    static func destinoAtual() -> (aparelho: String, enviado: Bool)?
}
```

- [ ] **Step 1: Teste que falha** — em `tools/sharingcheck.swift`, trocar as referências a `AirDropSession.isCancel` (linhas ~91-97) para continuar iguais (o tipo mantém o nome) e acrescentar:
```swift
static func testEstadoCarregaURLs() {
    let u = [URL(fileURLWithPath: "/tmp/x.png")]
    let s = AirDropState.enviado(label: "x.png", destino: "iPhone", urls: u)
    guard case .enviado(_, let d, let us) = s, d == "iPhone", us == u else {
        print("FALHOU: enviado carrega destino e urls"); exit(1)
    }
}
```
e chamá-lo em `main()`. Rodar a linha do `sharingcheck` com os novos arquivos → falha de compilação (caso `enviado` com 1 campo).

- [ ] **Step 2: Mover e ampliar**

Criar `Knobler/AirDrop/AirDropEnvio.swift` com o conteúdo movido de `Sharing.swift` (doc comments preservados, `Sharing.airdrop` → `AirDropEnvio.enviar`, `airdropFromPanel` → `enviarDoPainel`, `label(for:)` → `AirDropRegras.rotulo`, `existing` continua chamando `Sharing.existing`). Mudanças de comportamento:

```swift
final class AirDropSession: NSObject, NSSharingServiceDelegate {
    private let label: String
    private let urls: [URL]
    private let onState: (AirDropState) -> Void
    private var destino: String?
    private var timer: Timer?
    var onFinish: (() -> Void)?

    init(label: String, urls: [URL], onState: @escaping (AirDropState) -> Void) {
        self.label = label; self.urls = urls; self.onState = onState
    }

    func sharingService(_ service: NSSharingService, willShareItems items: [Any]) {
        onState(.enviando(label: label, destino: nil))
        // o destino só existe depois que o usuário clica no aparelho: sonda a
        // janela até ele aparecer. ponytail: polling de 0,5 s, trocar por
        // AXObserver se a sonda pesar
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.destino == nil,
                  let d = AirDropEnvio.destinoAtual() else { return }
            self.destino = d.aparelho
            self.onState(.enviando(label: self.label, destino: d.aparelho))
        }
    }

    func sharingService(_ service: NSSharingService, didShareItems items: [Any]) {
        timer?.invalidate()
        onState(.enviado(label: label, destino: destino ?? AirDropEnvio.destinoAtual()?.aparelho, urls: urls))
        onFinish?()
    }

    func sharingService(_ service: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        timer?.invalidate()
        onState(Self.isCancel(error) ? .cancelado : .falhou(error.localizedDescription))
        onFinish?()
    }

    static func isCancel(_ error: Error) -> Bool {
        let e = error as NSError
        return e.domain == NSCocoaErrorDomain && e.code == NSUserCancelledError
    }
}
```

`destinoAtual()`:
```swift
/// A janela do AirDrop nasce no processo de quem compartilha — aqui, no
/// próprio Knobler. Cada aparelho é um `AXButton` "<nome>, Enviando|Enviado".
static func destinoAtual() -> (aparelho: String, enviado: Bool)? {
    guard AXIsProcessTrusted() else { return nil }
    let app = AXUIElementCreateApplication(getpid())
    var janelas: AnyObject?
    AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &janelas)
    for janela in (janelas as? [AXUIElement]) ?? [] {
        var pilha = [janela]; var vistos = 0
        while let el = pilha.popLast(), vistos < 300 {
            vistos += 1
            var desc: AnyObject?
            AXUIElementCopyAttributeValue(el, kAXDescriptionAttribute as CFString, &desc)
            if let d = desc as? String, let achado = AirDropRegras.destino(deDescricao: d) {
                return achado
            }
            var filhos: AnyObject?
            AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &filhos)
            pilha += (filhos as? [AXUIElement]) ?? []
        }
    }
    return nil
}
```

Em `enviar`, criar a sessão com `AirDropSession(label: AirDropRegras.rotulo(items), urls: items, onState: onState)`.

Atualizar chamadores: `Shelf.swift:173` → `AirDropEnvio.enviar(urls)`; `KnoblerApp.swift:161` → `AirDropEnvio.enviar(urls)`; `KnoblerApp.swift:1673` → `AirDropEnvio.enviarDoPainel`. Em `aplicarEstadoAirDrop` (KnoblerApp.swift:164-186) ajustar só os padrões de `case` aos novos campos (`.enviando(let label, _)`, `.enviado(let label, _, _)`) — a Task 5 substitui essa função.

- [ ] **Step 3: `xcodegen generate` e gates**

Run: `xcodegen generate && ./tools/check.sh && xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build CODE_SIGNING_ALLOWED=NO -quiet`
Expected: checks passam; `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Knobler/AirDrop/AirDropEnvio.swift Knobler/Sharing.swift Knobler/Shelf.swift \
  Knobler/KnoblerApp.swift tools/check.sh tools/sharingcheck.swift tools/notchview-fontes.txt
git commit -m "refactor: envio de AirDrop no módulo próprio, com destino lido por AX"
```

---

### Task 3: Progresso de recebimento

**Files:**
- Create: `Knobler/AirDrop/AirDropProgresso.swift`

**Interfaces:**
- Consumes: nada das tasks anteriores.
- Produces:
```swift
final class AirDropProgresso {
    /// (arquivo, fração 0…1) a cada mudança; roda na main
    var onFracao: ((URL, Double) -> Void)?
    /// publicador saiu (fim ou interrupção)
    var onFim: ((URL) -> Void)?
    func iniciar()
    func parar()
}
```

- [ ] **Step 1: Implementar**

```swift
//
//  AirDropProgresso.swift
//  Knobler
//
//  Progresso de recebimento: o sistema publica um `NSProgress` por arquivo que
//  chega em ~/Downloads (é o mesmo que o Finder desenha no ícone). Confirmado
//  ao vivo em 2026-09-23: kind `NSProgressFileOperationKindReceiving`, ~6
//  atualizações por segundo. Envio não publica nada — ver AirDropEnvio.
//

import Foundation

final class AirDropProgresso {
    var onFracao: ((URL, Double) -> Void)?
    var onFim: ((URL) -> Void)?

    private var assinatura: Any?
    private var observacoes: [URL: NSKeyValueObservation] = [:]

    func iniciar() {
        guard assinatura == nil else { return }
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        assinatura = Progress.addSubscriber(forFileURL: downloads) { [weak self] progresso in
            // só recebimento: download do Safari/Chrome também publica aqui
            guard let self,
                  progresso.userInfo[.fileOperationKindKey] as? Progress.FileOperationKind == .receiving,
                  let url = progresso.userInfo[.fileURLKey] as? URL
            else { return nil }
            self.observacoes[url] = progresso.observe(\.fractionCompleted, options: [.initial]) { p, _ in
                let f = p.fractionCompleted
                DispatchQueue.main.async { self.onFracao?(url, f) }
            }
            return { [weak self] in
                DispatchQueue.main.async {
                    self?.observacoes[url] = nil
                    self?.onFim?(url)
                }
            }
        }
    }

    func parar() {
        if let assinatura { Progress.removeSubscriber(assinatura) }
        assinatura = nil
        observacoes = [:]
    }
}
```

- [ ] **Step 2: Sonda ao vivo do filtro** — compilar um `main` descartável no scratchpad que instancia `AirDropProgresso`, imprime `onFracao`/`onFim` e roda o RunLoop 120 s:
```bash
cat > /tmp/sondaprog.swift <<'EOF'
import Foundation
let p = AirDropProgresso()
p.onFracao = { print("frac", $0.lastPathComponent, $1) }
p.onFim = { print("fim", $0.lastPathComponent) }
p.iniciar()
RunLoop.main.run(until: Date().addingTimeInterval(120))
EOF
xcrun swiftc -swift-version 5 Knobler/AirDrop/AirDropProgresso.swift /tmp/sondaprog.swift -o /tmp/sondaprog && /tmp/sondaprog
```
Pedir ao usuário um AirDrop do iPhone e depois um download qualquer no navegador. Expected: frações + `fim` para o AirDrop; **nada** para o download do navegador (se o navegador aparecer, o filtro de `kind` está errado — parar e investigar).

- [ ] **Step 3: Commit**

```bash
xcodegen generate
git add Knobler/AirDrop/AirDropProgresso.swift
git commit -m "feat: progresso de recebimento do AirDrop via NSProgress publicado"
```

---

### Task 4: Miniatura no card de notificação

**Files:**
- Modify: `Knobler/NotchNotification.swift:34-42` (campo novo, fora do Codable)
- Modify: `Knobler/NotchView.swift:1408-1415` (`appIcon`)
- Modify: `tools/main.swift` (cenário `notification-airdrop-recebido`)

**Interfaces — Produces:** `NotchNotification.thumbnail: NSImage?` (default nil, não persistido).

- [ ] **Step 1: Cenário de snapshot que falha** — em `tools/main.swift`, junto dos cenários de notificação, adicionar (seguir a forma exata dos `Scenario(name:realNotch:)` vizinhos, ~linha 422):
```swift
Scenario(name: "notification-airdrop-recebido", realNotch: true) { vm, _, _ in
    var n = NotchNotification(appName: "AirDrop", title: "Recebido", body: "IMG_5708.MOV",
                              iconEmoji: "📥")
    n.thumbnail = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { r in
        NSColor.systemTeal.setFill(); r.fill(); return true
    }
    n.actionTitles = ["Abrir", "Mostrar no Finder", "Prateleira"]
    n.actionToken = UUID()
    vm.enqueue(n)
}
```
Run: `./tools/snapshot.sh` → falha de compilação (`thumbnail` não existe).

- [ ] **Step 2: Campo** — em `NotchNotification`, depois de `actionToken`:
```swift
/// Miniatura do arquivo (AirDrop). Só no card vivo: fica fora do Codable,
/// como os botões — o histórico mostra o emoji.
var thumbnail: NSImage? = nil
```
`Equatable` sintetizado compara `NSImage` por identidade — aceitável. Não adicionar a `CodingKeys`.

- [ ] **Step 3: Render** — em `NotchView.appIcon(for:)`:
```swift
@ViewBuilder
private func appIcon(for notification: NotchNotification) -> some View {
    if let thumb = notification.thumbnail {
        Image(nsImage: thumb)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    } else {
        RemoteAvatarView(iconURL: notification.iconURL,
                         iconEmoji: notification.iconEmoji,
                         iconColor: notification.iconColor,
                         fallbackPath: Self.appPath(bundleID: notification.bundleID,
                                                    named: notification.appName))
            .frame(width: 32, height: 32)
    }
}
```

- [ ] **Step 4: Snapshot** — Run: `./tools/snapshot.sh`, abrir `Snapshots/notification-airdrop-recebido.png` com Read. Expected: quadrado teal arredondado no lugar do ícone, três botões visíveis, sem ícone "proibido".

- [ ] **Step 5: Commit**

```bash
git add Knobler/NotchNotification.swift Knobler/NotchView.swift tools/main.swift Snapshots/notification-airdrop-recebido.png
git commit -m "feat: card de notificação aceita miniatura"
```

---

### Task 5: Coordenador, interceptor, ações e ligação

**Files:**
- Create: `Knobler/AirDrop/AirDropCoordenador.swift`
- Modify: `Knobler/KnoblerApp.swift:138-186` (sai `airdropActivity`/`aplicarEstadoAirDrop`; entra o coordenador), `:1215-1230` (ramo de ação), `:1233-1235`, `:1673`
- Modify: `Knobler/NotificationInterceptor.swift:131-166`
- Modify: `tools/notchview-fontes.txt` só se a `NotchView` passar a referenciar o coordenador (não deve).

**Interfaces:**
- Consumes: `AirDropRegras`, `AirDropRecebimentoEstado`, `AirDropTexto`, `AirDropFim`, `AirDropEnvio.enviar/enviarDoPainel`, `AirDropState`, `AirDropProgresso`, `ShelfPreview.thumbnail(of:)`, `NotchNotification.thumbnail`, `ShelfStore.add(_: [URL])`
- Produces:
```swift
final class AirDropCoordenador {
    init(shelf: ShelfStore,
         onActivity: @escaping (NotchActivity?) -> Void,
         onCard: @escaping (NotchNotification) -> Void)
    func iniciar()
    func enviar(_ urls: [URL])
    func enviarDoPainel()
    /// true = o token era de um card de AirDrop (a ação foi tratada)
    func perform(token: UUID, index: Int) -> Bool
}
```

- [ ] **Step 1: Coordenador**

```swift
//
//  AirDropCoordenador.swift
//  Knobler
//
//  Junta envio e recebimento num estado só e traduz pro notch: atividade (anel)
//  durante, card com miniatura e ações no fim. O AppDelegate só liga.
//

import AppKit

final class AirDropCoordenador {
    private let shelf: ShelfStore
    private let onActivity: (NotchActivity?) -> Void
    private let onCard: (NotchNotification) -> Void
    private let progresso = AirDropProgresso()
    private var recebimento = AirDropRecebimentoEstado()
    /// arquivos por card vivo; o índice do botão escolhe a ação
    private var acoes: [UUID: (urls: [URL], recebido: Bool)] = [:]

    init(shelf: ShelfStore,
         onActivity: @escaping (NotchActivity?) -> Void,
         onCard: @escaping (NotchNotification) -> Void) {
        self.shelf = shelf; self.onActivity = onActivity; self.onCard = onCard
    }

    func iniciar() {
        progresso.onFracao = { [weak self] url, f in
            guard let self else { return }
            self.recebimento.atualizar(url, fracao: f)
            self.onActivity(NotchActivity(
                id: "airdrop", title: AirDropTexto.atividadeRecebendo(),
                detail: self.recebimento.rotulo ?? "", progress: self.recebimento.progresso,
                updatedAt: Date()))
        }
        progresso.onFim = { [weak self] url in
            guard let self, let fim = self.recebimento.encerrar(url) else { return }
            self.onActivity(nil)
            if case .recebido(let urls) = fim { self.cardFinal(urls: urls, recebido: true, titulo: "Recebido") }
        }
        progresso.iniciar()
    }

    func enviar(_ urls: [URL]) { AirDropEnvio.enviar(urls) { [weak self] in self?.aplicar($0) } }
    func enviarDoPainel() { AirDropEnvio.enviarDoPainel { [weak self] in self?.aplicar($0) } }

    private func aplicar(_ estado: AirDropState) {
        switch estado {
        case .enviando(let label, let destino):
            onActivity(NotchActivity(id: "airdrop", title: AirDropTexto.atividadeEnviando(destino: destino),
                                     detail: label, progress: nil, updatedAt: Date()))
        case .enviado(_, let destino, let urls):
            onActivity(nil)
            cardFinal(urls: urls, recebido: false, titulo: AirDropTexto.cardEnviado(destino: destino))
        case .cancelado:
            onActivity(nil)
        case .falhou(let motivo):
            onActivity(nil)
            onCard(NotchNotification(appName: "AirDrop", title: "Não deu pra enviar",
                                     body: motivo, iconEmoji: "📤"))
        }
    }

    private func cardFinal(urls: [URL], recebido: Bool, titulo: String) {
        let token = UUID()
        acoes[token] = (urls, recebido)
        // ponytail: teto simples; card que some sem clique deixaria a entrada viva
        if acoes.count > 8, let velho = acoes.keys.first(where: { $0 != token }) { acoes[velho] = nil }
        var n = NotchNotification(appName: "AirDrop", title: titulo,
                                  body: AirDropRegras.rotulo(urls),
                                  iconEmoji: recebido ? "📥" : "📤",
                                  revealsDownloads: recebido)
        n.thumbnail = urls.first.flatMap(ShelfPreview.thumbnail(of:))
        n.actionTitles = recebido ? AirDropTexto.acoesRecebido : AirDropTexto.acoesEnviado
        n.actionToken = token
        onCard(n)
    }

    func perform(token: UUID, index: Int) -> Bool {
        guard let entrada = acoes.removeValue(forKey: token) else { return false }
        // arquivo pode ter sido movido/apagado enquanto o card estava na tela
        let urls = Sharing.existing(entrada.urls)
        guard !urls.isEmpty else { NSSound.beep(); return true }
        let titulos = entrada.recebido ? AirDropTexto.acoesRecebido : AirDropTexto.acoesEnviado
        switch titulos.indices.contains(index) ? titulos[index] : "" {
        case "Abrir": urls.forEach { NSWorkspace.shared.open($0) }
        case "Mostrar no Finder": NSWorkspace.shared.activateFileViewerSelecting(urls)
        case "Prateleira": shelf.add(urls)
        default: break
        }
        return true
    }
}
```

Conferir a assinatura real do init memberwise de `NotchNotification` (a ordem dos argumentos segue a declaração em `NotchNotification.swift:12-56`): `appName, title, body, …, iconEmoji, …, revealsDownloads`. Ajustar a ordem se o compilador reclamar.

- [ ] **Step 2: Interceptor delega** — em `NotificationInterceptor.process`, substituir o trecho `let airdrop = …` até o `onNotification(...)` para AirDrop:
```swift
// AirDrop tem dono próprio (AirDropCoordenador): o "Recebendo" acompanha a
// transferência viva e não pode ser tocado — o anel do notch já mostra o
// progresso, então não vira card. O "Concluído" só nasce depois do fim e é
// substituído pelo card com miniatura e ações.
switch AirDropRegras.faseDoAlerta(appName: parsed.appName, title: parsed.title) {
case .recebendo: return
case .concluido: close(banner); return
case nil: break
}
let buttons = actionButtons(in: banner)
if buttons.isEmpty { close(banner) }
```
e no `NotchNotification(...)` seguinte remover os ternários de `airdrop` (`appName: parsed.appName`, sem `iconEmoji`, sem `revealsDownloads`). Atualizar o comentário da linha 22.

- [ ] **Step 3: AppDelegate liga**

Em `KnoblerApp.swift`: remover `airdropActivity`, `airdropComEstado`, `aplicarEstadoAirDrop` (linhas 141, 156-186). Adicionar:
```swift
private var airdropActivity: NotchActivity?
private lazy var airdrop = AirDropCoordenador(
    shelf: shelf,
    onActivity: { [weak self] in self?.airdropActivity = $0; self?.pushActivity() },
    onCard: { [weak self] in self?.publicar($0) })
```
(`airdropActivity` continua no topo de `currentActivity`, linha 149.) Em `applicationDidFinishLaunching`, junto dos outros serviços: `airdrop.iniciar()`. `viewModel.onAirDrop = { [weak self] urls in self?.airdrop.enviar(urls) }` (linha 1233). `sendAirDrop()` → `airdrop.enviarDoPainel()`. Em `onNotificationAction`, antes do `else` final:
```swift
} else if self.airdrop.perform(token: token, index: index) {
    // card de AirDrop: ação local (abrir/Finder/prateleira)
} else {
    self.interceptor?.perform(token: token, index: index)
}
```

- [ ] **Step 4: Build + gates**

Run: `xcodegen generate && ./tools/check.sh && xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build -quiet`
Expected: checks passam; `BUILD SUCCEEDED`.

- [ ] **Step 5: Verificação ao vivo** (instalar em `/Applications` pelo fluxo de build assinado `Knobler Local Signing`; relançar)
1. iPhone → Mac, um vídeo grande: anel com % subindo no notch; alerta "Recebendo" do sistema intacto; no fim o alerta "Concluído" some e aparece o card com miniatura + Abrir / Mostrar no Finder / Prateleira; cada botão funciona.
2. iPhone → Mac, 3 fotos de uma vez: um anel só, "3 arquivos", um card no fim.
3. iPhone cancela no meio: anel some, sem card "Recebido".
4. Mac → iPhone pelo menu da barra: "Enviando pra <aparelho>" após escolher o destino; card "Enviado pra <aparelho>" com Mostrar no Finder.
5. Fechar a janela do AirDrop sem escolher destino: nada aparece.
6. Download no Chrome/Safari: nenhum anel de AirDrop.

- [ ] **Step 6: Commit**

```bash
git add Knobler/AirDrop/AirDropCoordenador.swift Knobler/KnoblerApp.swift Knobler/NotificationInterceptor.swift
git commit -m "feat: progresso e card de AirDrop no notch, coordenados num módulo"
```

---

### Task 6: Docs e changelog

**Files:**
- Modify: `docs/shelf.md:137-150`, `docs/notifications.md:28-36`, `docs/architecture.md` (seção de serviços: uma linha pro `AirDropCoordenador`), `docs/IDEIAS.md` (mover "Progresso do AirDrop" pra Entregues), `CHANGELOG.md` (`## [Unreleased]`)

- [ ] **Step 1: Reescrever** `docs/shelf.md` "Enviar por AirDrop": envio mostra "Enviando pra <aparelho>" (sem %, porque o sistema não publica progresso de envio — o destino vem da janela do AirDrop por Acessibilidade; sem ela, texto genérico) e card final com Mostrar no Finder.
`docs/notifications.md` AirDrop: recebimento mostra anel com % (vem do progresso que o sistema publica em Downloads); o alerta "Recebendo" continua na tela e nunca é tocado; o "Concluído" é fechado e vira card com miniatura e Abrir / Mostrar no Finder / Prateleira (30 s).
`CHANGELOG.md` em `### Added`: `- AirDrop no notch: anel com porcentagem ao receber, destino ao enviar, e card final com miniatura e ações (Abrir, Mostrar no Finder, Prateleira).`

- [ ] **Step 2: Commit**

```bash
git add docs/shelf.md docs/notifications.md docs/architecture.md docs/IDEIAS.md CHANGELOG.md
git commit -m "docs: AirDrop com progresso e card novo"
```

Nota de release: é feature (MINOR); `tools/release.sh minor` exige `Knobler/Novidades/<versão>.html` — fica pra hora do release, fora deste plano.
