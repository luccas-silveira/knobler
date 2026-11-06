#!/usr/bin/env bash
# Roda todos os self-checks do projeto. É o que a CI executa — rode antes de
# abrir PR pra ver o mesmo resultado localmente.
#
# Uso: ./tools/check.sh [--com-ambiente]
#   --com-ambiente: inclui os gates que dependem de ferramenta externa ou da
#                   sessão gráfica (hoje: codex CLI e o instancia-e2e, que
#                   lança um app-brinquedo com `open -n`). Sem a flag, eles
#                   são pulados.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

WITH_ENV=0
[ "${1:-}" = "--com-ambiente" ] && WITH_ENV=1

FAILED=()
PASSED=0
SKIPPED=()

# ponytail: o binário vai pro /tmp; nenhum check precisa de artefato persistente.
run() {
  local name="$1"; shift
  printf "  %-26s " "$name"
  if out=$("$@" 2>&1); then
    echo "ok"
    PASSED=$((PASSED + 1))
  else
    echo "FALHOU"
    # "command not found" some no meio de um heredoc ecoado — puxa pra cima.
    printf '%s\n' "$out" | grep -iE "command not found|No such file|not installed" \
      | sort -u | sed 's/^/      ⚠ /'
    # saída inteira: é curta, e truncar já escondeu a causa uma vez
    printf '%s\n' "$out" | sed 's/^/      /'
    # `test`/`jq -e` sob `set -e` falham em silêncio: sem o trace não dá pra
    # saber QUAL asserção caiu. Re-roda o gate com -x só pra colher isso.
    if [ "$1" = "bash" ] || [ "${1##*/}" = "bash" ]; then
      echo "      --- trace (bash -x) ---"
      # só as linhas de comando do trace: heredoc ecoado (sem '+') afogaria o fim.
      bash -x "${@:2}" 2>&1 | grep '^+' | tail -25 | sed 's/^/      /'
    fi
    FAILED+=("$name")
  fi
}

# Dependências que não vêm no macOS limpo (nem no runner da CI).
for dep in jq node; do
  command -v "$dep" >/dev/null || {
    echo "❌ falta '$dep' — os gates de integração precisam dele (brew install $dep)"
    exit 1
  }
done

# Compila os fontes indicados junto do harness e roda o binário.
# `main.swift` traz código top-level e por isso NÃO aceita -parse-as-library.
swift_check() {
  local name="$1"; shift
  local flags="-swift-version 5"
  case " $* " in
    *"main.swift "*) ;;
    *) flags="-parse-as-library $flags" ;;
  esac
  run "$name" bash -c "xcrun swiftc $flags $* -o /tmp/$name && /tmp/$name"
}

# Gate cujo nome É o nome do arquivo de teste: a falha cita o arquivo.
swift_teste() { local t="$1"; shift; swift_check "$(basename "$t" .swift)" "$@" "$t"; }
bash_teste()  { local t="$1"; shift; run "$(basename "$t" .sh)" bash "$t" "$@"; }

echo "== self-checks Swift =="
swift_check presentationcheck Knobler/NotchSectionOrder.swift Knobler/NotchPresentation.swift tools/presentationcheck.swift
swift_check askcheck          Knobler/AskModels.swift Knobler/AskFeature.swift tools/askcheck.swift
swift_check apiguardcheck      Knobler/NotchAPIGuard.swift tools/apiguardcheck.swift
swift_check longpollcheck     Knobler/NotchAPILongPoll.swift tools/longpollcheck.swift
# servidor de verdade numa porta alternativa (44877, nunca a 4477): contrato de
# /agent-requests e long-poll segurando, acordando e soltando conexão.
swift_check apiservercheck    Knobler/AgentRequestModels.swift Knobler/AskModels.swift \
  Knobler/NotchAPIServer.swift Knobler/NotchAPIGuard.swift Knobler/NotchAPILongPoll.swift \
  tools/agentrequest-api-server-check.swift
swift_check updatercheck      Knobler/Updater.swift tools/updatercheck.swift
swift_check agentrequestcheck Knobler/AgentRequestModels.swift Knobler/AgentRequestStore.swift tools/agentrequestcheck.swift
# backend vendorizado inteiro: o modelo do codenotch se amarra em quase tudo.
swift_check agentescheck     $(find Vendor/Codenotch -name '*.swift') tools/agentescheck.swift
swift_check airpodscheck      Knobler/AirPodsBattery.swift tools/airpods_selfcheck.swift
swift_check monitorescheck    Knobler/MonitoresModel.swift tools/monitorescheck.swift
swift_check monitoresservicecheck Knobler/MonitoresModel.swift Knobler/Monitores.swift tools/monitoresservicecheck.swift
swift_check volumehudcheck    Knobler/VolumeHUD.swift Knobler/TeclaDiagnostico.swift tools/volumehudcheck.swift
# keyLog do /status sai sem autenticação: só tecla de função entra no anel.
swift_check keylogcheck       Knobler/TeclaDiagnostico.swift tools/keylogcheck.swift
# ...e o monitor global de keyDown do VolumeHUD passa pelo filtro: o
# volumehudcheck testa o método, mas só o grep amarra o closure a ele.
run keylogintegracao bash -c '
grep -qF "self?.registrarKeyDown(keyCode: event.keyCode)" Knobler/VolumeHUD.swift || exit 1
grep -qF "guard let entrada = TeclaDiagnostico.entrada(keyCode: keyCode)" Knobler/VolumeHUD.swift || exit 1
! grep -qF "logKey(\"kb=" Knobler/VolumeHUD.swift'
swift_check wirecheck         Knobler/Wire.swift tools/wirecheck/main.swift
swift_check webhookcheck      Knobler/WebhookKeychainStore.swift Knobler/WebhookClient.swift \
  Knobler/NotchNotification.swift tools/webhookcheck.swift
swift_check templatecheck     Knobler/WebhookTemplate.swift tools/templatecheck.swift
swift_check presetcheck       Knobler/WebhookTemplate.swift Knobler/WebhookPresets.swift tools/presetcheck.swift
swift_check assistentecheck   Knobler/WebhookAssistant.swift tools/assistentecheck.swift
swift_check exemplocheck      Knobler/WebhookTemplate.swift Knobler/WebhookExemplo.swift tools/exemplocheck.swift
swift_check automapcheck      Knobler/WebhookTemplate.swift Knobler/WebhookPresets.swift Knobler/WebhookAutoMap.swift tools/automapcheck.swift
swift_check colorpickercheck  Knobler/ColorPicker.swift Knobler/CoresRecentes.swift tools/colorpickercheck.swift
swift_check corescheck        Knobler/CoresRecentes.swift tools/corescheck.swift
swift_check ilhacheck         Knobler/IlhaVisualizador.swift tools/ilhacheck.swift
# a máquina de peças; NotchSectionOrder entra só pra conferir o nome da seção
# da ficha; FileConverter entra pra tarefa 10 (Conversão de arquivo) provar o
# gating com o `targets(for:)` de verdade, não um dublê.
swift_check plugincheck       Knobler/Plugin.swift Knobler/Pomodoro.swift \
  Knobler/Reminders.swift Knobler/Descanso.swift Knobler/NotchSectionOrder.swift \
  Knobler/Peer.swift Knobler/Wire.swift Knobler/LANMessaging.swift Knobler/MessageStore.swift \
  Knobler/Permissions.swift Knobler/WebhookClient.swift Knobler/WebhookKeychainStore.swift \
  Knobler/NotchNotification.swift Knobler/FileConverter.swift Knobler/ImageConverter.swift \
  Knobler/DocumentConverter.swift Knobler/VideoConverter.swift tools/plugincheck.swift
CONVERSAO="Knobler/FileConverter.swift Knobler/ImageConverter.swift Knobler/DocumentConverter.swift Knobler/VideoConverter.swift"
swift_check imageconvertercheck    $CONVERSAO tools/imageconvertercheck.swift
swift_check documentconvertercheck $CONVERSAO tools/documentconvertercheck.swift
swift_check sharingcheck          Knobler/Sharing.swift Knobler/AirDrop/AirDropEnvio.swift Knobler/AirDrop/AirDropRegras.swift Knobler/NotificationRules.swift tools/sharingcheck.swift
swift_check airdropcheck          Knobler/AirDrop/AirDropRegras.swift tools/airdropcheck.swift
# Confirmação passa pelo ShelfStore real, incluindo falha e sucesso parcial.
swift_check conversionpreviewcheck $CONVERSAO Knobler/ShelfPreview.swift \
  Knobler/ShelfStore.swift Knobler/ShelfOrdem.swift tools/conversionpreviewcheck.swift
# arrasta o FileConverter junto: o nome único do arquivo materializado sai de lá.
swift_check shelfdropcheck        $CONVERSAO Knobler/ShelfDrop.swift \
  Knobler/LinkBrowser.swift tools/shelfdropcheck.swift

swift_check shelfordemcheck       Knobler/ShelfOrdem.swift tools/shelfordemcheck.swift
swift_check screenshotcheck       Knobler/ScreenshotWatcher.swift Knobler/Permissions.swift tools/screenshotcheck.swift
swift_check historycheck          Knobler/NotchNotification.swift Knobler/NotificationHistory.swift Knobler/NotchGesture.swift tools/historycheck.swift
swift_check sectionordercheck    Knobler/NotchSectionOrder.swift tools/sectionordercheck.swift
swift_check tecladocheck         Knobler/TecladoBloqueado.swift tools/tecladocheck.swift
# a decisão pura da instância única; o caminho AppKit de verdade é o
# instancia-e2e, mais abaixo, que precisa de sessão gráfica.
swift_check instanciacheck       Knobler/InstanciaUnica.swift tools/instanciacheck.swift
# Arquivo do token de agente: pasta 0700 mesmo já existindo, arquivo 0600 desde o primeiro byte.
swift_check tokencheck           Knobler/TokenDeAgente.swift tools/tokencheck.swift
# Registro de desempenho: formato da linha, cpu_pct e poda sem reescrita a cada amostra.
swift_check desempenhocheck      Knobler/Desempenho.swift tools/desempenhocheck.swift
# Avatar remoto: o cache guarda a miniatura (≤ 128 px), não a imagem cheia.
swift_check avatarcheck          Knobler/RemoteAvatarLoader.swift tools/avatarcheck.swift
# Preview de link: o "voltar" não atravessa pra sessão anterior. WKWebView de
# verdade contra um servidor HTTP no loopback, numa porta que o kernel escolhe.
swift_check linkpreviewcheck     Knobler/LinkPreview.swift Knobler/LinkBrowser.swift tools/linkpreviewcheck.swift
# Diagnóstico passivo: a integração não pode sumir nem voltar a reconstruir a raiz.
run cortedetectorcheck bash -c '
grep -qF "SensorDeCorte(vigia: vigia, aVista: vm.painelAVista" Knobler/NotchView.swift || exit 1
grep -qF "viewModel.painelAVista = { [weak panel] in panel?.isVisible == true }" Knobler/KnoblerApp.swift || exit 1
! grep -qF "id(vigia.geracao)" Knobler/NotchView.swift || exit 1
grep -qF "NotchHostingView(" Knobler/KnoblerApp.swift || exit 1
xcrun swiftc -parse-as-library -swift-version 5 \
  Knobler/CorteDoKnob.swift tools/cortedetectorcheck.swift \
  -o /tmp/cortedetectorcheck && /tmp/cortedetectorcheck'
# O host AppKit real na sequência do placeWindows: nascer e trocar de resolução
# não gravam; corte e cura gravam. Abre um painel com alpha 0, fora da tela.
swift_check cortehostcheck       Knobler/CorteDoKnob.swift Knobler/NotchWindow.swift tools/cortehostcheck.swift
# Ganhou o mesmo bloco de arquivos do plugincheck na tarefa 8 (nota vira
# peça): `extension QuickNote: PluginServico` (QuickNote.swift) precisa do
# protocolo de Plugin.swift, que por sua vez arrasta os tipos que as outras
# fichas referenciam.
swift_check quicknotecheck        Knobler/QuickNote.swift Knobler/Plugin.swift Knobler/Pomodoro.swift \
  Knobler/Reminders.swift Knobler/Descanso.swift Knobler/NotchSectionOrder.swift \
  Knobler/Peer.swift Knobler/Wire.swift Knobler/LANMessaging.swift Knobler/MessageStore.swift \
  Knobler/Permissions.swift Knobler/WebhookClient.swift Knobler/WebhookKeychainStore.swift \
  Knobler/NotchNotification.swift tools/quicknotecheck.swift
swift_check permissioncheck       Knobler/Permissions.swift tools/permissioncheck.swift
swift_check textodatelacheck      Knobler/TextoDaTela.swift tools/textodatelacheck.swift
swift_check annotationcheck      Knobler/AnnotationModel.swift tools/annotationcheck.swift
swift_check appleremindersuicheck Knobler/AppleReminders.swift Knobler/AppleRemindersStore.swift Knobler/AppleRemindersView.swift Knobler/AppleRemindersNotchView.swift tools/appleremindersuicheck.swift
swift_check applereminderscheck Knobler/AppleReminders.swift Knobler/AppleRemindersStore.swift tools/applereminderscheck.swift
swift_check calendariocheck       Knobler/CalendarAviso.swift tools/calendariocheck.swift
# arrasta o Updater: a comparação de versão da página de novidades é o
# isNewer/versionComponents dele, mesmo caminho do avisoscheck. E o mesmo
# bloco de arquivos do plugincheck: data-alvo="instalarPeca" é validado
# contra o PluginID de verdade.
swift_check novidadescheck        Knobler/Updater.swift Knobler/NovidadesCatalogo.swift \
  Knobler/Plugin.swift Knobler/Pomodoro.swift \
  Knobler/Reminders.swift Knobler/Descanso.swift Knobler/NotchSectionOrder.swift \
  Knobler/Peer.swift Knobler/Wire.swift Knobler/LANMessaging.swift Knobler/MessageStore.swift \
  Knobler/Permissions.swift Knobler/WebhookClient.swift Knobler/WebhookKeychainStore.swift \
  Knobler/NotchNotification.swift Knobler/FileConverter.swift Knobler/ImageConverter.swift \
  Knobler/DocumentConverter.swift Knobler/VideoConverter.swift \
  tools/novidadescheck.swift
# arrasta o Updater: a faixa de versão do aviso usa o isNewer/versionComponents
# dele, e o gate também valida o avisos.json publicado neste repo.
swift_check avisoscheck           Knobler/Updater.swift Knobler/DevAvisos.swift tools/avisoscheck.swift
# "tique não carimba": o VM inteiro sobe isolado, e por isso arrasta os tipos
# que ele cita (Pomodoro, AirPods, notificação, Wire, Updater).
swift_check eventoscheck          Knobler/NotchViewModel.swift Knobler/NotchPresentation.swift Knobler/NotchSectionOrder.swift \
  Knobler/Pomodoro.swift Knobler/AirPodsBattery.swift Knobler/NotchNotification.swift \
  Knobler/NotificationHistory.swift Knobler/QuickNote.swift Knobler/Wire.swift \
  Knobler/LinkPreview.swift Knobler/LinkBrowser.swift \
  Knobler/Updater.swift \
  Knobler/AnnotationModel.swift Knobler/AnnotationController.swift Knobler/CalendarAviso.swift \
  Knobler/AppSettings.swift Knobler/Descanso.swift Knobler/Mirror.swift \
  Knobler/Reminders.swift Knobler/Peer.swift Knobler/LANMessaging.swift \
  Knobler/MessageStore.swift Knobler/Permissions.swift Knobler/Plugin.swift \
  Knobler/WebhookClient.swift Knobler/WebhookKeychainStore.swift Knobler/TecladoBloqueado.swift tools/eventoscheck.swift
# Ajudantes swift_teste/bash_teste, bloco do WhatsApp e os gates
# whatsappgatescheck/notchfontescheck, cada um provado num repo falso.
run gateajudantescheck bash tools/gateajudantescheck.sh
# --- WhatsApp (docs/whatsapp.md) ---
bash_teste tools/whatsappgatescheck.sh
bash_teste tools/notchfontescheck.sh
# tipos do contrato da ponte (docs/whatsapp-ponte.md) e decodificação
swift_teste tools/whatsappmodeloscheck.swift Knobler/WhatsApp/WhatsAppModelos.swift
# chave da ponte, porta configurável e conclusão da sonda de GET /
swift_teste tools/whatsappchavecheck.swift Knobler/WhatsApp/WhatsAppModelos.swift Knobler/WhatsApp/WhatsAppChave.swift
# cliente HTTP da ponte: rotas, chave, releitura no 401 e erros do contrato
swift_teste tools/whatsappclientecheck.swift Knobler/WhatsApp/WhatsAppModelos.swift Knobler/WhatsApp/WhatsAppChave.swift Knobler/WhatsApp/WhatsAppCliente.swift
# exceção de ATS só para 127.0.0.1, no Info.plist e no project.yml
bash_teste tools/whatsappatscheck.sh
# sondagem de GET /v1/ponte: só com o arquivo da chave, janela de 30 s
swift_teste tools/whatsappsondacheck.swift Knobler/WhatsApp/WhatsAppModelos.swift Knobler/WhatsApp/WhatsAppChave.swift Knobler/WhatsApp/WhatsAppCliente.swift Knobler/WhatsApp/WhatsAppSonda.swift
# canal ao vivo por WebSocket: cursor/desde, reconexão, sinal de vida, wake, App Nap
swift_teste tools/whatsappcanalcheck.swift Knobler/WhatsApp/WhatsAppModelos.swift Knobler/WhatsApp/WhatsAppChave.swift Knobler/WhatsApp/WhatsAppCanal.swift
# estado puro: eventos, dedupe, ordem, apelidos, não lidas, rascunho
swift_teste tools/whatsappestadocheck.swift Knobler/WhatsApp/WhatsAppModelos.swift Knobler/WhatsApp/WhatsAppEstado.swift
# bolha de envio: enviando/enviada/entregue/lida/falhou casada pelo ref, retry manual
swift_teste tools/whatsappbolhacheck.swift Knobler/WhatsApp/WhatsAppModelos.swift Knobler/WhatsApp/WhatsAppEstado.swift
# núcleo do estado: todo gate que compila o WhatsAppStore usa esta lista
# (as próximas etapas acrescentam arquivos nela)
WA_NUCLEO="Knobler/WhatsApp/WhatsAppModelos.swift Knobler/WhatsApp/WhatsAppChave.swift \
  Knobler/WhatsApp/WhatsAppCliente.swift Knobler/WhatsApp/WhatsAppCanal.swift \
  Knobler/WhatsApp/WhatsAppEstado.swift Knobler/WhatsApp/WhatsAppStore.swift \
  Knobler/WhatsApp/WhatsAppGravacao.swift Knobler/WhatsApp/CodificadorOpus.swift \
  Knobler/WhatsApp/OggOpus.swift Knobler/WhatsApp/WhatsAppMidia.swift"
# singleton inerte até start: cliente + canal + estado, carga, envio, lida, stop
swift_teste tools/whatsappstorecheck.swift $WA_NUCLEO
# seção .whatsapp: enum, ordem, atalhos, largura 780 e altura 360
swift_teste tools/whatsappsecaocheck.swift Knobler/NotchSectionOrder.swift Knobler/NotchPresentation.swift
# peça escondida: desinstalada em instalação nova, fora da vitrine sem a ponte
# (mesmas fontes do plugincheck; a vitrine recebe o booleano, sem WhatsAppSonda)
swift_teste tools/whatsappescondidacheck.swift Knobler/Plugin.swift Knobler/Pomodoro.swift \
  Knobler/Reminders.swift Knobler/Descanso.swift Knobler/NotchSectionOrder.swift \
  Knobler/Peer.swift Knobler/Wire.swift Knobler/LANMessaging.swift Knobler/MessageStore.swift \
  Knobler/Permissions.swift Knobler/WebhookClient.swift Knobler/WebhookKeychainStore.swift \
  Knobler/NotchNotification.swift Knobler/FileConverter.swift Knobler/ImageConverter.swift \
  Knobler/DocumentConverter.swift Knobler/VideoConverter.swift
# o VM inteiro, isolado: a mesma lista do eventoscheck (o VM não conhece tipo
# nenhum de Knobler/WhatsApp/, só String/Bool)
VM_FONTES="Knobler/NotchViewModel.swift Knobler/NotchPresentation.swift Knobler/NotchSectionOrder.swift \
  Knobler/Pomodoro.swift Knobler/AirPodsBattery.swift Knobler/NotchNotification.swift \
  Knobler/NotificationHistory.swift Knobler/QuickNote.swift Knobler/Wire.swift \
  Knobler/LinkPreview.swift Knobler/LinkBrowser.swift Knobler/Updater.swift \
  Knobler/AnnotationModel.swift Knobler/AnnotationController.swift Knobler/CalendarAviso.swift \
  Knobler/AppSettings.swift Knobler/Descanso.swift Knobler/Mirror.swift \
  Knobler/Reminders.swift Knobler/Peer.swift Knobler/LANMessaging.swift \
  Knobler/MessageStore.swift Knobler/Permissions.swift Knobler/Plugin.swift \
  Knobler/WebhookClient.swift Knobler/WebhookKeychainStore.swift Knobler/TecladoBloqueado.swift"
# fila de notificação com o campo do WhatsApp: precedência, supressão da
# conversa aberta, junção por conversa, card de chegada 360 × 96 (+126), 20 s
swift_teste tools/whatsappfilacheck.swift $VM_FONTES
# card de chegada: texto, conta, grupo, mídia, agrupamento por conversa, idade máxima
swift_teste tools/whatsappcartaocheck.swift Knobler/WhatsApp/WhatsAppModelos.swift Knobler/NotchNotification.swift Knobler/WhatsApp/WhatsAppCartao.swift
# peça ligada: instalar nasce uma vez, desinstalar para uma vez, reinstalar
# nasce de novo, instalação nova não nasce (mesmas fontes do plugincheck)
swift_teste tools/whatsapppecacheck.swift Knobler/Plugin.swift Knobler/Pomodoro.swift \
  Knobler/Reminders.swift Knobler/Descanso.swift Knobler/NotchSectionOrder.swift \
  Knobler/Peer.swift Knobler/Wire.swift Knobler/LANMessaging.swift Knobler/MessageStore.swift \
  Knobler/Permissions.swift Knobler/WebhookClient.swift Knobler/WebhookKeychainStore.swift \
  Knobler/NotchNotification.swift Knobler/FileConverter.swift Knobler/ImageConverter.swift \
  Knobler/DocumentConverter.swift Knobler/VideoConverter.swift
# a ligação que só o app compila: efeitos antes do subir(), sonda depois,
# conformidade isolada em WhatsAppPeca.swift, card índigo na vitrine
bash_teste tools/whatsapppecaligacaocheck.sh
# banner do WhatsApp Desktop: some só com a ponte conectada; o sharingcheck
# (mais acima) compila o mesmo NotificationRules.swift e segue valendo
swift_teste tools/whatsappbannercheck.swift Knobler/NotificationRules.swift
# a ligação que só o app compila: propriedade e chamada no interceptor entre o
# AirDrop e os botões, estado da ponte entregue pelo AppDelegate
bash_teste tools/whatsappbannerligacaocheck.sh
# silêncio por microfone desconta o uso do próprio Knobler (ditado e gravação
# de áudio); o sharingcheck (mais acima) segue provando o limiar antigo
swift_teste tools/whatsappmicrofonecheck.swift Knobler/NotificationRules.swift Knobler/UsoProprioDoMicrofone.swift
# a ligação que só o app compila: marca no MicRecorder depois do engine abrir,
# entregue pelo AppDelegate à regra, frase antiga fora do docs/notifications.md
bash_teste tools/whatsappmicrofoneligacaocheck.sh
# texto de permissão do microfone genérico (ditado e gravação de áudio, sem
# citar o WhatsApp): project.yml, Info.plist e Permission.microfone.why; o
# permissioncheck (mais acima) segue valendo pro resto do Permissions.swift
bash_teste tools/whatsappmicpermissaocheck.sh
# ditado no campo do WhatsApp em uso: Ask vence, depois o campo, depois o app
# da frente; receberDitado só na conversa do campo, com um espaço só
swift_teste tools/whatsappditadocheck.swift Knobler/DictationDestination.swift $WA_NUCLEO
# a ligação que só o app compila: enum fora do Dictation.swift, case .whatsapp
# copiando na recusa, escolher/campoEmUso/receberDitado no AppDelegate
bash_teste tools/whatsappditadoligacaocheck.sh
# nota de voz: CRC do Ogg, OpusHead/OpusTags, duração pelo TOC, páginas relidas
# por um leitor próprio, e 2 s de seno codificados de verdade (AVAudioFile em 26+)
swift_teste tools/whatsappoggcheck.swift Knobler/WhatsApp/OggOpus.swift Knobler/WhatsApp/CodificadorOpus.swift
# nota de voz gravada: onda de 64 barras pelo nível do microfone, segundos
# arredondados pra cima, gravar/cancelar/descartar curta, envio do Ogg pela
# pasta de envio (apagado depois da resposta), bolha de voz e lida no sucesso
swift_teste tools/whatsappgravacaocheck.swift $WA_NUCLEO
# a ligação que só o app compila: MicrofoneDoDitado sobre o MicRecorder com
# onLevel, entregue ao store em WhatsAppPeca.ligar() antes do start()
bash_teste tools/whatsappgravacaoligacaocheck.sh
# mídia: caminho do cache pela regra da ponte, download guardado, recuperação
# única da expirada, miniatura em memória, anexo copiado pra pasta de envio
# (apagado depois da resposta, 100 MiB no máximo) e tocador do áudio recebido
swift_teste tools/whatsappmidiacheck.swift $WA_NUCLEO Knobler/WhatsApp/WhatsAppPlayer.swift
# --- fim WhatsApp ---
# No macOS 27 o NSLog chega ao log unificado só como <private>: log do app é os.Logger
# (docs/development.md, seção Logs).
run semnslog bash -c '! grep -rn "NSLog(" Knobler'
# Reminders traz o próprio @main atrás de -D (molde do Pomodoro), sem harness.
run reminderscheck bash -c "xcrun swiftc -parse-as-library -swift-version 5 \
  -D REMINDERS_SELFCHECK Knobler/Reminders.swift -o /tmp/reminderscheck && /tmp/reminderscheck"

echo "== gates de integração =="
# `Knobler --selfcheck` (teardown do Ditado, Desenho, Espelho, Nota rápida e
# Preview de Link). NÃO é hermético: precisa do app inteiro compilado, e um
# `xcodebuild` do zero leva minutos — caro demais pra um gate que roda a cada
# push. Por isso o gate só roda o binário que JÁ existir no DerivedData; sem
# build local ele é pulado, e aí esses self-checks continuam manuais
# (`xcodebuild ... build` e depois o binário com `--selfcheck`).
SELFCHECK_BIN=$(ls -td ~/Library/Developer/Xcode/DerivedData/Knobler-*/Build/Products/Debug/Knobler.app/Contents/MacOS/Knobler 2>/dev/null | head -1)
if [ -n "$SELFCHECK_BIN" ]; then
  run app-selfcheck bash -c "'$SELFCHECK_BIN' --selfcheck"
else
  SKIPPED+=("app-selfcheck (sem build Debug no DerivedData)")
fi
run claude-hook          bash tools/claude-hook/test.sh
run codex-bridge         node tools/codex-agent-bridge-check.mjs
run agent-requests-e2e   node tools/agent-requests-e2e.mjs
# só os testes herméticos do relay: db/hub/server exigem better-sqlite3 e ws instalados
for t in template normalize ratelimit tokens; do
  run "relay-$t" node --test "relay/test/$t.test.js"
done
run site-build bash -c "cd site && npm ci && cd .. && node --test site/tests/*.test.mjs"

if [ "$WITH_ENV" -eq 1 ]; then
  echo "== gates que dependem do ambiente =="
  if command -v codex >/dev/null; then
    run codex-integration node tools/codex-integration-check.mjs
  else
    SKIPPED+=("codex-integration (codex CLI não instalado)")
  fi
  run instancia-e2e bash tools/instancia-e2e.sh
else
  SKIPPED+=("codex-integration (rode com --com-ambiente)")
  SKIPPED+=("instancia-e2e (rode com --com-ambiente)")
fi

echo
for s in ${SKIPPED+"${SKIPPED[@]}"}; do echo "  pulado: $s"; done
if [ ${#FAILED[@]} -gt 0 ]; then
  echo "❌ $PASSED ok, ${#FAILED[@]} falhou: ${FAILED[*]}"
  exit 1
fi
echo "✅ $PASSED checks ok"
