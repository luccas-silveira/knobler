# Wizard de boas-vindas — pesquisa

Verificação das incógnitas do
[design](2026-08-03-boas-vindas-design.md), feita no código em 2026-08-03 antes
de escrever o plano. Cada achado diz o que muda no desenho.

## 1. Adiar o prompt de Acessibilidade é seguro — nada precisa de relaunch

O design tira `Permission.promptAccessibilityOnce()` do
`applicationDidFinishLaunching` (`KnoblerApp.swift:175`) e deixa o painel
Permissões pedir. O risco levantado era: os subsistemas que dependem de
Acessibilidade sobem sem ela e ficam inertes pra sempre.

**Não ficam.** Os três consumidores já se recuperam sozinhos por polling,
porque conceder ou revogar Acessibilidade não notifica ninguém no macOS:

| Consumidor | Recuperação |
|---|---|
| `NotificationInterceptor` | `attachTimer` de 3 s chamando `attachIfPossible()`, que só faz `guard AXIsProcessTrusted()` (`:38-58`) |
| `VolumeHUD` (gatilho ⌥ direita do ditado) | `checkTapHealth()` — sem tap e confiável, chama `setupEventTap()`; se o trust mudou desde a criação, derruba e refaz (`:110-128`) |
| `AnnotationController` | `checkEventTapHealth()`, mesma estrutura (`:269-284`) |

O `checkTapHealth` ainda dispara `onAXTrust?(trusted)`, que é quem atualiza o ⚠
do `statusItem`. Ou seja: conceder a permissão no meio da sessão já era um
caminho suportado e testado — o wizard só o torna o caminho normal na primeira
execução.

**Efeito no design:** a "consequência aceita" (subsistemas mudos entre o launch
e o fechamento do wizard) é real, mas dura o tempo do wizard e se resolve em até
3 s depois da concessão, sem relaunch. Risco menor do que a spec assumia.

## 2. O painel Permissões sempre oferece "Permitir" pra Acessibilidade

`Permission.acessibilidade.status` é `AXIsProcessTrusted() ? .concedida :
.naoPedida` (`Permissions.swift:91`) — o comentário do código é explícito: a API
**não distingue negada de nunca pedida**. E `canRequest` casa com `.naoPedida`
(`:180`).

Logo, enquanto não estiver concedida, o painel sempre mostra o botão. Não existe
o estado "negada, botão some" para a Acessibilidade, que era o buraco temido
quando movemos o pedido do launch para o painel.

Some com isso a última objeção contra a Pergunta 12: mover o pedido pro painel é
idempotente. `promptAccessibilityOnce()` já tem `guard !AXIsProcessTrusted()` e
vira no-op depois de decisão gravada — chamá-lo N vezes é inofensivo.

## 3. Nenhuma janela do projeto tem delegate

Zero ocorrências de `NSWindowDelegate`, `windowWillClose` e `windowShouldClose`
em `Knobler/`. O `settingsWindow` é criado e esquecido (`KnoblerApp.swift:1305`).

**Efeito no design:** gravar `onboarding.versao` "no `windowWillClose`" não é
uma linha — exige delegate novo ou observar
`NSWindow.willCloseNotification` para aquela janela. O observer é o caminho
menor: não muda a conformidade do `AppDelegate` e some junto com a janela.

O botão "Ignorar" grava e chama `close()`, caindo no mesmo observer — uma
gravação, um lugar, como decidido.

## 4. A flag de CLI precisa do mesmo desvio que a `--ajustes`

`--ajustes` não é só um atalho de abertura: ele está no **`if`** cujo `else`
chama `apresentarPermissoesSeNecessario()` (`:555-561`). Abrir Ajustes por CLI
suprime o onboarding de propósito, senão a captura de tela dispara o fluxo real.

**Efeito no design:** `--boas-vindas` entra no mesmo `if`, não numa condição
paralela. Abrir o wizard pra tirar print não pode gravar a versão nem encadear
o painel Permissões.

## 5. O estado real desta máquina confirma o corte do passo de toggles

`defaults read com.zoi.knobler` devolve **apenas**
`"onboarding.permissoes.apresentado" = 1` entre as chaves de interesse.
`dictation`, `localAPI` e `displayName` **não existem** — estão valendo pelo
default (`flag()` → `true`; `displayName` → `AppSettings.macOSFullName()`).

Confirma empiricamente o que a auditoria de código já dizia: o passo "ative o
ditado / a API / as mensagens" não teria o que oferecer. E confirma que a
migração da Pergunta 18 encontra a chave antiga onde espera.

## 6. O molde do check

`tools/check.sh` usa um helper `swift_check <nome> <arquivos...>` que compila os
arquivos listados junto com `tools/<nome>.swift`. O `onboardingcheck` entra como
uma linha só, com um arquivo:

```
swift_check onboardingcheck Knobler/Onboarding.swift tools/onboardingcheck.swift
```

Isso só funciona se `Onboarding.swift` não importar SwiftUI nem tocar
`AppSettings` — a restrição que o design já impõe pela mesma razão que criou o
`CalendarAviso`. O harness usa `-parse-as-library`, então **não** pode ser
escrito como `main.swift`.

## 7. Incógnita que sobra pro plano, não pra pesquisa

A captura das duas PNGs depende de descobrir o `windowID` da janela nova pro
`screencapture -l`. É o mesmo procedimento dos `settings-*.png` e o recorte
(`802x554+55+37`) foi calibrado para 800×520 — se o wizard tiver outro tamanho,
o recorte muda. Decidir o tamanho da janela antes de capturar.

## Nada mudou nas decisões

Os sete achados confirmam o desenho ou baratearam um risco. Nenhuma pergunta do
grilling precisa ser reaberta.
