# 001 — Amarras por feature (levantamento, sem proposta)

Levantado em 2026-08-04 por subagente de pesquisa, sobre o código da v0.22.0.
Linhas são do estado daquele commit — conferir antes de confiar num número.

## 1. Pomodoro
| Eixo | Achado |
|---|---|
| Nascimento | `KnoblerApp.swift:79` `private let pomodoro = Pomodoro()`; configurado em `KnoblerApp.swift:410-448` (`configProvider`, `onState`, `onPhaseEnd`, `onPhaseBegin`). Referência só no AppDelegate. |
| Notch | `NotchSectionOrder.swift:15` case `.pomodoro`; conteúdo em `NotchView.swift:926-931`; altura `NotchView.swift:124`; anel na faixa `NotchView.swift:1010-1019` (+ `fatiaDoCiclo` lendo `AppSettings`); estado empurrado por `KnoblerApp.swift:413` para `vm.pomodoro` (`NotchViewModel.swift:79` marca evento). |
| Ajustes | `SettingsPane.pomodoro` (`SettingsView.swift:17`), painel `PomodoroSettingsPane()` (`SettingsView.swift:117`). |
| Preferências | `pomodoroFocus/ShortBreak/LongBreak/CyclesLong/Sound/LockScreen` (`AppSettings.swift:201-226`), derivadas em `pomodoroConfig:228`. **Não há toggle liga/desliga**: o serviço existe sempre, só está `idle`. |
| API local | Nenhuma rota. Em `/status` aparece indiretamente via `focus` da seção (`KnoblerApp.swift:527`). |
| Sistema | `Timer` de 1 s enquanto rodando (`Pomodoro.swift:121-131`); nada global parado. Som `NSSound "Glass"`. |
| Amarras cruzadas | Menu da barra lê fase/duração (`KnoblerApp.swift:1203-1212`); `pomodoroAtivo` alimenta `pushActivity()` (`:416-421`); `onPhaseBegin` chama **DescansoController** (`:437-441`); `NotchView.fatiaDoCiclo` lê `AppSettings` direto. |

## 2. Lembretes
| Eixo | Achado |
|---|---|
| Nascimento | `KnoblerApp.swift:80` `ReminderScheduler()`; wiring `:450-467`, `start()` em `:475`. |
| Notch | Não tem seção própria — sai como card via `vm.enqueue` (`:459`) e cai no Histórico. |
| Ajustes | `SettingsPane.lembretes` → `RemindersView()` (`SettingsView.swift:118`). |
| Preferências | `reminders` JSON (`AppSettings.swift:184-190`) + snooze próprio (`Reminders.swift:177-186`, `:360`, `:383`). Toggle é **por item** (`enabled`), não global. |
| API local | Nenhuma. Nada em `/status`. |
| Sistema | `Timer` de 15 s em `.common` sempre ligado (`Reminders.swift:190-195`); observer de wake `NSWorkspace.didWakeNotification` (`KnoblerApp.swift:469-473`). Sem permissão. |
| Amarras cruzadas | Ações de snooze do card resolvidas no AppDelegate (`:82`, `:153`); escreve de volta em `AppSettings.reminders` ao disparar oneShot (`:463-466`). |

## 3. Descanso
| Eixo | Achado |
|---|---|
| Nascimento | `KnoblerApp.swift:84-85` `ScheduleEngine<ScreenBreak>()` + `DescansoController()`; wiring `:478-487`. |
| Notch | Não entra no card — é overlay de tela cheia (`DescansoView.swift`, `DescansoController.swift`). |
| Ajustes | `SettingsPane.descanso` → `DescansoTabView()` (`SettingsView.swift:119`). |
| Preferências | `screenBreaks` JSON (`AppSettings.swift:193-199`). Toggle por item, sem global. |
| API local | Nenhuma. Nada em `/status`. |
| Sistema | `ScheduleEngine` reaproveita o mesmo motor dos lembretes (timer 15 s); wake tick (`:472`); overlay com timer de 0,25 s enquanto ativo (`DescansoController.swift:84`). |
| Amarras cruzadas | **Pomodoro chama `descanso.begin`** para travar a tela nas pausas (`KnoblerApp.swift:441`) — segundo dono do overlay. |

## 4. Ditado
| Eixo | Achado |
|---|---|
| Nascimento | `KnoblerApp.swift:67` `DictationController()`; wiring pesado `:215-239` (`onState`, `destinationProvider`, `transcriptSink`, gatilho vindo do `volumeHUD.onRightOption`). |
| Notch | Sem seção: pílula em todas as telas via `vm.dictation` (`:216-218`). |
| Ajustes | `SettingsPane.ditado` → `DictationSettingsPane()` (`SettingsView.swift:116`). |
| Preferências | `dictation`, `dictationCloud`, `formatTranscript`, `formatEndpoint`, `formatModel` (`AppSettings.swift:76-93`) + API key no Keychain (`AppSettings.swift:387`). Toggle `dictation` **desliga de verdade** (`Dictation.swift:272` e `:315` guardam `start`/gatilho). |
| API local | Nenhuma rota; contribui `status["dictation"]` (`KnoblerApp.swift:533`). |
| Sistema | Acessibilidade (`Dictation.swift:277`), microfone (`:337`), `NSEvent.addGlobalMonitorForEvents` (`:378`); depende do **tap global do VolumeHUD** para o Right-Option (`KnoblerApp.swift:230`). |
| Amarras cruzadas | Destino do texto lê `askStore` (`:221-228`, `:236-239`); badge de Acessibilidade do menu lê `AppSettings.dictation` (`KnoblerApp.swift:1140`, `:1186`); `silenciando` comenta o mic do próprio ditado (`:1304`). |

## 5. Mensagens LAN
| Eixo | Achado |
|---|---|
| Nascimento | `KnoblerApp.swift:64-65` `messageStore` + `lanMessaging` (ambos `let` públicos); wiring `:345-388`. |
| Notch | Seção `.mensagens` (`NotchSectionOrder.swift:15`), conteúdo `NotchView.swift:918` (`MessagesView`), altura `:128`, sem sinal vivo (`:1027`); `MessageStore` entra como `@EnvironmentObject` (`NotchView.swift:25`); card de entrada via `vm.showIncoming` (`NotchViewModel.swift:422`). |
| Ajustes | `SettingsPane.mensagens` → `IdentitySettingsView()` (`SettingsView.swift:121`). |
| Preferências | `displayName` (`AppSettings.swift:177`), avatar em arquivo (`AppSettings.swift:331`), `myProfile()`. **Não há toggle de liga/desliga** — Bonjour sobe sempre. |
| API local | Nenhuma rota; contribui `status["lanMessaging"]` (`KnoblerApp.swift:534`). |
| Sistema | `NWListener` + `NWBrowser` (Bonjour TCP) sempre ativos (`LANMessaging.swift:35-114`) — rede local acesa mesmo parado. |
| Amarras cruzadas | `AppSettings.$displayName` re-anuncia identidade (`KnoblerApp.swift:384-388`); avatar remoto cruza com `loadRemoteImages`; media salva via `MessageStore` (`:359-363`). |

## 6. Webhooks (notificações externas)
| Eixo | Achado |
|---|---|
| Nascimento | `KnoblerApp.swift:63` `let webhookClient = WebhookClient()` (público, passado à `SettingsView`); wiring `:494-495`; start/stop no sink `:552-556`. |
| Notch | Sem seção; publica card via `publicar()` (`:495`). |
| Ajustes | `SettingsPane.webhooks` → `WebhookSettingsView(client:)` (`SettingsView.swift:120`) — **único painel que recebe o serviço injetado**. |
| Preferências | `webhookNotifications` (`AppSettings.swift:128`, opt-in `:286`), `loadRemoteImages` (`:140`); segredos no Keychain (`WebhookKeychainStore.swift`). Toggle **desliga de verdade** (`KnoblerApp.swift:552-556`). |
| API local | Nenhuma rota própria; nada em `/status`. |
| Sistema | WebSocket persistente ao relay (`WebhookClient.swift:23-56`) — só quando ligado. Sem permissão. |
| Amarras cruzadas | Passa pelo gate `silenciando` (`:1290`); `webhookID` reutilizado pelos avisos do dev (`:1334`); satélites (`WebhookPresets/Template/AutoMap/Assistant/MappingEditor`) só falam com o painel. |

## 7. Shelf (Prateleira)
| Eixo | Achado |
|---|---|
| Nascimento | `KnoblerApp.swift:87` `ShelfStore()`; alimentado por `screenshots.onScreenshot` (`:244-248`). |
| Notch | Seção `.shelf` (`NotchView.swift:920` `ShelfRowView`), altura `:126` (com preview), contagem na faixa `:994`, evento `NotchView.swift:1845`, `peekShelf()` (`KnoblerApp.swift:932-951`). |
| Ajustes | Sem painel próprio; toggles moram no painel Notch (`SettingsView.swift:330+`). |
| Preferências | `Shelf.storageKey` (paths em UserDefaults, `Shelf.swift:17,26`), `screenshotsToShelf` e `hideScreenshotPreview` (`AppSettings.swift:95-101`). Sem toggle da seção em si — só o `pin`/ordem. |
| API local | Nenhuma rota. |
| Sistema | `NSMetadataQuery` (Spotlight) quando `screenshotsToShelf` (`ScreenshotWatcher.swift:18-52`, start/stop em `KnoblerApp.swift:558-562`); supressão de preview nativo (`:577-583`). |
| Amarras cruzadas | Abre **LinkPreview** (`Shelf.swift:155`, `:231`); dispara **FileConverter/ShelfPreview** (`Shelf.swift:49`, `:237`); AirDrop (`Sharing.swift`, `vm.onAirDrop`). |

## 8. Espelho (Mirror)
| Eixo | Achado |
|---|---|
| Nascimento | Singleton `MirrorController.shared` (`Mirror.swift:14`) — **não nasce no AppDelegate**; ativado por `MirrorController.activate` (`KnoblerApp.swift:492`, `:500`). |
| Notch | Seção `.espelho` (`NotchView.swift:919`), altura `:127`, sem sinal (`:1027`); `vm.mirrorOn` marca evento (`NotchViewModel.swift:48`). |
| Ajustes | Sem painel próprio: toggle `mirrorBeforeMeetings` está no painel Notch (`SettingsView.swift:319-322`), device em `mirrorDeviceID`. |
| Preferências | `mirrorBeforeMeetings` (`AppSettings.swift:57`), `mirrorDeviceID` (`:62`). O toggle só governa a abertura automática. |
| API local | **`POST /mirror`** (`NotchAPIServer.swift:300`), handler `KnoblerApp.swift:498-511`; contribui `MirrorController.shared.diagnostics` ao `/status` (`:519`). |
| Sistema | Permissão de câmera (`Mirror.swift:94-118`); `AVCaptureSession` só enquanto ligado. |
| Amarras cruzadas | **Calendário** abre/fecha automático (`KnoblerApp.swift:489-497`, flag `mirrorAutoOpened:96`); API abre; `NotchView` observa o singleton (`:21`). |

## 9. Anotação (desenho na tela)
| Eixo | Achado |
|---|---|
| Nascimento | Singleton `AnnotationController.shared` (`AnnotationController.swift:117`), guardado em `KnoblerApp.swift:86` e **iniciado incondicionalmente** em `:197` (`annotation.start()`). |
| Notch | Seção `.anotacao`, **sempre com conteúdo** (`NotchViewModel.swift:157-158` — comentário explícito: é página fixa); view `NotchView.swift:932`, altura `:132`, sinal `:1021`. |
| Ajustes | `SettingsPane.desenho` → `DesenhoSettingsPane()` (`SettingsView.swift:115`). |
| Preferências | `annotationActivationMode`, `annotationAutoFade`, `annotationFadeSeconds`, `annotationDefaultTool`, `annotationDefaultColor`, `annotationLineWidth` (`AppSettings.swift:103-126`) + `annotationBackground` direto no UserDefaults (`AnnotationController.swift:131,237`). **Sem toggle de liga/desliga** (só modo de ativação). |
| API local | Contribui `status["annotation"]` (`KnoblerApp.swift:516`); sem rota. |
| Sistema | Acessibilidade + **CGEvent tap global** (`AnnotationController.swift:282-317`) e `Timer` de health-check de 3 s **sempre** (`:146`). |
| Amarras cruzadas | `NotchView.swift:1811` lê `isActive/temTinta` fora da seção; lê `AppSettings` direto (`:38-40`, `:128-135`). |

## 10. Preview de Link
| Eixo | Achado |
|---|---|
| Nascimento | Singleton `LinkPreview.shared` (`LinkPreview.swift:19`) — **nunca aparece no AppDelegate**. |
| Notch | Seção `.link` (`NotchView.swift:921`), altura `:131`, sinal de carregando `:1004`; `NotchViewModel.linkAberto` lê o singleton (`:301`). |
| Ajustes | Nenhum painel, nenhuma preferência. |
| Preferências | Nenhuma chave própria. **Sem toggle.** |
| API local | Nenhuma. |
| Sistema | `WKWebView` só quando aberto; nada acende parado. |
| Amarras cruzadas | Só o Shelf abre (`Shelf.swift:155`, `:231`); o gesto de scroll do AppDelegate consulta `LinkPreview.shared.hosted` (`KnoblerApp.swift:880`, flag `scrollStartedInLink:175`). |

## 11. Nota rápida
| Eixo | Achado |
|---|---|
| Nascimento | Singleton `QuickNote.shared` (`QuickNote.swift:18`); usado no menu da barra (`KnoblerApp.swift:1214`, `:1252-1257`). |
| Notch | Seção `.nota` (`NotchView.swift:915`), altura `:130`, sinal `:998`, evento `:1848`; tem **privilégio no ordenador**: `travadaNaNota` força topo (`NotchSectionOrder.swift:119-122`) e `NotchViewModel.swift:232` força foco. |
| Ajustes | Nenhum painel. |
| Preferências | Nenhuma chave (texto em memória, `QuickNote.swift:33`). Sem toggle. |
| API local | Nenhuma. |
| Sistema | Nada global. |
| Amarras cruzadas | `note.editing` trava o hover do VM (`NotchView.swift:890-905`), `NotchViewModel.focar` limpa `editing` (`:265`); `hostDisplayID` amarra à tela (`KnoblerApp.swift:1254`). |

## 12. AirPods
| Eixo | Achado |
|---|---|
| Nascimento | `KnoblerApp.swift:56` `BluetoothMonitor()`; wiring `:258-276`; start/stop só pelo sink de settings (`:564-568`). |
| Notch | Sem seção: `vm.airpods` + `vm.showAirPodsCard()` (`:259-263`); render em `AirPodsBattery.swift` / `NotchView`. |
| Ajustes | Toggle no painel Notch (`SettingsView.swift:286-289`). |
| Preferências | `airpodsNotch` (`AppSettings.swift:72`). Toggle **desliga de verdade** (`:564-568`). |
| API local | Nenhuma; nada em `/status`. |
| Sistema | Polling Bluetooth de 60 s só quando ligado (`BluetoothMonitor.swift:116-127`). |
| Amarras cruzadas | Praticamente nenhuma — só `vm.airpods`/`airpodsCard`. |

## 13. Conversão de arquivo
| Eixo | Achado |
|---|---|
| Nascimento | **Não nasce**: tudo estático/por demanda (`FileConverter.targets` em `Shelf.swift:237`, `ShelfPreview` criado em `Shelf.swift:49`). |
| Notch | Sem seção própria: mora dentro do card do Shelf (`NotchView.swift:126` altura de preview, `ShelfPreviewView.swift`). |
| Ajustes | Nenhum painel. |
| Preferências | Nenhuma chave. Sem toggle. |
| API local | Nenhuma. |
| Sistema | Nada parado; `AVAssetExportSession`/ImageIO/PDFKit só durante a conversão (`VideoConverter.swift:90` ticker local). |
| Amarras cruzadas | Só o Shelf. Único ponto de entrada. |

## 14. Notificações (interceptor + histórico)
| Eixo | Achado |
|---|---|
| Nascimento | `KnoblerApp.swift:52` `interceptor`, criado e **iniciado incondicionalmente** em `:199-203`; `NotificationHistory.shared` é singleton. |
| Notch | Seção `.historico` (`NotchView.swift:916` `HistoryListView`), altura `:129`, contagem `:996`, evento `:1846`; cards por `publicar()` → `vm.enqueue` (`KnoblerApp.swift:1290-1296`). |
| Ajustes | Sem painel próprio; toggle no painel Notch (`SettingsView.swift:276-278`). |
| Preferências | `notchNotifications` (`AppSettings.swift:19`), `silenciarEmReuniao`/`silenciarComMicrofone` (`:47-56`), `batteryAlerts` (`:28`), `avisosDoDesenvolvedor` (`:136`). O toggle **não desliga o interceptor**: `start()` roda sempre e a checagem é no consumo (`NotificationInterceptor.swift:99`) — o tap AX fica de pé. |
| API local | `POST /notify` (`NotchAPIServer.swift:257`); nada específico em `/status` além de `hasNotification` (`KnoblerApp.swift:528`). |
| Sistema | Acessibilidade + polling de 3 s em dois timers (`NotificationInterceptor.swift:43-58`), sempre. |
| Amarras cruzadas | É o **funil central**: Pomodoro, Lembretes, DevAvisos, Webhook, API, ColorPicker, Updater todos passam por `publicar()`; o gate `silenciando` (`KnoblerApp.swift:1304`) lê **calendário** e **microfone**. |

## 15. Música / HUDs
| Eixo | Achado |
|---|---|
| Nascimento | `KnoblerApp.swift:51` `MediaController()`, `:53` `VolumeHUDController()`, `:54` `SystemAudioLevels()`, `:55` `BatteryMonitor()`, `:57` `MicMonitor()`; wiring `:206-213`, `:249-256`, `:318-343`. |
| Notch | Seção `.musica` é o **default/fallback** (`NotchView.swift:933` `case .musica, .none`), altura `:122`, sinal `:988`, eventos `:1843-1844`; HUDs vão pra todas as telas (`:207-209`). |
| Ajustes | Painel Notch: seções "HUDs" e "Música" (`SettingsView.swift:296-308`). |
| Preferências | `volumeHUD`, `brightnessHUD`, `liveAudioVisualizer`, `batteryAlerts`, `micIndicator` (`AppSettings.swift:22-33`, `:68`). `volumeHUD.start()` é **incondicional** (`KnoblerApp.swift:213`): os toggles só filtram a exibição; o tap continua de pé porque o **ditado depende dele**. |
| API local | Contribui a base do `/status` (`volumeHUD.diagnostics`, `KnoblerApp.swift:515`), `visualizerTapped`, `player`, `micInUse`. |
| Sistema | Acessibilidade + **CGEvent tap global** (`VolumeHUD.swift:146-160`), monitor global de teclas (`:94`), health-timer de 3 s (`:89`); `SystemAudioLevels` faz tap de áudio do app tocando (`KnoblerApp.swift:800-812`); `OSDSuppressor` mexe em estado do sistema (`:577-583`). |
| Amarras cruzadas | Muitas: badge de Acessibilidade (`:212`), Right-Option → ditado (`:230`), `media.$state` alimenta o tap de áudio (`:325-332`) e o `musicPaused` (`:340-343`), `media.activeBundleID` no `/status`. |

---

## Nota final — grudadas vs. quase soltas

**Quase soltas (poucas amarras, ou toggle que desliga de verdade)**
- **Conversão de arquivo** — não nasce em lugar nenhum, sem preferência, sem rota, um único chamador (Shelf).
- **Preview de Link** — singleton preguiçoso, zero preferência, zero permissão; só o Shelf abre e um `if` no gesto de scroll.
- **AirPods** — toggle `airpodsNotch` liga/desliga o serviço de fato; escreve só em dois campos do VM.
- **Webhooks** — toggle real, painel próprio que já recebe o serviço injetado, satélites isolados; só encosta em `publicar()`.
- **Descanso** — painel próprio, dados próprios, sem UI no card; a única amarra é o Pomodoro chamar `begin()`.
- **Ditado** — toggle que barra `start()` de verdade e painel próprio; preso apenas pelo Right-Option vindo do tap do VolumeHUD e pelo destino `askStore`.
- **Lembretes** — painel e chave próprios, sem seção no notch; só o snooze do card volta ao AppDelegate.

**Mais grudadas**
- **Notificações** — é o funil por onde sete features publicam, e o gate `silenciando` lê calendário e microfone; o toggle não desliga o tap.
- **Música/HUDs** — seção default do card, tap global incondicional que o ditado consome, base do `/status` e supressor de OSD do sistema.
- **Anotação** — `hasContent` hardcoded como `true` no VM, tap global e timer sempre ligados, seis chaves de preferência e nenhum toggle de desligar.
- **Espelho** — sem dono claro (singleton), aberto por três caminhos (calendário, API `/mirror`, usuário) e com estado espalhado por todos os VMs.
- **Mensagens LAN** — dois `let` públicos no AppDelegate, Bonjour sempre no ar sem toggle, e o wiring mais longo do `applicationDidFinishLaunching` (store + perfil + mídia + avatar).
- **Shelf** — recebe screenshots via Spotlight, despacha para LinkPreview, conversão e AirDrop, tem `peekShelf` no AppDelegate e persistência própria.
- **Pomodoro** — sem toggle, aparece no menu da barra, empurra atividade e comanda o overlay do Descanso; a `NotchView` ainda lê `AppSettings` direto pro anel.
