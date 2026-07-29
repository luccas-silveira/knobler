# Fechar as pendências abertas — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** fechar as quatro pendências que dependem de nós — o ramo trancado do keychain sem cobertura, o teste de aceitação do update pelo brew, o caminho direto do updater e o grafo desatualizado.

**Architecture:** a decisão "pareado / trancado / nunca pareado" sai do `WebhookClient` (onde está misturada com rede) e vira função pura em `WebhookKeychainStore`, coberta por um self-check no `check.sh` — é a única mudança de código. O resto é validação ao vivo: publica-se a **0.10.1** como veículo e exercita-se cada caminho do updater contra ela, primeiro pelo brew, depois com o app fora do brew. O ramo trancado do keychain é reproduzido gravando os segredos pelo binário `security`, cuja ACL o app não consegue abrir — o mesmo estado que uma troca de assinatura produziria, sem tocar na assinatura.

**Tech Stack:** Swift 5 / AppKit / SwiftUI, `swiftc` avulso para os self-checks, `tools/check.sh`, `tools/release.sh`, Homebrew cask, `security(1)`.

## Global Constraints

- Deployment target **macOS 14.2**. Nada de `glassEffect`/API de macOS 26 sem `if #available(macOS 26, *)`.
- Comentários e strings de UI em **pt-BR**.
- `Knobler.xcodeproj` é artefato: **nunca** editar à mão. Alvos e settings vivem em `project.yml`; rode `xcodegen generate` só se adicionar/remover arquivo do alvo.
- A versão canônica é a tag. **Só** `tools/release.sh` escreve `MARKETING_VERSION` e cria tag.
- Simplificações deliberadas levam comentário `// ponytail:`.
- O clone canônico do tap é o do `brew` (`brew --repo luccas-silveira/knobler`); `~/Desktop/Ferramentas/homebrew-knobler` é symlink pra ele.
- Fora do escopo: **notarização**. O caminho já existe em `tools/release.sh` atrás de `KNOBLER_NOTARY_PROFILE` e espera conta Apple Developer paga, que não temos. A Task 6 só registra isso.

---

## File Structure

| Arquivo | Responsabilidade |
|---|---|
| `Knobler/WebhookKeychainStore.swift` (modificar) | ganha `WebhookPairingState` e a função pura `pairingState(load:exists:)`. Continua sem dependência além de `Security`/`Foundation`, o que deixa o self-check compilar esse arquivo sozinho. |
| `Knobler/WebhookClient.swift` (modificar, ~83-97) | `ensurePairedThenConnect()` passa a consumir a função pura em vez de repetir a decisão inline. |
| `tools/webhookcheck.swift` (criar) | self-check das três decisões, no molde do `tools/updatercheck.swift`. |
| `tools/check.sh` (modificar, linha ~65) | registra o `webhookcheck` junto dos outros `swift_check`. |
| `CHANGELOG.md` (modificar) | entrada em `## [Unreleased]` — sem ela o `release.sh` aborta (`tools/release.sh:84`). |
| `HANDOFF.md` (modificar) | resultado de cada validação. |

---

### Task 1: estado de pareamento como função pura + self-check

A decisão está hoje espalhada em `WebhookClient.swift:83-97`: dois `load` seguidos, e um `exists` no `else` pra separar "trancado" de "nunca pareado". É a lógica que a pendência quer cobrir, e ela não tem como ser testada onde está — o método que a contém também abre `URLSession` e fala com o relay.

**Files:**
- Modify: `Knobler/WebhookKeychainStore.swift` (adicionar ao fim, antes do `// MARK: Token por perfil`)
- Modify: `Knobler/WebhookClient.swift:83-97`
- Modify: `tools/check.sh:65`
- Test: `tools/webhookcheck.swift` (criar)

**Interfaces:**
- Consumes: `WebhookKeychainStore.Account` (`.deviceId`, `.deviceSecret`, `.publishToken`), `load(_:)`, `exists(_:)` — já existem no arquivo.
- Produces: `WebhookKeychainStore.PairingState` (`enum ... : Equatable { case ready(publishToken: String), locked, unpaired }`, aninhado no store — o tipo só faz sentido junto dele) e `static func pairingState(load:exists:) -> PairingState`, consumidos pelo `WebhookClient` e pelo self-check.

- [ ] **Step 1: Escrever o self-check que falha**

Criar `tools/webhookcheck.swift`:

```swift
//
//  tools/webhookcheck.swift — self-check da decisão de pareamento do relay.
//  NÃO faz parte do alvo do app.
//
//  Rodar:
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/WebhookKeychainStore.swift tools/webhookcheck.swift \
//    -o /tmp/webhookcheck && /tmp/webhookcheck
//

import Foundation

@main
struct WebhookCheck {
    static func main() {
        testReady()
        testLocked()
        testHalfOpen()
        testUnpaired()
        print("✅ webhookcheck ok")
    }

    /// Os dois segredos abriram: é o caminho feliz, com o link publicável.
    static func testReady() {
        let s = WebhookKeychainStore.pairingState(
            load: { $0 == .publishToken ? "tok" : "sec" },
            exists: { _ in true })
        assert(s == .ready(publishToken: "tok"), "dois segredos abertos → ready")
    }

    /// O item está lá mas a ACL não abre: NÃO pode virar registro novo, senão o
    /// link público que o usuário já colou lá fora morre em silêncio.
    static func testLocked() {
        let s = WebhookKeychainStore.pairingState(
            load: { _ in nil },
            exists: { _ in true })
        assert(s == .locked, "existe mas não abre → locked")
    }

    /// Meio segredo não serve pra nada: sem o deviceSecret não há como autenticar.
    static func testHalfOpen() {
        let s = WebhookKeychainStore.pairingState(
            load: { $0 == .publishToken ? "tok" : nil },
            exists: { _ in true })
        assert(s == .locked, "só metade dos segredos → locked")
    }

    /// Keychain limpo: primeiro uso, pode registrar.
    static func testUnpaired() {
        let s = WebhookKeychainStore.pairingState(
            load: { _ in nil },
            exists: { _ in false })
        assert(s == .unpaired, "keychain vazio → unpaired")
    }
}
```

- [ ] **Step 2: Rodar e ver falhar**

```bash
xcrun swiftc -parse-as-library -swift-version 5 \
  Knobler/WebhookKeychainStore.swift tools/webhookcheck.swift \
  -o /tmp/webhookcheck && /tmp/webhookcheck
```

Esperado: FALHA de compilação — `cannot find 'WebhookPairingState'` / `type 'WebhookKeychainStore' has no member 'pairingState'`.

- [ ] **Step 3: Implementar a função pura**

Em `Knobler/WebhookKeychainStore.swift`, logo antes da marca `// MARK: Token por perfil`:

```swift
    // MARK: Estado do pareamento

    /// O que o Keychain permite fazer agora. Separar `locked` de `unpaired` é o
    /// ponto: só o segundo pode registrar de novo.
    enum PairingState: Equatable {
        /// Os dois segredos abriram — dá pra publicar o link e conectar.
        case ready(publishToken: String)
        /// Os itens existem mas a ACL não bate com a assinatura de quem lê.
        case locked
        /// Nunca pareou: primeiro uso.
        case unpaired
    }

    /// Decisão pura, sem rede e sem efeito. Os closures existem pro self-check
    /// injetar um Keychain falso; em produção usam os acessores reais.
    static func pairingState(
        load: (Account) -> String? = { WebhookKeychainStore.load($0) },
        exists: (Account) -> Bool = { WebhookKeychainStore.exists($0) }
    ) -> PairingState {
        if let pub = load(.publishToken), load(.deviceSecret) != nil {
            return .ready(publishToken: pub)
        }
        return exists(.publishToken) ? .locked : .unpaired
    }
```

Os `assert` do self-check comparam com o valor retornado, então o `==` resolve o tipo sozinho — nenhuma anotação é necessária. Se algum deles der erro de tipo ambíguo, anote a variável: `let s: WebhookKeychainStore.PairingState = ...`.

- [ ] **Step 4: Rodar o self-check e ver passar**

```bash
xcrun swiftc -parse-as-library -swift-version 5 \
  Knobler/WebhookKeychainStore.swift tools/webhookcheck.swift \
  -o /tmp/webhookcheck && /tmp/webhookcheck
```

Esperado: `✅ webhookcheck ok`.

- [ ] **Step 5: Registrar o check no `check.sh`**

Em `tools/check.sh`, na lista de `swift_check` (depois da linha do `wirecheck`), acrescentar:

```bash
swift_check webhookcheck      Knobler/WebhookKeychainStore.swift tools/webhookcheck.swift
```

- [ ] **Step 6: Fazer o app consumir a função pura**

Em `Knobler/WebhookClient.swift`, substituir o bloco `ensurePairedThenConnect()` das linhas 83-97 (da abertura do método até o `}` que fecha o `if exists`) por:

```swift
    private func ensurePairedThenConnect() {
        switch WebhookKeychainStore.pairingState() {
        case .ready(let pub):
            DispatchQueue.main.async { self.credentialsLocked = false }
            publishLink(pub); connect(); return
        case .locked:
            // Existe no Keychain mas não abriu: a assinatura do app mudou e a ACL
            // do item não bate mais. NÃO re-registrar — o publishToken é a URL
            // pública que o usuário já colou no serviço externo, e um registro
            // novo a invalidaria em silêncio. Melhor parar e deixar ele decidir.
            log.error("credenciais no Keychain inacessíveis (ACL não bate com a assinatura)")
            DispatchQueue.main.async { self.credentialsLocked = true }
            return
        case .unpaired:
            break
        }
        // 1º uso: registra
```

O corpo do registro (`var req = URLRequest(...)` em diante, linhas 99-120) fica **intocado**.

- [ ] **Step 7: Rodar a bateria inteira e o build**

```bash
./tools/check.sh
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build 2>&1 | tail -5
```

Esperado: `✅ 9 checks ok` (eram 8) e `BUILD SUCCEEDED`.

- [ ] **Step 8: Commit**

```bash
git add Knobler/WebhookKeychainStore.swift Knobler/WebhookClient.swift \
        tools/webhookcheck.swift tools/check.sh
git commit -m "refactor(webhook): decisão de pareamento vira função pura testada

A escolha entre pareado, trancado e nunca pareado estava inline no
ensurePairedThenConnect, junto de URLSession e do relay — impossível de
exercitar sem rede. Virou WebhookKeychainStore.PairingState + pairingState(),
sem efeito nenhum, com webhookcheck cobrindo os quatro casos (inclusive meio
segredo aberto). Comportamento idêntico."
```

---

### Task 2: publicar a 0.10.1 como veículo dos testes de update

Os dois caminhos do updater só podem ser exercitados contra uma release **mais nova** que a instalada. O `release.sh` aborta com `## [Unreleased]` vazio (`tools/release.sh:84`), então a entrada vem primeiro.

**Files:**
- Modify: `CHANGELOG.md` (seção `## [Unreleased]`)

- [ ] **Step 1: Escrever a entrada do CHANGELOG**

Em `CHANGELOG.md`, logo abaixo de `## [Unreleased]`:

```markdown
### Changed
- **A decisão de pareamento do relay virou função pura testada**: escolher entre
  pareado, trancado e nunca pareado estava embutida no cliente do webhook, junto
  da chamada de rede, e por isso nunca teve teste. Agora é
  `WebhookKeychainStore.pairingState()`, sem efeito nenhum, coberta pelo
  `webhookcheck` no `tools/check.sh`. O comportamento do app é o mesmo.
```

- [ ] **Step 2: Dry-run do release**

```bash
./tools/release.sh patch --dry-run
```

Esperado: valida, compila Release, assina, zipa, imprime o SHA e as notas lidas do `## [Unreleased]` — sem commitar, sem tag, sem publicar. Se ele reclamar de working tree suja, commite o CHANGELOG antes (`git add CHANGELOG.md && git commit -m "docs: entrada da 0.10.1 no changelog"`).

- [ ] **Step 3: Publicar**

```bash
./tools/release.sh patch
```

Esperado: tag `v0.10.1`, release no GitHub com as notas acima, `Knobler-0.10.1.zip` anexado e cask bumpado no tap.

- [ ] **Step 4: Conferir o que foi ao ar**

```bash
gh release view v0.10.1 --json tagName,assets --jq '{tag: .tagName, assets: [.assets[].name]}'
git -C "$(brew --repo luccas-silveira/knobler)" log --oneline -1
grep -n 'version\|sha256' "$(brew --repo luccas-silveira/knobler)/Casks/knobler.rb" | head -2
```

Esperado: tag `v0.10.1`, asset `Knobler-0.10.1.zip`, último commit do tap `knobler 0.10.1`, `version "0.10.1"` no cask.

---

### Task 3: teste de aceitação do caminho brew (0.10.0 → 0.10.1)

Esta é a pendência mais antiga: "o app deve avisar sozinho e atualizar por `brew upgrade --cask knobler`" nunca rodou de ponta a ponta. O app instalado é 0.10.0, gerenciado pelo brew, então `installViaBrew()` (`Knobler/Updater.swift:289`) é o caminho que vai ser escolhido.

**Files:** nenhum — validação ao vivo.

- [ ] **Step 1: Confirmar o ponto de partida**

```bash
defaults read /Applications/Knobler.app/Contents/Info.plist CFBundleShortVersionString
brew list --cask knobler >/dev/null && echo "gerenciado pelo brew"
curl -s --max-time 3 http://127.0.0.1:4477/status >/dev/null && echo "app rodando"
```

Esperado: `0.10.0`, "gerenciado pelo brew", "app rodando". Se o app não estiver rodando, `open -a /Applications/Knobler.app`.

- [ ] **Step 2: Forçar a checagem**

Abrir Ajustes › Geral e clicar **Verificar agora** (`Knobler/SettingsView.swift:214`, chama `updater.check(force: true)`, que ignora o intervalo de 24h).

```bash
open -a /Applications/Knobler.app --args --ajustes=geral
```

Esperado: a seção de atualização passa a mostrar a 0.10.1 com o botão **Atualizar**, e o card aparece no notch (`Mode.update`) com **Atualizar** / **Depois**.

- [ ] **Step 3: Registrar o que apareceu**

```bash
screencapture -x /tmp/update-card.png
```

Ler o PNG e confirmar: o card cita a 0.10.1 e o botão diz **Atualizar** (não "Ver release" — "Ver release" significa que `canInstall` deu falso e o caminho de instalação não seria exercitado).

- [ ] **Step 4: Instalar pelo card**

Clicar **Atualizar** no notch. O app roda `brew upgrade --cask knobler` e se relança sozinho (`relaunch()`, `Knobler/Updater.swift:390`).

- [ ] **Step 5: Verificar o desfecho**

```bash
sleep 20
defaults read /Applications/Knobler.app/Contents/Info.plist CFBundleShortVersionString
brew list --cask knobler | head -1
codesign -dvv /Applications/Knobler.app 2>&1 | grep Authority
curl -s --max-time 3 http://127.0.0.1:4477/status \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print({k:d[k] for k in ('axTrusted','tapExists','tapEnabled')})"
```

Esperado: `0.10.1`; o cask continua listando o app; `Authority=Knobler Local Signing`; e `axTrusted: True, tapExists: True, tapEnabled: True` — a assinatura é a mesma dos dois lados, então a Acessibilidade **não** pode ter caído. Se caiu, é regressão: pare e investigue antes de seguir.

---

### Task 4: teste de aceitação do caminho direto (0.10.0 → 0.10.1, fora do brew)

`installDirect()` (`Knobler/Updater.swift:310`) — baixa o zip, `ditto -x -k`, `replaceItemAt`, relança — nunca rodou. Só é escolhido quando `brew list --cask knobler` falha (`Knobler/Updater.swift:218`), então o app precisa sair do brew.

**Files:** nenhum — validação ao vivo.

- [ ] **Step 1: Tirar o app do brew e instalar a 0.10.0 pelo zip**

```bash
pkill -f "/Applications/Knobler.app"
brew uninstall --cask knobler
curl -sL -o /tmp/k010.zip \
  https://github.com/luccas-silveira/knobler/releases/download/v0.10.0/Knobler-0.10.0.zip
rm -rf /tmp/k010 && mkdir -p /tmp/k010
ditto -x -k /tmp/k010.zip /tmp/k010
ditto /tmp/k010/Knobler.app /Applications/Knobler.app
xattr -dr com.apple.quarantine /Applications/Knobler.app
codesign -dvv /Applications/Knobler.app 2>&1 | grep Authority
```

Esperado: `Authority=Knobler Local Signing` — a mesma identidade da instalação anterior, que é o que preserva a Acessibilidade.

- [ ] **Step 2: Confirmar que o app se vê fora do brew**

```bash
open -a /Applications/Knobler.app
sleep 8
defaults read /Applications/Knobler.app/Contents/Info.plist CFBundleShortVersionString
brew list --cask knobler 2>&1 | head -2
```

Esperado: `0.10.0` e o `brew list` falhando ("not installed" / erro) — é exatamente a sonda que o `Updater` faz.

- [ ] **Step 3: Forçar a checagem e instalar**

```bash
open -a /Applications/Knobler.app --args --ajustes=geral
```

Clicar **Verificar agora**, depois **Atualizar** (no painel ou no card do notch).

- [ ] **Step 4: Verificar o desfecho do caminho direto**

```bash
sleep 30
defaults read /Applications/Knobler.app/Contents/Info.plist CFBundleShortVersionString
codesign -dvv /Applications/Knobler.app 2>&1 | grep Authority
curl -s --max-time 3 http://127.0.0.1:4477/status \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print({k:d[k] for k in ('axTrusted','tapExists','tapEnabled')})"
ls -la /Applications/Knobler.app | head -2
```

Esperado: `0.10.1` (o `replaceItemAt` trocou o bundle no lugar), `Authority=Knobler Local Signing`, o app relançado e respondendo, permissões intactas.

Se falhar: `log show --predicate 'process == "Knobler"' --last 10m --info | grep -i updat` mostra o motivo — as falhas do `installDirect` passam por `fail(...)`, que publica a mensagem na UI e no log.

- [ ] **Step 5: Voltar o app pro brew**

```bash
pkill -f "/Applications/Knobler.app"
rm -rf /Applications/Knobler.app
brew install --cask knobler
defaults read /Applications/Knobler.app/Contents/Info.plist CFBundleShortVersionString
brew list --cask knobler >/dev/null && echo "gerenciado pelo brew de novo"
open -a /Applications/Knobler.app
```

Esperado: `0.10.1` e o cask gerenciando de novo. (`brew install` recusa sobrescrever app não gerenciado — por isso o `rm -rf` antes.)

---

### Task 5: reproduzir o keychain trancado de verdade

O aviso "Parear de novo" (`Knobler/WebhookSettingsView.swift:47-52`) só aparece com `credentialsLocked == true`, e isso exigia uma troca de assinatura do app. Há um jeito honesto sem tocar na assinatura: gravar os itens pelo binário `security`, cuja ACL o Knobler não consegue abrir. O app vê `exists == true` e `load == nil` — o mesmo estado.

**Pré-condição:** o toggle de notificações externas está desligado e não há link publicado em uso, então os itens atuais (de instalações velhas) podem ser sobrescritos.

**Files:** nenhum — validação ao vivo.

- [ ] **Step 1: Plantar segredos ilegíveis pro app**

```bash
security add-generic-password -U -s com.zoi.knobler.webhook -a publishToken  -w tokenfalso
security add-generic-password -U -s com.zoi.knobler.webhook -a deviceSecret  -w segredofalso
security add-generic-password -U -s com.zoi.knobler.webhook -a deviceId      -w idfalso
security find-generic-password -s com.zoi.knobler.webhook -a publishToken >/dev/null && echo "item existe"
```

Esperado: "item existe". A ACL pertence ao `security`, não ao Knobler.

- [ ] **Step 2: Ligar as notificações externas**

```bash
pkill -f "/Applications/Knobler.app"; sleep 1
open -a /Applications/Knobler.app --args --ajustes=webhooks
```

Ligar **Receber notificações externas**.

- [ ] **Step 3: Verificar que o app detectou e não re-registrou**

```bash
sleep 5
screencapture -x /tmp/keychain-locked.png
log show --predicate 'process == "Knobler"' --last 5m --info \
  | grep -i "inacess" | tail -3
```

Esperado no PNG: o aviso de credenciais inacessíveis e o botão **Parear de novo**; no log, `credenciais no Keychain inacessíveis (ACL não bate com a assinatura)`. **Nenhum diálogo de senha do login keychain pode ter aparecido** — é o ponto do `SecKeychainSetUserInteractionAllowed(false)`.

- [ ] **Step 4: Exercitar o Parear de novo**

Clicar **Parear de novo** (chama `repair()`, `Knobler/WebhookClient.swift:125`: limpa tudo e registra do zero contra o relay).

```bash
sleep 8
screencapture -x /tmp/keychain-repaired.png
```

Esperado: o aviso some e um link novo aparece no painel — prova de que o registro rodou e os itens agora pertencem ao app.

- [ ] **Step 5: Limpar**

Desligar o toggle **Receber notificações externas** e apagar o pareamento de teste:

```bash
for a in publishToken deviceSecret deviceId; do
  security delete-generic-password -s com.zoi.knobler.webhook -a "$a" >/dev/null 2>&1
done
security find-generic-password -s com.zoi.knobler.webhook -a publishToken 2>&1 | tail -1
```

Esperado: "could not be found" — o link de teste deixa de existir. (Ele foi criado só para esta validação; nenhum serviço externo o conhece.)

---

### Task 6: regenerar o grafo e fechar a documentação

O `graphify-out/` foi gerado às 18:33 de 28/07, antes dos commits da 0.10.0 — `Knobler/Permissions.swift` e o painel de Permissões estão fora dele, e agora também o `pairingState`.

**Files:**
- Modify: `HANDOFF.md`
- Regenerar: `graphify-out/`

- [ ] **Step 1: Regenerar o grafo**

Invocar a skill `graphify` sobre o repositório. É caro (a última passada custou ~639k tokens para 1943 nós); se o orçamento da sessão não comportar, **pule este step e registre no HANDOFF que segue pendente** — não o faça pela metade.

- [ ] **Step 2: Escrever o desfecho no HANDOFF**

No bloco `## Pendências` da entrada do topo do `HANDOFF.md`, riscar as que fecharam e registrar o resultado real de cada validação (versões observadas, se a Acessibilidade sobreviveu, se o aviso do keychain apareceu). Manter aberta e explicada apenas a **notarização**:

```markdown
- **Notarização** (`KNOBLER_NOTARY_PROFILE`) — bloqueada por dependência externa:
  o caminho existe no `tools/release.sh` desde a 0.10.0 e espera uma conta Apple
  Developer paga. Enquanto não houver, o cask segue removendo a quarentena no
  install, e os caveats explicam isso ao usuário.
```

- [ ] **Step 3: Rodar a bateria antes de fechar**

```bash
./tools/check.sh
git status --short
```

Esperado: `✅ 9 checks ok`.

- [ ] **Step 4: Commit e push**

```bash
git add HANDOFF.md graphify-out
git commit -m "docs: fecha as pendências de cobertura do updater e do keychain

Update pelo brew e pelo caminho direto exercitados de ponta a ponta contra a
0.10.1, e o ramo trancado do keychain reproduzido com os itens gravados pelo
security(1) — mesma condição de ACL que uma troca de assinatura produz. Só a
notarização segue aberta, esperando conta Apple Developer."
git push origin master
```

---

## Verificação de ponta a ponta

Ao fim das seis tasks:

- `./tools/check.sh` → `✅ 9 checks ok`, com `webhookcheck` na lista.
- `defaults read /Applications/Knobler.app/Contents/Info.plist CFBundleShortVersionString` → `0.10.1`, e `brew list --cask knobler` responde (app de volta ao brew).
- `GET http://127.0.0.1:4477/status` → `axTrusted: true, tapExists: true, tapEnabled: true` depois dos dois updates — nenhum deles pode ter derrubado permissão, porque a identidade de assinatura é a mesma nos dois caminhos.
- `gh release view v0.10.1` mostra a release com o zip anexado; o cask no tap está em `0.10.1`.
- Os PNGs `/tmp/update-card.png`, `/tmp/keychain-locked.png` e `/tmp/keychain-repaired.png` mostram, respectivamente: o card oferecendo **Atualizar**, o aviso de credenciais inacessíveis com **Parear de novo**, e o painel já reparado.
- `security find-generic-password -s com.zoi.knobler.webhook -a publishToken` não acha nada (limpeza feita).
- `git status` limpo e `git log origin/master..master` vazio.
