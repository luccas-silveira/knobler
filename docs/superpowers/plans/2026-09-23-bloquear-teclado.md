# Bloquear teclado Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Modo que descarta todo evento de teclado enquanto ligado; destrava clicando no card do notch.

**Architecture:** Singleton `TecladoBloqueado` com `CGEventTap` próprio, criado só enquanto ativo. Novo `NotchMode.tecladoBloqueado` no topo da cadeia de prioridade. Liga pelo menu e pela API local.

**Tech Stack:** Swift 5, AppKit + SwiftUI, CoreGraphics (`CGEventTap`), Carbon (`IsSecureEventInputEnabled`).

**Spec:** `docs/superpowers/specs/2026-09-23-bloquear-teclado-design.md`

## Global Constraints

- Deployment target macOS 14.2; nada de API mais nova sem `#available`.
- Strings de UI e comentários em pt-BR.
- Estado só em memória — nunca em `UserDefaults`.
- Não editar `Knobler.xcodeproj`; arquivo novo exige `xcodegen generate`.
- Arquivo novo usado pela `NotchView` entra em `tools/notchview-fontes.txt`.
- Check novo entra em `tools/check.sh`.
- Mudança anotada em `## [Unreleased]` do `CHANGELOG.md` (hoje com conflito `UU` de outra sessão — resolver antes de tocar).

## Review Focus

- Tap morre por timeout durante o bloqueio: tem que reativar, não liberar o teclado.
- Ligar duas vezes (menu + API): não pode criar dois taps nem vazar o primeiro.
- Dois monitores: o card aparece e destrava em qualquer um.
- `tapCreate` falha (sem Acessibilidade): `ativo` continua `false`, nada fica meio-ligado.
- Entrada segura ativa: recusa, notifica, não liga.

---

### Task 1: `TecladoBloqueado` + check

**Files:**
- Create: `Knobler/TecladoBloqueado.swift`
- Create: `tools/tecladocheck.swift`
- Modify: `tools/check.sh`

**Interfaces:**
- Produces: `TecladoBloqueado.shared`, `@Published private(set) var ativo: Bool`, `func ligar() -> TecladoBloqueado.Recusa?`, `func desligar()`, `enum Recusa { case semAcessibilidade, entradaSegura }`, `static func deveEngolir(_ tipo: CGEventType) -> Bool`.

- [ ] **Step 1: Check que falha**

```swift
//
//  tools/tecladocheck.swift — self-check do bloqueio de teclado.
//  NÃO faz parte do alvo do app.
//
//  Rodar:
//    xcrun swiftc -parse-as-library -swift-version 5 \
//      Knobler/TecladoBloqueado.swift tools/tecladocheck.swift \
//      -o /tmp/tecladocheck && /tmp/tecladocheck
//
import CoreGraphics

@main
struct TecladoCheck {
    static func main() {
        let sys = CGEventType(rawValue: 14)!
        for t in [CGEventType.keyDown, .keyUp, .flagsChanged, sys] {
            precondition(TecladoBloqueado.deveEngolir(t), "devia engolir \(t.rawValue)")
        }
        for t in [CGEventType.tapDisabledByTimeout, .tapDisabledByUserInput, .leftMouseDown, .mouseMoved] {
            precondition(!TecladoBloqueado.deveEngolir(t), "não devia engolir \(t.rawValue)")
        }
        let t = TecladoBloqueado()
        t.desligar()                       // desligar sem ligar não quebra
        precondition(!t.ativo)
        print("tecladocheck: ok")
    }
}
```

- [ ] **Step 2: Rodar — falha** (`cannot find 'TecladoBloqueado'`), com o comando do cabeçalho.

- [ ] **Step 3: Implementar**

```swift
// Bloqueio de teclado pra limpeza: engole todo evento de teclado enquanto ativo.
// Estado só em memória — crash ou saída do app libera o teclado.
import AppKit
import Carbon
import CoreGraphics

final class TecladoBloqueado: ObservableObject {
    static let shared = TecladoBloqueado()

    enum Recusa { case semAcessibilidade, entradaSegura }

    @Published private(set) var ativo = false
    private var tap: CFMachPort?
    private var fonte: CFRunLoopSource?

    private static let systemDefined = CGEventType(rawValue: 14)!

    static func deveEngolir(_ tipo: CGEventType) -> Bool {
        tipo == .keyDown || tipo == .keyUp || tipo == .flagsChanged || tipo == systemDefined
    }

    /// Devolve o motivo quando não liga.
    @discardableResult
    func ligar() -> Recusa? {
        if ativo { return nil }
        // Com campo de senha focado o macOS entrega as teclas por fora do tap.
        if IsSecureEventInputEnabled() { return .entradaSegura }
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged, Self.systemDefined]
            .reduce(CGEventMask(0)) { $0 | CGEventMask(1 << $1.rawValue) }
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, tipo, evento, refcon in
                guard let refcon else { return Unmanaged.passRetained(evento) }
                let eu = Unmanaged<TecladoBloqueado>.fromOpaque(refcon).takeUnretainedValue()
                if tipo == .tapDisabledByTimeout || tipo == .tapDisabledByUserInput {
                    if let tap = eu.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passRetained(evento)
                }
                return TecladoBloqueado.deveEngolir(tipo) ? nil : Unmanaged.passRetained(evento)
            },
            userInfo: refcon)
        else { return .semAcessibilidade }
        let fonte = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), fonte, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.fonte = fonte
        ativo = true
        return nil
    }

    func desligar() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let fonte { CFRunLoopRemoveSource(CFRunLoopGetMain(), fonte, .commonModes) }
        tap = nil
        fonte = nil
        ativo = false
    }
}
```

- [ ] **Step 4: Rodar — `tecladocheck: ok`.**

- [ ] **Step 5: Acrescentar ao `tools/check.sh`** a linha no mesmo formato das vizinhas (compilar com `-parse-as-library` os dois arquivos acima). Rodar `./tools/check.sh`.

- [ ] **Step 6: Commit** — `feat: TecladoBloqueado engole eventos de teclado`.

### Task 2: Modo do notch + card

**Files:**
- Modify: `Knobler/NotchPresentation.swift:5-41,144-169,236`
- Modify: `Knobler/NotchViewModel.swift:446-453`
- Modify: `Knobler/NotchView.swift:19,~150-214,847,927`
- Modify: `tools/notchview-fontes.txt`, `tools/main.swift:246+,762`

**Interfaces:**
- Consumes: `TecladoBloqueado.shared.ativo`, `.desligar()`.
- Produces: `NotchMode.tecladoBloqueado`, `NotchContentState.tecladoBloqueado: Bool`.

- [ ] **Step 1:** Em `NotchPresentation.swift`: `case tecladoBloqueado` no enum; `var tecladoBloqueado = false` no struct; primeira linha de `mode`: `if tecladoBloqueado { return .tecladoBloqueado }`; `keyboard` devolve `false` pra ele; em `size`, mesmo tamanho do `.update` (`380 × topInset+72`); cobrir o `switch` de :236 como `.update`.
- [ ] **Step 2:** Em `contentState()` (`NotchViewModel.swift:446`), passar `tecladoBloqueado: TecladoBloqueado.shared.ativo`.
- [ ] **Step 3:** Em `NotchView`: `@ObservedObject private var teclado = TecladoBloqueado.shared` (junto de :19); no `switch mode`, ramo novo copiando o de `.update` (:208-213):

```swift
case .tecladoBloqueado:
    HStack(spacing: 10) {
        Image(systemName: "keyboard.badge.ellipsis")
        VStack(alignment: .leading, spacing: 2) {
            Text("Teclado bloqueado").font(.system(size: 13, weight: .semibold))
            Text("Clique para destravar").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        Spacer()
    }
    .foregroundStyle(.white)
    .frame(width: 380 - 40)
    .padding(.top, topInset)
    .contentShape(Rectangle())
    .onTapGesture { TecladoBloqueado.shared.desligar() }
    .transition(.move(edge: .top).combined(with: .opacity))
```

  Cobrir os `switch` de :847 e :927 como `.update`.
- [ ] **Step 4:** `Knobler/TecladoBloqueado.swift` em `tools/notchview-fontes.txt`. Em `tools/main.swift`: reset `TecladoBloqueado.shared.desligar()` junto de :762; cenário novo — o harness não liga tap, então exponha pra ele `#if DEBUG`-free um setter de teste: em `TecladoBloqueado`, `func _simularAtivo(_ v: Bool) { ativo = v }` (padrão `_pararSelfCheck` do `QuickNote`), e

```swift
Scenario(name: "teclado-bloqueado", realNotch: true) { _,_,_ in TecladoBloqueado.shared._simularAtivo(true) },
```

- [ ] **Step 5:** `./tools/snapshot.sh`; abrir `Snapshots/teclado-bloqueado.png` e conferir o card. `./tools/check.sh`.
- [ ] **Step 6: Commit** — `feat: card de teclado bloqueado no notch`.

### Task 3: Menu, API, docs

**Files:**
- Modify: `Knobler/KnoblerApp.swift:~649,1494,1533`
- Modify: `Knobler/NotchAPIServer.swift:26-41,~314,410`
- Modify: `docs/local-api.md`, `CHANGELOG.md`

- [ ] **Step 1:** Em `KnoblerApp`, ação única usada por menu e API:

```swift
@objc private func bloquearTeclado() {
    switch TecladoBloqueado.shared.ligar() {
    case .semAcessibilidade?: openAccessibilityPane()
    case .entradaSegura?:
        let n = NotchNotification(/* mesmos campos de uma notificação interna existente */
            title: "Teclado não bloqueado", body: "Saia do campo de senha antes de bloquear")
        notches.values.forEach { $0.vm.enqueue(n) }   // construída ACIMA do laço (dedupe)
    case nil: break
    }
}
```

  Copie o init de `NotchNotification` de uma notificação interna existente (ex.: a do Pomodoro) — `grep -n "NotchNotification(" Knobler/*.swift`.
- [ ] **Step 2:** Menu, seção Ferramentas após :1494: `addItem(menu, "Bloquear teclado", "keyboard.badge.ellipsis", #selector(bloquearTeclado))`.
- [ ] **Step 3:** API: `var onTeclado: ((Bool) -> Void)?`; rotas `POST /keyboard/lock` e `POST /keyboard/unlock` no molde de `/mirror` (:300-314); ambas na string de uso (:410). Wiring perto de :649: `apiServer.onTeclado = { [weak self] on in on ? self?.bloquearTeclado() : TecladoBloqueado.shared.desligar() }`.
- [ ] **Step 4:** `docs/local-api.md` — seção por rota no formato de `/mirror`. `CHANGELOG.md` `[Unreleased]`: "Bloquear teclado pra limpeza (menu da barra ou API); clique no notch destrava."
- [ ] **Step 5: Verificar ao vivo:** build (`xcodebuild ... build`), instalar em `/Applications`, ligar pelo menu, digitar (nada sai), apertar volume (nada), clicar no card (volta). `curl -X POST 127.0.0.1:4477/keyboard/lock` e depois clicar. Com o foco num campo de senha, ligar: tem que recusar com aviso.
- [ ] **Step 6: Commit** — `feat: bloquear teclado pelo menu e pela API`.
