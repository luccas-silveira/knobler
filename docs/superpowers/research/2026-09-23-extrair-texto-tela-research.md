# Pesquisa — extrair texto da tela

Spec: `docs/superpowers/specs/2026-09-23-extrair-texto-tela-design.md`

## Achados

### A1 — Fotografar a tela antes de mostrar a camada é o padrão do mercado e do Vorssaint
- Fonte: `vorssaint-utils/Sources/Vorssaint/Services/QuickTools/ScreenshotSelectionController.swift:11-12,212-226` (freeze ligado por padrão); CleanShot/Shottr fazem igual.
- Contradiz a spec: parcial — a spec captura depois de fechar a camada.
- Pergunta que levanta: congelar a tela garante que o texto lido é exatamente o que a pessoa viu ao selecionar (vídeo rodando, tooltip que some) e dispensa esconder a própria camada; custa uma foto por monitor a cada acionamento. Congela?

### A2 — macOS 15+ reapresenta periodicamente o pedido de "ignorar o seletor de janelas privado" para apps que capturam por ScreenCaptureKit
- Fonte: https://9to5mac.com/2024/08/14/macos-sequoia-screen-recording-prompt-monthly/ ; entitlement que evita (`com.apple.developer.persistent-content-capture`) exige aprovação da Apple e Team ID — o Knobler não tem.
- Contradiz a spec: parcial — a spec não prevê esse alerta.
- Pergunta que levanta: o usuário vai ver um alerta do sistema de tempos em tempos e não há como evitar. Aceita esse custo? (Não verificado se vale pra captura avulsa, não só stream.)

### A3 — Conceder Gravação de Tela só vale depois de relançar o app; o pedido do sistema aparece uma vez só
- Fonte: docs de `CGRequestScreenCaptureAccess` / `CGPreflightScreenCaptureAccess`.
- Contradiz a spec: parcial — a spec só abre os Ajustes.
- Pergunta que levanta: depois de conceder, a pessoa precisa reabrir o Knobler. O app oferece "Reabrir agora" ou deixa o macOS pedir?

### A4 — O registro de atalhos existente apaga todos os handlers quando os Monitores param
- Fonte: `Vendor/MonitorControl/KeyboardShortcuts.swift:143,251`; `Knobler/Monitores.swift:107` (`removeAllHandlers()`).
- Contradiz a spec: parcial — reusar o registro sem ajuste quebra o atalho novo em silêncio.
- Pergunta que levanta: trocar o `removeAllHandlers` dos Monitores por remoção só dos atalhos deles (ajuste de uma linha no uso). OK?

### A5 — O notch expandido não tem fileira de ferramentas; as ferramentas (conta-gotas, AirDrop, Bloquear teclado) vivem no menu "Ferramentas"
- Fonte: `Knobler/KnoblerApp.swift:1478-1491`; botões do notch pertencem a seções (`NotchView.swift:534-560,1082`).
- Contradiz a spec: parcial — "botão no notch" não tem lugar definido.
- Pergunta que levanta: onde fica o botão no notch, e entra também no menu Ferramentas (uma linha)?

### A6 — Pela regra de arquitetura, recurso que não substitui algo do macOS vira peça (plugin opcional)
- Fonte: `docs/architecture.md:43-70`; contraexemplo: conta-gotas composto no `AppDelegate`.
- Contradiz a spec: parcial — a spec compõe no `AppDelegate`.
- Pergunta que levanta: é recurso fixo do app (como o conta-gotas) ou peça que a pessoa liga/desliga?

### A7 — A camada de seleção precisa ficar acima do notch
- Fonte: `Knobler/AnnotationController.swift:~425-466` usa `.mainMenu + 2`, abaixo do `NotchWindow` (`.mainMenu + 3`, `NotchWindow.swift:30`); `DescansoController.swift:61` usa `CGShieldingWindowLevel()`.
- Contradiz a spec: não — confirma "acima de tudo"; padrão a seguir é o do Descanso.

### A8 — Correção de idioma melhora prosa e estraga código, URL e IDs
- Fonte: docs de `VNRecognizeTextRequest.usesLanguageCorrection`.
- Contradiz a spec: parcial — a spec liga a correção sempre.
- Pergunta que levanta: o uso é mais texto corrido ou código/links? Define se liga a correção.

### A9 — APIs confirmadas no SDK instalado
- Fonte: `SCScreenshotManager.h:153` (captura com filtro, macOS 14.0), `:161` (`captureImage(in:)` só 15.2), `CGWindow.h:274` (`CGWindowListCreateImage` obsoleta no 15); `VNRecognizeTextRequest.h:74` (`automaticallyDetectsLanguage` macOS 13).
- Contradiz a spec: não.

### A10 — Reuso confirmado
- Fonte: aviso no notch como o conta-gotas (`KnoblerApp.swift:1677-1687`, `NotchViewModel.swift:586`); `Permission` ganha um caso (`Permissions.swift:35,50,78,98,171`) e aparece sozinho no painel (`SettingsView.swift:646`); gravador de atalho pronto (`MonitoresView.swift:217-222`); log por `Logger` por arquivo; check no formato de `tools/colorpickercheck.swift` + linha em `tools/check.sh`. Sem entitlement nem chave de Info.plist.
- Contradiz a spec: não.

## Fila do grill

1. A6 — recurso fixo ou peça opcional? (trava A5)
2. A1 — congelar a tela antes de selecionar?
3. A5 — onde fica o botão no notch; entra no menu Ferramentas?
4. A2 — aceitar o alerta periódico do macOS?
5. A3 — oferecer "Reabrir agora" depois de conceder?
6. A4 — ajustar o `removeAllHandlers` dos Monitores?
7. A8 — correção de idioma sempre ligada?
