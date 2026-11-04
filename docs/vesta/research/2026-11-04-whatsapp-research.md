# Pesquisa — WhatsApp no notch

Spec: `docs/vesta/specs/2026-11-04-whatsapp-design.md`

Cinco frentes em paralelo; todo achado que contradiz a spec passou por um cético que voltou à fonte. `Verificação` registra o veredito e a correção dele. Achado refutado fica marcado e fora da fila.

## Achados

### Frente: Reuso e decisões documentadas

#### A1 — A chave compartilhada no Chaveiro entre ponte (Go), Knobler e MCP (Python) esbarra na ACL do item: ela pertence a quem gravou. O Knobler lê com interação desligada e recebe nil, então vê a chave como "ausente" sem erro nenhum. Já existe no repo um precedente de segredo dividido entre processos locais: arquivo 0600 numa pasta 0700.
- Fonte: Knobler/WebhookKeychainStore.swift:27-53
- Contradiz a spec: sim
- Pergunta que levanta: Se a chave ficar no Chaveiro dividido entre ponte, Knobler e MCP, toda vez que um dos três for reinstalado ou reassinado o Knobler passa a dizer "a chave não confere" (ou o Mac pede sua senha). Prefere guardar a chave num arquivo que só a sua conta lê, como já é feito com o token dos agentes? Nesse caso qualquer programa rodando com o seu usuário consegue lê-la.
- Evidência: WebhookKeychainStore.swift:27-39: "A ACL destes itens confia no requisito de assinatura de quem os gravou... Preferimos falhar aqui" (SecKeychainSetUserInteractionAllowed(false)). MEMORY.md 2026-07-29: gravar com `security add-generic-password` deixa o app com exists==true e load==nil. Precedente: Knobler/TokenDeAgente.swift:1-16,44-60 grava o token num arquivo 0600 em Application Support/Knobler, que hooks, ponte do Codex e tools/knobler leem.
- Verificação: se sustenta — A fonte confirma: WebhookKeychainStore.swift:27-39 lê com SecKeychainSetUserInteractionAllowed(false), e a ACL confia em quem gravou. O precedente 0600/0700 também confere (TokenDeAgente.swift:37-60). Duas imprecisões. (1) Não é verdade que o Knobler veja a chave como 'ausente sem erro nenhum': existsRaw (linhas 41+) foi feito justamente para separar 'nunca gravado' de 'gravado mas trancado'. (2) Não é impossível: o item pode nascer com uma ACL que libera vários apps ou qualquer app (opções -T/-A do comando security). O problema real é a ponte Go: com assinatura ad-hoc, cada go build gera outro cdhash e quebra a ACL de quem confiava nela. 'sim' é forte demais; 'parcial' é mais justo, porque muda o meio de guardar a chave e não a arquitetura.

#### A2 — A vitrine de peças desenha todas as peças do registro, sem condição nenhuma. Hoje não existe jeito de uma peça aparecer só quando a ponte responde: isso é mecanismo novo, não reuso do sistema de plugins.
- Fonte: Knobler/PluginsSettingsPane.swift:133-140
- Contradiz a spec: parcial
- Pergunta que levanta: Esconder a peça do WhatsApp de quem não tem a ponte exige mexer na vitrine, que hoje mostra todas as peças sempre. Prefere esse trabalho extra, deixar a peça visível pra todos com o aviso "precisa da ponte", ou deixar o WhatsApp fora do sistema de peças?
- Evidência: `ForEach(PluginRegistry.todos, id: \.id) { peca in CardPeca(...) { acao(peca) } }`. A ficha `Plugin` (Plugin.swift:226-255) só tem nome, descricao, simbolo, secao, painel, rotas, permissao, pronta e nascer. Nenhum campo de visibilidade. E o gate tools/plugincheck.swift:98 exige `todos.count == PluginID.allCases.count`.
- Verificação: se sustenta — Confere: PluginsSettingsPane.swift:133-140 percorre PluginRegistry.todos sem filtro, e a ficha Plugin (Plugin.swift:226-255) não tem campo de visibilidade. Só que o gate tools/plugincheck.swift:98 (todos.count == allCases.count) não atrapalha: esconder seria um filtro na vitrine, não tirar a peça do registro. Também já existe o caminho 'instalada mas não sobe': o nascer pode devolver nil quando falta dependência (Plugin.swift:251-255). Então é mecanismo novo, mas pequeno.

#### A3 — Em instalação nova, toda peça entra instalada, menos Monitores e Texto da tela. Um PluginID novo do WhatsApp nasceria ligado pra quem instala pelo brew, a menos que entre na lista de exceções e no gate.
- Fonte: Knobler/Plugin.swift:413-417
- Contradiz a spec: parcial
- Pergunta que levanta: Quem instala o Knobler do zero ganha toda peça nova já ligada. A do WhatsApp deve nascer desligada, como Texto da tela (você liga uma vez na sua máquina e ninguém mais carrega nada dela), ou ligada?
- Evidência: `d.set(PluginID.allCases.filter { $0 != .monitores && $0 != .textoDaTela }.map(\.rawValue), forKey: chave)`. tools/plugincheck.swift:125-128 trava essa lista ("Texto da tela precisa começar desinstalada").
- Verificação: se sustenta — Confere para instalação nova: Plugin.swift:413-417 instala tudo menos .monitores e .textoDaTela, e plugincheck.swift:125-128 trava essa lista. Faltou dizer que quem já migrou (versaoMigracao = 1) NÃO ganha um PluginID novo, porque a migração roda uma vez só. O Agentes precisou de passo próprio por isso (acrescentarAgentesSePreciso, Plugin.swift:419-428). Além disso, peça instalada numa máquina sem a ponte pode simplesmente não subir (nascer devolve nil). O efeito para quem vem do brew é menor do que o achado sugere.

#### A4 — Feature nova pede release MINOR, e MINOR exige uma página de novidades que abre sozinha pra todo usuário no primeiro launch. Isso bate de frente com "quem instala pelo brew não vê nada".
- Fonte: VERSIONING.md:14,51-54
- Contradiz a spec: sim
- Pergunta que levanta: Toda feature nova obriga uma página de novidades que abre na tela de todo mundo. Você topa anunciar algo que só você usa, publicar como correção sem anúncio (furando a regra de versão do projeto) ou manter a feature num build só seu, fora do brew?
- Evidência: VERSIONING.md:14 "MINOR 0.X.0 | feature ou capacidade nova de usuário". VERSIONING.md:51: "MINOR (e MAJOR) exigem página de novidades... tools/release.sh minor/major aborta sem o arquivo". tools/release.sh:86-91 aborta. docs/novidades.md:29: "Primeiro launch de cada versão nova: a página abre sozinha".
- Verificação: se sustenta — As fontes conferem: VERSIONING.md:14 e :51-54, tools/release.sh:86-91 e docs/novidades.md:29. Mas a página de novidades é por versão, não por feature: um MINOR que leve outra feature junto pode anunciar só a outra. O vazamento maior seria a entrada do CHANGELOG, que vira nota pública do GitHub Release. E a regra é do próprio dono, não uma restrição técnica. Por isso cabe mais 'parcial' que 'sim': é conflito de processo, a spec não assume nada errado sobre o código.

#### A5 — O card de mensagem com resposta rápida que já existe (o das Mensagens LAN) tem uma vaga só: a mensagem nova apaga a anterior. Ele também não passa pelo silêncio de reunião/chamada nem pelo Histórico. O card de notificação faz fila, respeita o silêncio e grava no Histórico, mas não tem campo de resposta.
- Fonte: Knobler/NotchViewModel.swift:248-258,603-615
- Contradiz a spec: parcial
- Pergunta que levanta: Hoje o banner do WhatsApp Desktop fica quieto durante reunião e vai pro Histórico. O card com resposta rápida que já existe mostra uma mensagem por vez (a nova apaga a anterior) e aparece mesmo no meio de uma call. Em grupo movimentado ou em reunião, qual dos dois comportamentos você quer?
- Evidência: `@Published var incoming: IncomingMessage?` e `showIncoming` faz `incoming = m` (vaga única, some em 20 s com resposta). LAN chama `showIncoming` direto (KnoblerApp.swift:534-538), sem `publicar`. `publicar` (KnoblerApp.swift:1726-1732) desvia pro Histórico quando `silenciando`, e `enqueue` (NotchViewModel.swift:663-664) grava `NotificationHistory`. docs/notifications.md:49-53.
- Verificação: se sustenta — Confere: incoming é uma vaga só (NotchViewModel.swift:258, 603-606), a LAN chama showIncoming direto (KnoblerApp.swift:534-538), publicar desvia pro Histórico quando está silenciando (KnoblerApp.swift:1727-1732) e enqueue grava o Histórico (NotchViewModel.swift:663-664). Um detalhe: o card de notificação tem botões de ação (actionTitles), só não tem campo de texto. E o silêncio por reunião/microfone é opt-in, então o 'fica quieto durante reunião' só vale com a opção ligada.

#### A6 — Tudo que vira card de notificação fica 24 h em texto claro no disco (Histórico). A spec diz que o Knobler não guarda conversa em disco, o que conflita se o card do WhatsApp passar pelo caminho de notificação.
- Fonte: Knobler/NotificationHistory.swift:9-17
- Contradiz a spec: parcial
- Pergunta que levanta: Se o card do WhatsApp entrar no Histórico, o texto das mensagens das duas contas fica 24 h em claro no seu disco, como já acontece hoje com o banner do WhatsApp Desktop. Mantém isso pra poder rever o que passou, ou o WhatsApp fica fora do Histórico?
- Evidência: "Os corpos das notificações passam a ficar em claro em Application Support por 24 h — mesma exposição do messages.json". docs/architecture.md:164: "Notificações das últimas 24 h (em disco) | NotificationHistory.shared".
- Verificação: se sustenta — Confere: NotificationHistory.swift:9-17 e architecture.md:164. O conflito só existe se o card do WhatsApp passar por enqueue/publicar. Um card no molde do incoming da LAN não grava no Histórico.

#### A7 — Não há cliente SSE no repo. O cliente ao vivo que existe é o WebSocket do WebhookClient, já com reconexão com espera aleatória crescente (teto de 30 s), reconexão ao acordar do sleep e proteção contra App Nap. Só que ele para de tentar quando o monitor de rede diz "offline", e isso derrubaria também a conexão com a ponte local.
- Fonte: Knobler/WebhookClient.swift:191-209,266-291
- Contradiz a spec: parcial
- Pergunta que levanta: Já existe no app um canal ao vivo testado em produção (o dos webhooks), que reconecta depois do sleep e não cochila, mas é WebSocket, não o canal que a spec escolheu. Reaproveitar ele economiza código e bugs já resolvidos. Só que ele desiste quando o Mac fica sem internet: com a ponte local, a seção deve continuar mostrando o histórico mesmo offline?
- Evidência: Linha 68: `private let path = NWPathMonitor(); private var online = true`. Linha 192: `guard running, online else { return }`. Linha 193: `min(backoffCap, pow(2, Double(attempt)))`, backoffCap = 30. Linha 282: `didWake → forceReconnect`. Linhas 284-287: `beginActivity(.userInitiatedAllowingIdleSystemSleep)`. A busca por event-stream/EventSource em Knobler/ não acha nada relevante.
- Verificação: se sustenta — Confere: não há cliente SSE no repo (os grep de EventSource só acham CGEventSource). As linhas citadas batem: backoffCap = 30, jitter, guard online, didWake → forceReconnect, beginActivity. Mas o WebhookClient é amarrado ao relay remoto (URLSessionWebSocketTask com ping/pong de 25/10 s). O reuso é do padrão, copiando a lógica de backoff, wake, App Nap e caminho de rede, não da classe. Adotá-lo como está exigiria que a ponte Go servisse WebSocket em vez de SSE.

#### A8 — Polling frequente em loopback já foi motivo de refazer outra parte do app: cada conexão deixa umas 20 linhas no log do sistema. A spec propõe tentar reconectar "a cada poucos segundos" com a ponte fora.
- Fonte: Knobler/NotchAPILongPoll.swift:4-9
- Contradiz a spec: parcial
- Pergunta que levanta: Com a ponte desligada por horas, tentar religar a cada poucos segundos enche o log do Mac, e isso já fez o projeto refazer outra peça. Aceita um intervalo que cresce até uns 30 s, ao custo de demorar até meio minuto pra voltar quando você religar a ponte?
- Evidência: "mandava um GET a cada 0,3 s, e cada conexão deixa umas 20 linhas do Network.framework no log do sistema". O WebhookClient usa teto de 30 s com jitter (WebhookClient.swift:67,193).
- Verificação: se sustenta — A fonte (NotchAPILongPoll.swift:4-9) confere, mas a escala é outra. O caso refeito era um GET a cada 0,3 s de vários clientes; 'a cada poucos segundos' é uma ordem de grandeza mais raro. O ponto continua válido para a ponte fora por horas, e o teto de 30 s com jitter já existe (WebhookClient.swift:67,193).

#### A9 — Microfone ligado há 20 s ou mais conta como "chamada" e silencia os cards. O código assume que o único uso do mic pelo próprio Knobler é o ditado, que é curto. Gravar um áudio longo de WhatsApp pelo notch cairia nessa regra.
- Fonte: Knobler/KnoblerApp.swift:1735-1746
- Contradiz a spec: parcial
- Pergunta que levanta: Gravar um áudio de mais de 20 s pelo notch faz o Knobler achar que você está numa ligação: os cards que chegarem nesse tempo não aparecem e vão direto pro Histórico. Tudo bem, ou a gravação do próprio Knobler não deve contar como chamada?
- Evidência: "ponytail: o ditado do próprio Knobler também acende o microfone, e não há código aqui pra descontar isso — ele dura segundos, fica abaixo do limiar". docs/notifications.md:64-69. NotificationRules.swift:47 limiar = 20.
- Verificação: se sustenta — Confere: limiar de 20 s (NotificationRules.swift:47) e o ponytail em KnoblerApp.swift:1739-1741. Mas silenciarComMicrofone é opt-in (docs/notifications.md:71) e só pega cards que passam por publicar. O ditado (e uma gravação do próprio notch) também não silencia o card incoming da LAN. Então só acontece com a opção ligada e o card do WhatsApp roteado por publicar. NotificationRules.swift:41-44 já cita 'gravar um áudio de WhatsApp' como uso curto do microfone.

#### A10 — O gravador do ditado (MicRecorder) já resolve microfone com fone Bluetooth (grava pelo mic embutido pra não derrubar o áudio do fone), troca de dispositivo e NSException do installTap. Mas ele mora no mesmo arquivo que importa FluidAudio e sai em Float32 mono 16 kHz.
- Fonte: Knobler/Dictation.swift:100-130
- Contradiz a spec: nao
- Pergunta que levanta: Reaproveitar o gravador do ditado traz de graça a proteção do fone Bluetooth (gravar não estraga a música tocando nos AirPods), mas exige separá-lo do ditado, e a voz sai em qualidade de ditado (16 kHz). Serve pra mandar áudio no WhatsApp, ou você quer qualidade maior?
- Evidência: `/// Mic → Float32 mono 16kHz` e `static let sampleRate: Double = 16000`. Fallback BT nas linhas 123-129. Plugin.swift:124-132 avisa que referenciar o ditado arrasta FluidAudio pro compile isolado do plugincheck.

#### A11 — O texto de permissão do microfone, tanto o do sistema quanto o do painel Permissões, fala só do ditado. Usar o mic pra áudio de WhatsApp deixa o texto impreciso, e corrigi-lo muda o app de todo mundo.
- Fonte: project.yml:59
- Contradiz a spec: parcial
- Pergunta que levanta: O texto que explica o uso do microfone fala só do ditado. Atualizar pra citar áudio de WhatsApp muda o texto pra todos os usuários do brew, revelando a feature escondida. Deixar como está fica impreciso só pra você. Qual prefere?
- Evidência: project.yml:59 `NSMicrophoneUsageDescription: Knobler grava sua voz enquanto você segura a tecla de ditado`. Knobler/Permissions.swift:59-60 `case .microfone: return "Grava sua voz enquanto você segura a ⌥ direita."`. Plugin.swift:308 permissao "microfone" fica só no Ditado.
- Verificação: se sustenta — Os textos conferem (project.yml:59, Permissions.swift:59-60), mas a linha do Plugin está errada: a permissao "microfone" do Ditado fica em Plugin.swift:316, não em 308. E o texto do sistema só aparece no primeiro pedido de permissão: para quem já concedeu, nada muda na prática. O risco de 'revelar a feature' é pequeno.

#### A12 — O carregador de foto remota recusa http e qualquer IP de loopback (127.x), e não manda cabeçalho de chave. Ele não serve pra foto de perfil vinda da ponte em 127.0.0.1:8099. Só a parte de miniatura e cache dele é reaproveitável.
- Fonte: Knobler/RemoteAvatarLoader.swift:59-72,81-86
- Contradiz a spec: parcial
- Pergunta que levanta: O carregador de fotos que já existe bloqueia endereço local por segurança, porque também atende webhooks de terceiros. Afrouxar essa regra pra ponte enfraquece a proteção dos webhooks. Prefere um caminho separado pra foto do WhatsApp, com mais código mas sem mexer na segurança que já existe?
- Evidência: `if a == 127 || a == 10 || a == 0 { return true }` e `url.scheme?.lowercased() == "https", !Self.isPrivateHost(url.host) else { image = nil; return }`. Reaproveitável: `static func miniatura(de:ladoMaximo:)` (46-56) e o cache de 64 miniaturas.
- Verificação: se sustenta — Confere: load exige https e isPrivateHost recusa 127.x literal (RemoteAvatarLoader.swift:68, 83-85), e o loader não manda cabeçalho de autenticação. Detalhe: o hostname 'localhost' passaria pelo filtro de host, mas cai igual porque a ponte é http. miniatura(de:) e o NSCache (linhas 21-23, 46-56) são reaproveitáveis.

#### A13 — A seção Mensagens LAN já tem lista, conversa colada embaixo, compositor com anexo e bolha "não entregue". Mas grava conversa em disco (até 20 por pessoa), o anexo só aceita jpeg/png/gif e a bolha só conhece entregue/não entregue.
- Fonte: Knobler/MessagesView.swift:94-116
- Contradiz a spec: parcial
- Pergunta que levanta: Reaproveitar a tela de Mensagens da rede local dá lista, conversa e anexo prontos, mas ela grava conversa em disco, só aceita imagem e só sabe "entregue / não entregue". Prefere estender essa tela (as duas seções ficam iguais e evoluem juntas, com risco de mexer na LAN) ou fazer a do WhatsApp à parte?
- Evidência: MessagesView.swift:107-108 `if !m.incoming, !m.delivered { Text("não entregue") }`. Knobler/Wire.swift:102-103 `enum MediaKind { case jpeg, png, gif }`. MessageMedia.swift:18 `openTypes = [.jpeg, .png, .gif]`. MessageStore persiste messages.json (MessageStore.swift:27; spec mensagens-lan 105-108). Já existe miniatura de vídeo segura no snapshot: ShelfPreview.swift:177-192 (AVAssetImageGenerator).
- Verificação: se sustenta — Confere: 'não entregue' em MessagesView.swift:107-108, MediaKind jpeg/png/gif (Wire.swift:102-103), openTypes (MessageMedia.swift:18), maxPerPeer = 20 e messages.json (MessageStore.swift:18,27). A miniatura de vídeo por AVAssetImageGenerator está em ShelfPreview.swift:180-189. Sem correção relevante.

#### A14 — A altura da seção Mensagens é fixa (272 pt) e a lista de seções que liberam teclado é literal. Uma seção WhatsApp nova precisa de caso próprio no enum, na altura e na lista de teclado, senão o conteúdo vaza da borda e o campo de envio não recebe tecla.
- Fonte: Knobler/NotchPresentation.swift:51,251
- Contradiz a spec: nao
- Pergunta que levanta: A seção Mensagens tem altura fixa. Pôr seletor de conta, lista de conversas e conversa no mesmo espaço fica apertado. Aceita a mesma altura (rola mais) ou o notch cresce quando o WhatsApp está em foco, cobrindo mais da tela?
- Evidência: Linha 51: `[.nota, .mensagens, .link, .monitores].contains(focus)` libera o teclado. Linha 251: `case .mensagens: return 272`. NotchSectionOrder.swift:14-16 lista as seções. MEMORY: "currentSize ... não se ajusta sozinho... metade sai acima da borda da tela".

#### A15 — O filtro do banner do WhatsApp Desktop tem precedente direto: o AirDrop já é tratado por nome de app dentro do interceptor, com limpeza do U+200E do WhatsApp. Mas o interceptor inteiro só roda com "notificações no notch" ligado, e o nome do app vem de uma heurística que às vezes erra.
- Fonte: Knobler/NotificationInterceptor.swift:100-103,130-154
- Contradiz a spec: parcial
- Pergunta que levanta: Se você desligar "notificações no notch", o Knobler para de engolir o banner do WhatsApp Desktop e você recebe dois avisos por mensagem (banner do Mac e card do Knobler). Aceita isso, ou o filtro do WhatsApp deve valer mesmo com essa opção desligada?
- Evidência: Linha 102: `guard AppSettings.shared.notchNotifications else { return }`. Linhas 150-154: `switch AirDropRegras.faseDoAlerta(appName:...)`. Comentário 130-135: o app "sai de uma heurística... quando ela erra... é o nome de quem mandou a mensagem". NotificationRules.swift:63-66: limpo() pro "‎WhatsApp".
- Verificação: se sustenta — Confere: guard notchNotifications na linha 102, AirDropRegras.faseDoAlerta nas 150-154 e o comentário da heurística nas 130-135. Também exige AXIsProcessTrusted (linha 103): sem Acessibilidade o filtro não roda, e também haveria aviso duplicado.

#### A16 — A ideia registrada de WhatsApp no repo é outra (WhatsApp Web, login headless), e existe regra gravada de que o ditado nunca envia pra app terceiro: WhatsApp só sobrevive como envio a partir do notch. A spec não cita essa regra nem atualiza IDEIAS/ROADMAP.
- Fonte: docs/ROADMAP.md:61-63
- Contradiz a spec: parcial
- Pergunta que levanta: Já está decidido que o ditado só escreve no campo selecionado e nunca manda direto pro WhatsApp. Ou seja, responder por voz só vale ditando no campo do notch e você apertando enviar, sem atalho de "ditar e mandar". Confirma, e a ideia antiga de WhatsApp Web sai do backlog?
- Evidência: ROADMAP.md:61: "WhatsApp Web — se for mais um destino de ditado, está descartado... Só sobrevive como envio a partir do notch, sem tocar o ditado". IDEIAS.md:48: "WhatsApp Web: ... (parse da URL, login headless)". HANDOFF.md:333-338: "o ditado só escreve no campo de texto que a pessoa tem selecionado".
- Verificação: se sustenta — As fontes conferem (ROADMAP.md:61-63, HANDOFF.md:333-338), mas o arquivo é docs/IDEIAS.md:48, não IDEIAS.md na raiz. A spec não propõe o ditado como destino nem 'ditar e mandar': ditar no campo do próprio notch já cabe na regra. Não há contradição, só arrumação de backlog (ROADMAP/IDEIAS desatualizados). 'contradiz' deveria ser 'nao'.

#### A17 — Ações direto no card de notificação estão travadas porque dependem do banner vivo do sistema. Com a ponte, o card do WhatsApp não depende do banner, então botões e resposta no card ficam viáveis, e a infra de botões já existe.
- Fonte: docs/IDEIAS.md:12
- Contradiz a spec: nao
- Pergunta que levanta: Como o card do WhatsApp não depende do banner do Mac, ele pode ter botões (curtir, marcar como lida) além da resposta, sem o problema que trava isso nas outras notificações. Quer botões no card na primeira versão, ou só a resposta?
- Evidência: "acionar a ação exige o AXUIElement do banner vivo... A infra de botão no card já existe (actionTitles/actionToken)". NotchNotification.swift:39-50: actionTitles, actionToken e actionURLs (fora do Codable, linhas 62-70). ROADMAP.md:59.

#### A18 — O ícone da seção Mensagens na faixa não mostra sinal de propósito, porque a LAN não tem "não lida". Com a ponte, as não lidas existem de verdade.
- Fonte: Knobler/NotchView.swift:986-987
- Contradiz a spec: nao
- Pergunta que levanta: Com a ponte o Knobler sabe quantas mensagens não lidas há nas duas contas. Quer esse número no ícone da faixa do notch (útil, mas fica sempre à vista de quem olha sua tela) ou só um ponto discreto?
- Evidência: "mensagens: o sinal seria a contagem de não-lidas, que não existe hoje (o store guarda a conversa, não o 'lido') — melhor nada que inventar."

#### A19 — Já foi decidido que pareamento por chave é burocracia demais pra este app (sync LAN implementado e revertido). A chave da ponte só não esbarra nessa decisão se o usuário nunca precisar copiar nem colar nada.
- Fonte: docs/ROADMAP.md:39-46
- Contradiz a spec: parcial
- Pergunta que levanta: O projeto já descartou exigir chave entre Macs por ser burocracia. A chave da ponte precisa ser 100% automática (você nunca vê nem cola nada), ou aceita colar uma vez nos Ajustes, ao custo de mais um passo de configuração?
- Evidência: "Foi decisão de produto — pareamento por chave é burocracia demais pra este app". IDEIAS.md:81 repete. A spec só diz "chave guardada no Keychain e compartilhada com o Knobler e com o MCP", sem dizer quem a cria.
- Verificação: REFUTADO — A citação confere (ROADMAP.md:39-46, docs/IDEIAS.md:81), mas a conclusão não segue. A decisão foi sobre pareamento entre Macs na LAN, numa feature pública usada sem configurar nada. Aqui é um segredo local, de uma máquina só, numa feature só do dono, cujo setup já é manual (ponte, QR). O próprio repo já aceita segredo local compartilhado entre processos sem atrito para o usuário: o TokenDeAgente (TokenDeAgente.swift:1-16), gerado sozinho e lido de arquivo 0600 por hooks e CLI. Isso não é 'pareamento por chave'. O ponto útil (a spec não diz quem gera a chave) cabe no achado 0.

#### A20 — Escutar só em loopback não protege contra página aberta no navegador. A API local do Knobler já recusa pedidos com Host/Origin/Sec-Fetch-Site de navegador. A ponte em 127.0.0.1 depende só da chave.
- Fonte: Knobler/NotchAPIGuard.swift:5-37
- Contradiz a spec: nao
- Pergunta que levanta: Além da chave, a ponte pode recusar pedidos vindos de navegador, como a API do Knobler já faz. Isso fecha o caso de um site aberto tentar mexer nas suas conversas se a chave vazar. Vale o trabalho extra na ponte?
- Evidência: "uma página aberta no navegador alcança o loopback com 'simple requests' (CSRF) e, com DNS rebinding, até lê as respostas". A lógica é pura e tem teste (tools/apiguardcheck.swift), dá pra portar pra Go.

### Frente: Blast radius no Knobler

#### A21 — Já existe uma seção `.mensagens` (Mensagens LAN entre Macs) com título 'Mensagens', ícone de balões e PluginID `.mensagens`; o WhatsApp precisa de um caso NOVO com rawValue próprio (ex.: `whatsapp`), nunca reaproveitar nem renomear o existente.
- Fonte: Knobler/NotchSectionOrder.swift:14-15,26,48 e Knobler/Plugin.swift:21-23,299-304
- Contradiz a spec: parcial
- Pergunta que levanta: O WhatsApp vira uma seção separada do 'Mensagens' entre Macs (dois ícones parecidos na faixa) ou você quer que as duas coisas morem juntas numa seção só? Separado é mais simples e não mexe no que já funciona; juntar exige reescrever o Mensagens.
- Evidência: `case musica, atividade, pomodoro, shelf, espelho, mensagens, ...` e comentário 'renomear um caso quebra ordem salva de usuário' / 'renomear um caso desinstala a peça'.
- Verificação: se sustenta — Os fatos conferem (NotchSectionOrder.swift:14-15,26,48; Plugin.swift:21-23,299-304). Mas a spec não propõe reaproveitar o Mensagens: ela já fala em 'Seção WhatsApp do notch' e numa peça própria. Então não há contradição, no máximo um detalhe ('nao'/'parcial' fraco). Falta citar também Plugin.swift:394: todo PluginID tem que estar em PluginRegistry.todos. Com isso, um caso novo obriga a ter ficha no registro e um mapeamento secao→NotchSection novo.

#### A22 — Instalação nova do Knobler pelo brew instala TODOS os PluginID.allCases exceto monitores e textoDaTela; um `.whatsapp` novo nasceria instalado em todo Mac novo, contrariando 'quem instala pelo brew não vê nada'. O plugincheck fixa esse conjunto.
- Fonte: Knobler/Plugin.swift:413-416 e tools/plugincheck.swift:124-126
- Contradiz a spec: sim
- Pergunta que levanta: Pra quem instala do zero, a peça do WhatsApp tem que nascer desinstalada (e no seu Mac você instala na mão pela vitrine)? Se nascer instalada, todo Mac novo fica tentando falar com uma ponte que não existe.
- Evidência: `d.set(PluginID.allCases.filter { $0 != .monitores && $0 != .textoDaTela }.map(\.rawValue), forKey: chave)`; check: `ler(d) == Set(PluginID.allCases).subtracting([.monitores, .textoDaTela])`.
- Verificação: se sustenta — Confere (Plugin.swift:413-416; plugincheck.swift:122-129). O que falta dizer: isso só vale pra instalação NOVA. Quem já passou pela migração v1, inclusive o Mac do Luccas, NÃO ganha a peça nova sozinho. Foi por isso que Agentes precisou de um passo próprio (Plugin.swift:419-429). Lá o .whatsapp nasceria desinstalado. Pra nascer desinstalada em Mac novo, a peça entra no filtro junto de .monitores/.textoDaTela, e o plugincheck muda junto.

#### A23 — A vitrine lista todas as peças do registro sem filtro, e o card só tem três estados (Em breve, Instalar, Abrir); não existe mecanismo para esconder uma peça da vitrine conforme algo responder no Mac. Isso é peça nova de infraestrutura, não reuso.
- Fonte: Knobler/PluginsSettingsPane.swift:134 e Knobler/Plugin.swift:451-456,521-524
- Contradiz a spec: sim
- Pergunta que levanta: Vale criar a regra 'peça só aparece na vitrine se a ponte responder' (toda instalação passa a sondar a porta 8099 do Mac), ou basta a peça aparecer sempre com um aviso 'precisa da ponte'? A primeira esconde de verdade; a segunda é mais barata e não sonda ninguém.
- Evidência: `ForEach(PluginRegistry.todos, id: \.id) { peca in CardPeca(...) }`; `enum EstadoDoCard { case emBreve, abrir, instalar }`.
- Verificação: se sustenta — Confere (PluginsSettingsPane.swift:133-134 e o enum EstadoDoCard em Plugin.swift:451-456; estadoDoCard em 521-524). Tem mais um detalhe: Plugin.swift:394 exige que todo PluginID esteja em todos. Então esconder a peça tem que ser um filtro na vitrine, não tirá-la do registro.

#### A24 — A sondagem 'a ponte responde' em 127.0.0.1:8099 vai rodar no Mac de todo usuário do brew; qualquer outro serviço local na 8099 daria falso positivo se a checagem for só 'a porta abriu'.
- Fonte: Knobler/Plugin.swift:521-524 (vitrine decide só por pronta/instalado) e docs/vesta/specs/2026-11-04-whatsapp-design.md:17-18,88-89
- Contradiz a spec: parcial
- Pergunta que levanta: A ponte deve se identificar (rota própria que diz 'sou a ponte do WhatsApp') pra o Knobler não confundir com outro programa na mesma porta? Sem isso, alguém com outro serviço na 8099 veria a peça aparecer quebrada.
- Evidência: Spec: 'Só aparece na vitrine quando a ponte responde no Mac.' Nenhum código hoje distingue quem atende numa porta local.
- Verificação: se sustenta — É um risco de desenho, não um defeito que já existe. Confirmado que a ponte hoje não tem rota que a identifique: ~/Code/whatsapp-mcp/whatsapp-bridge/main.go:900-1066 só tem /api/send, group/*, history, mediaretry e download, na porta 8099 (main.go:1251). O falso positivo só acontece se a sondagem se contentar com 'porta abriu'. A rota autenticada que a spec já prevê (recusa sem chave) também resolve, se a sondagem exigir resposta válida.

#### A25 — Seção nova entra no fim da ordem salva de quem já personalizou: `sanear` completa o que falta com `padrao` filtrado, então no seu Mac o WhatsApp cai depois de Cor, não onde ficar em `padrao`.
- Fonte: Knobler/NotchSectionOrder.swift:191-197 e Knobler/AppSettings.swift:183-201
- Contradiz a spec: parcial
- Pergunta que levanta: Onde o WhatsApp deve ficar na faixa de ícones? Se não fizer nada, ele aparece por último até você arrastar; dá pra forçar uma posição uma vez só, mas isso mexe na ordem que você já escolheu.
- Evidência: `return vistas + padrao.filter { !vistas.contains($0) }`.
- Verificação: se sustenta — O mecanismo confere (NotchSectionOrder.swift:191-197). O detalhe está errado: a ordem salva no Mac do Luccas (defaults notchSectionOrder) termina em '..., monitores, cor, historico'. O WhatsApp cairia depois de Histórico, não depois de Cor. Também vale lembrar que a promoção por evento reordena a faixa na abertura (AppSettings.swift:181-182), então a seção sobe quando chega mensagem.

#### A26 — A lista de Ações rápidas nos Ajustes usa `NotchSection.allCases` sem filtrar peças desinstaladas: a seção WhatsApp apareceria como atalho marcável para todo usuário do brew, mesmo sem a peça.
- Fonte: Knobler/SettingsView.swift:427
- Contradiz a spec: sim
- Pergunta que levanta: Topa corrigir de quebra a lista de atalhos dos Ajustes pra esconder seção de peça não instalada? Sem isso, o WhatsApp vaza como opção pra quem nunca vai ter a ponte.
- Evidência: `let linhas = marcados + NotchSection.allCases.filter { $0 != .acoesRapidas && !marcados.contains($0) }` (a faixa em si usa `atalhosVisiveis(..., desinstaladas:)` em AcoesRapidasView.swift:9).
- Verificação: se sustenta — Confere (SettingsView.swift:427). Nem o ForEach nem o Toggle filtram, enquanto a faixa (AcoesRapidasView.swift:9-10) e o editor de ordem (SettingsView.swift:333) usam desinstaladas(). É um bug que já existe hoje para Monitores e para qualquer outra peça desinstalada, não só para o WhatsApp.

#### A27 — A altura do card não vem mais de um ramo `vm.tab == .messages` no `currentSize`: hoje é `NotchMetrics.alturaDaSecao` (switch exaustivo, Mensagens = 272) com overrides por seção dentro de `NotchView.presentation` (agenda, lembretes e monitores limitam pela altura da tela). Caso novo quebra a compilação ali, e a largura padrão é 430.
- Fonte: Knobler/NotchPresentation.swift:234-265 e Knobler/NotchView.swift:49-75
- Contradiz a spec: parcial
- Pergunta que levanta: A conversa do WhatsApp cabe em 430 de largura por ~270 de altura como o Mensagens, ou você quer um card maior (tipo o Link, que abre a 780)? Maior mostra foto e áudio direito; mas o card fica mais alto que a tela pequena aguenta sem limitar pela tela.
- Evidência: `case .mensagens: return 272`; `if vm.focus == .lembretesApple { layout.sectionHeight = min(330, max(0, vm.availableSize.height - vm.notchSize.height - 84)) }`; `larguraDoCard(... padrao: 430 ...)`.
- Verificação: se sustenta — O código confere (NotchPresentation.swift:234-265, mensagens = 272, linkCardWidth = 780 na linha 209; NotchView.swift:49-75, padrão de 430). Duas imprecisões. Quem cita 'vm.tab == .messages' é a MEMORY.md, não a spec, então a contradição é com a memória desatualizada e não com a spec, que nem fala de altura. E Monitores não limita pela altura da tela: soma pelo conteúdo (NotchView.swift:66-72). Só agenda e lembretes limitam pela tela.

#### A28 — Campo de texto numa seção só recebe teclado se a seção estiver na lista fixa de `keyboard`; o WhatsApp precisa entrar ali, senão o compositor nunca pega foco.
- Fonte: Knobler/NotchPresentation.swift:51
- Contradiz a spec: nao
- Pergunta que levanta: Nenhuma decisão sua aqui: é item obrigatório do plano (sem ele, nada que você digitar chega ao campo de resposta).
- Evidência: `case .music: return expanded && (pelaTecla || [.nota, .mensagens, .link, .monitores].contains(focus) || editingAgenda || editingReminders)`.

#### A29 — Digitar numa seção de mensagens NÃO protege contra notificação: `protegeEdicao` só cobre nota, agenda e lembretes, e `.notification` vence o card aberto. Uma notificação qualquer (inclusive um card do próprio WhatsApp) tira o compositor da tela e o teclado cai pro app da frente.
- Fonte: Knobler/NotchViewModel.swift:145,680 e Knobler/NotchPresentation.swift:37,42
- Contradiz a spec: sim
- Pergunta que levanta: Enquanto você digita uma resposta no WhatsApp do notch, os outros avisos devem esperar na fila (como acontece na nota rápida)? Sem isso, chega um aviso no meio da frase e o resto do que você digita vai parar em outro app.
- Evidência: `private var protegeEdicao: Bool { typingNote || editandoAgenda || editandoLembretes }`; mode: `if notification { return .notification }` vem antes de `if expanded { return .music }`.
- Verificação: se sustenta — Confere: protegeEdicao está em NotchViewModel.swift:145, o uso em 680, e .notification na linha 37 vem antes de .expanded na 42 (NotchPresentation.swift). O compositor do Mensagens LAN que já existe tem a mesma falha. A causa é estrutural, não exclusiva do WhatsApp.

#### A30 — O card de mensagem recebida (`incoming`) vence o card aberto na prioridade de modo e é um slot único sem fila: mensagem nova substitui a anterior, e se você estiver na conversa aberta o card de outra conversa esconde a conversa.
- Fonte: Knobler/NotchPresentation.swift:34 e Knobler/NotchViewModel.swift:258,603-607
- Contradiz a spec: sim
- Pergunta que levanta: Com duas contas e grupos chegando em rajada, você prefere fila de cards (vê um por um), card agrupado ('3 mensagens novas') ou só o último? E com a conversa aberta no notch, mensagem de outra conversa deve virar só um contador em vez de cobrir a tela?
- Evidência: `if incoming { return .message }` antes de `if expanded`; `func showIncoming(_ m:) { incoming = m ... }` sem fila.
- Verificação: se sustenta — Confere (NotchPresentation.swift:34; NotchViewModel.swift:258 e 603-607). O card de chegada é slot único, sem fila, e a mensagem nova substitui a anterior. O card também tem auto-dismiss próprio (scheduleIncomingDismiss) e hoje é mostrado em todas as telas (KnoblerApp.swift:534-539). Não existe supressão quando a conversa está aberta.

#### A31 — O rascunho do compositor e da resposta rápida vive em `@State` da view; quando a view sai da árvore (card fechou, notificação/HUD/ditado entrou, outra mensagem substituiu o card), o texto digitado some. Só o anexo pendente foi movido pro VM por esse motivo.
- Fonte: Knobler/MessagesView.swift:17 e Knobler/IncomingMessageView.swift:17 e Knobler/NotchViewModel.swift:259-262
- Contradiz a spec: parcial
- Pergunta que levanta: Rascunho deve sobreviver ao notch fechar e a uma notificação passar por cima (e por conversa, como no WhatsApp de verdade)? Guardar por conversa evita perder texto, mas é estado a mais pra manter.
- Evidência: `@State private var draft = ""`; `@State private var reply = ""`; comentário do `PendingAttachment`: 'o notch fecha e a view morreria levando a escolha junto'.
- Verificação: se sustenta — Confere (MessagesView.swift:17, IncomingMessageView.swift:17, o comentário do PendingAttachment em NotchViewModel.swift:259-262).

#### A32 — A estrutura do card de chegada e a abertura de conversa são específicas da LAN: `IncomingMessage` tem só `peerID`, `onSendReply` manda (peerID, texto) e `openThread` força foco em `.mensagens`. Card do WhatsApp precisa de conta, conversa e grupo; reaproveitar exige generalizar isso.
- Fonte: Knobler/NotchViewModel.swift:247-271,638-643
- Contradiz a spec: parcial
- Pergunta que levanta: O card de chegada do WhatsApp reaproveita o card de mensagem LAN (mesmo visual, menos código novo, mas mexe no que já funciona) ou ganha card próprio?
- Evidência: `struct IncomingMessage { let peerID: String; let name: String; let text: String; let allowReply: Bool ... }`; `func openThread(peerID:) { ... pedirFoco(.mensagens) }`.
- Verificação: se sustenta — Confere (NotchViewModel.swift:247-271, 638-643). IncomingMessage também carrega mediaFile, que é um nome de arquivo no MessageStore LAN, e o IncomingMessageView depende de @EnvironmentObject MessageStore. Generalizar mexe nessa dependência também.

#### A33 — Card montado dentro do laço por tela ganha um id diferente por monitor e fura dedupe e histórico; o padrão estabelecido é montar uma vez fora do laço e espalhar.
- Fonte: Knobler/KnoblerApp.swift:445-452,1727-1733
- Contradiz a spec: nao
- Pergunta que levanta: Nenhuma decisão sua aqui: é regra do plano (com dois monitores, sem isso cada mensagem aparece duplicada no histórico).
- Evidência: Comentário: 'uma notificação só, montada FORA do laço: o id é um UUID novo a cada init, então uma por tela viraria N linhas no histórico'; `publicar` faz `notches.values.forEach { $0.viewModel.enqueue(notification) }`.

#### A34 — A conversa selecionada é estado por tela (`selectedThreadPeerID` em cada NotchViewModel), então 'a conversa não está aberta na frente do usuário' tem de ser decidido por monitor.
- Fonte: Knobler/NotchViewModel.swift:263-267
- Contradiz a spec: parcial
- Pergunta que levanta: Se a conversa está aberta no notch de um monitor, o card dessa mesma conversa ainda desce no outro monitor? Suprimir em todos evita repetição; suprimir só onde está aberta garante que você vê onde estiver olhando.
- Evidência: `@Published var selectedThreadPeerID: String?` — um por VM, e há um VM por display (AppDelegate cria NotchWindow/NotchViewModel por tela).
- Verificação: se sustenta — Confere (NotchViewModel.swift:263-267; um VM por tela, como diz o CLAUDE.md). Hoje o card LAN não suprime nada mesmo com a conversa aberta, e desce em todas as telas (KnoblerApp.swift:534).

#### A35 — Passar o card do WhatsApp por `enqueue`/`publicar` grava o corpo da mensagem no Histórico, que persiste em claro em Application Support; o caminho do card LAN (`showIncoming`) não grava histórico e também ignora o silêncio de reunião/microfone.
- Fonte: Knobler/NotificationHistory.swift:16,23,67 e Knobler/KnoblerApp.swift:1727-1745 e Knobler/NotchViewModel.swift:603-607
- Contradiz a spec: sim
- Pergunta que levanta: Mensagem de WhatsApp deve entrar no Histórico do notch (fica salva em disco no Mac) e respeitar o 'silenciar em reunião'? A spec diz que o Knobler não guarda conversa em disco; entrar no histórico quebra isso, ficar fora dele faz o card tocar em reunião.
- Evidência: 'Os corpos das notificações passam a ficar em claro em Application Support'; `guard silenciando else { enqueue }; NotificationHistory.shared.record(notification)`.
- Verificação: se sustenta — Confere: enqueue grava no histórico logo na entrada (NotchViewModel.swift:664), publicar só manda pro histórico quando está silenciando (KnoblerApp.swift:1727-1745) e showIncoming não grava nem respeita silêncio. Um detalhe que muda o peso: hoje os banners do WhatsApp Desktop já passam por interceptor→publicar→enqueue (KnoblerApp.swift:256-257). Então os corpos de mensagens do WhatsApp JÁ vão em claro pro histórico (24 h). A spec não piora isso se o card da ponte ficar fora do histórico.

#### A36 — Hoje o interceptor não filtra por app: todo banner sem botão é fechado e vira card. O filtro do WhatsApp Desktop tem que entrar depois do `close(banner)` e antes do `onNotification`, e a decisão precisa morar em NotificationRules (puro, testável); o nome do app só sai de heurística sobre o texto e já é limpo do U+200E.
- Fonte: Knobler/NotificationInterceptor.swift:121-185 e Knobler/NotificationRules.swift:63-80
- Contradiz a spec: parcial
- Pergunta que levanta: Com a ponte de pé, o banner do WhatsApp Desktop deve sumir calado (nem card, nem histórico)? E se a ponte estiver com só uma das contas conectada, os banners continuam sumindo mesmo sem saber de qual conta vieram?
- Evidência: `if buttons.isEmpty { close(banner) }` seguido de `onNotification(NotchNotification(appName: parsed.appName, ...))`; `limpo()` remove 0x200E 'sem isso "‎WhatsApp" nunca casa'; `appName(fromDescription:)` pega o 1º trecho antes de ', '.
- Verificação: se sustenta — Confere (NotificationInterceptor.swift:121-185; NotificationRules.swift:63-80). É imprecisa a parte de que o filtro 'tem que' entrar entre close e onNotification: também pode morar no closure do AppDelegate (KnoblerApp.swift:256-257), antes de publicar, porque o banner sem botão já é fechado de qualquer forma. Banner com botões não é fechado, e se for descartado ficaria duplicado na tela do sistema.

#### A37 — NotificationRules.swift é compilado por outros harness (sharingcheck) e pela lista da NotchView; a regra do filtro tem que ficar Foundation-pura e não pode puxar o estado do WhatsApp para dentro desse arquivo.
- Fonte: tools/check.sh:114 e tools/notchview-fontes.txt:44
- Contradiz a spec: nao
- Pergunta que levanta: Nenhuma decisão sua aqui: é restrição do plano (entra o estado 'ponte conectada' por parâmetro, senão quebra outros testes).
- Evidência: `swift_check sharingcheck Knobler/Sharing.swift ... Knobler/NotificationRules.swift tools/sharingcheck.swift`.

#### A38 — A chave guardada no Keychain e gravada pela ponte (ou pelo `security`) fica ilegível para o Knobler: a leitura desliga interação e a ACL é de quem gravou, então o app vê o item existir mas não abre (estado 'trancado'). Já existe precedente de segredo compartilhado com processos locais por arquivo 0600.
- Fonte: Knobler/WebhookKeychainStore.swift:28-55,95-116 e Knobler/TokenDeAgente.swift:5-15
- Contradiz a spec: sim
- Pergunta que levanta: A chave da ponte pode ficar num arquivo protegido só pro seu usuário (como o token dos agentes) em vez do Keychain? Keychain compartilhado entre o Knobler, a ponte em Go e o MCP em Python vai dar 'chave não confere' ou pedir senha toda hora.
- Evidência: `SecKeychainSetUserInteractionAllowed(false)`; 'A ACL destes itens confia no requisito de assinatura de quem os gravou'; TokenDeAgente: 'num arquivo que os adaptadores locais leem', pasta 0700 / arquivo 0600.
- Verificação: se sustenta — Confere (WebhookKeychainStore.swift:28-55, 95-116; TokenDeAgente.swift:5-15 e a gravação 0700/0600). A MEMORY.md reproduziu o estado 'trancado' gravando pelo `security`. Dá pra criar o item com a lista de apps confiáveis (-T), mas essa lista se baseia em assinatura e quebra quando a assinatura muda. O precedente em arquivo 0600 é o caminho já usado no projeto.

#### A39 — HTTP para o loopback já funciona sem chave ATS nem entitlement: o app não é sandbox, não tem .entitlements, hardened runtime desligado, e o TranscriptFormatter já chama http://localhost:11434. Loopback também não dispara o pedido de Rede Local.
- Fonte: project.yml:83 e Knobler/TranscriptFormatter.swift:16 e Knobler/Info.plist:39-40
- Contradiz a spec: nao
- Pergunta que levanta: Nenhuma decisão sua aqui: falar com a ponte local não pede permissão nova ao sistema.
- Evidência: `ENABLE_HARDENED_RUNTIME: "NO"`; nenhum `*.entitlements` em Knobler/; `endpoint ex: http://localhost:11434/v1/chat/completions`; Info.plist sem NSAppTransportSecurity.

#### A40 — O cliente de rede com reconexão que já existe (WebhookClient) usa timeout de requisição de 30 s; copiado para o canal ao vivo, derruba a conexão a cada 30 s de silêncio se a ponte não mandar batimento.
- Fonte: Knobler/WebhookClient.swift:53-58
- Contradiz a spec: parcial
- Pergunta que levanta: A ponte manda um 'sinal de vida' a cada poucos segundos no canal ao vivo? Sem isso o Knobler fica reconectando sozinho de madrugada e pode atrasar o card além dos 2 segundos.
- Evidência: `c.waitsForConnectivity = true; c.timeoutIntervalForRequest = 30` — o código não tem precedente de SSE (nenhum `text/event-stream`/`bytes(for:)` em Knobler/).
- Verificação: se sustenta — Impreciso. O WebhookClient é WebSocket, não SSE, e manda ping a cada 25 s com pong de 10 s (WebhookClient.swift:65-67). Por isso o timeout de 30 s nunca derruba a conexão. O risco existe só se alguém copiar a configuração pra um canal SSE sem batimento do servidor, ou sem subir timeoutIntervalForRequest. Também vale registrar que o cliente com reconexão que já existe é WebSocket, e a spec escolheu SSE: não há precedente de SSE no código.

#### A41 — Gravar áudio de voz por mais de 20 s liga o 'silenciar com microfone' do próprio Knobler (ele não desconta o próprio microfone) e passa a engolir cards; a descrição de uso do microfone no Info.plist fala só de ditado.
- Fonte: Knobler/KnoblerApp.swift:1735-1746,368-375 e Knobler/NotificationRules.swift:43-51 e Knobler/Info.plist:41-42
- Contradiz a spec: parcial
- Pergunta que levanta: Durante uma gravação de áudio longa no notch, os avisos podem ir calados pro histórico como numa ligação, ou o Knobler deve ignorar o próprio microfone? E tudo bem o texto de permissão continuar dizendo só 'ditado'?
- Evidência: 'o ditado do próprio Knobler também acende o microfone, e não há código aqui pra descontar isso — ele dura segundos'; `micIndicaChamada(... limiar: TimeInterval = 20)`; NSMicrophoneUsageDescription: 'grava sua voz enquanto você segura a tecla de ditado'.
- Verificação: se sustenta — O mecanismo confere (KnoblerApp.swift:1735-1746 e 368-375; NotificationRules.swift:43-51; Info.plist:41-42). Faltam duas ressalvas. 'Silenciar com microfone' vem desligado por padrão (AppSettings.swift:321, defaults.bool), e o card silenciado vai pro Histórico, não some. E isso só afeta o que passa por publicar: banner interceptado, API e webhook. Um card da ponte que use outro caminho nem passa por esse gate.

#### A42 — Ditar com a tecla do Knobler no compositor do notch não funciona hoje: o ditado vence o card aberto (pílula toma o lugar), e o texto é colado com Cmd+V no app da frente; só o Ask tem destino interno.
- Fonte: Knobler/NotchPresentation.swift:35,42 e Knobler/KnoblerApp.swift:588-600 e Knobler/Dictation.swift:664-672
- Contradiz a spec: parcial
- Pergunta que levanta: Você quer ditar respostas do WhatsApp direto no notch? Dá pra fazer igual ao Ask (o texto cai no campo certo), mas é trabalho a mais; sem isso o ditado cola no app que estiver por trás.
- Evidência: `if dictation { return .dictation }` antes de `if expanded`; `destinationProvider`: `.ask(id:)` ou `.application(pid: frontmostApplication)`; `postCommandV()`.
- Verificação: se sustenta — Confere (NotchPresentation.swift:35 antes de 42; destinationProvider em KnoblerApp.swift:588-600; postCommandV em Dictation.swift:664-672). Além disso, quando o ditado entra o card sai da árvore e o foco do campo cai, e é por isso que o Cmd+V vai pro app da frente.

#### A43 — Se a seção nova tiver 'tem conteúdo' (conversas, não lidas), ela precisa de campo em NotchSectionInputs, entrada no mapa de `estadoDasSecoes` (o default silencioso é false) e no `membershipChanged`, senão não aparece nem atualiza com o card aberto.
- Fonte: Knobler/NotchViewModel.swift:46-63,290-319 e Knobler/NotchPresentation.swift:268-277
- Contradiz a spec: nao
- Pergunta que levanta: A seção WhatsApp aparece sempre na faixa (como Agenda) ou só quando há conversa/não lida? Sempre é previsível; só com novidade deixa a faixa limpa mas o ícone some quando tudo foi lido.
- Evidência: `hasContent: conteudo[$0] ?? false`; `membershipChanged = inputs.note != ... || inputs.messages != ... || inputs.link != ... || inputs.agentes != ...`.

#### A44 — Mexer em Plugin.swift (ficha, PluginDeps, efeitos) arrasta três harness com lista fixa de arquivos (plugincheck, quicknotecheck, novidadescheck), e mexer no VM arrasta o eventoscheck; o plugincheck também fixa a lista literal de peças prontas.
- Fonte: tools/check.sh:105-111,145-151,156-165,173-182 e tools/plugincheck.swift:369-372
- Contradiz a spec: nao
- Pergunta que levanta: Nenhuma decisão sua aqui: custo do plano (cada tipo do WhatsApp citado na ficha entra em quatro listas de teste).
- Evidência: `assert(PluginRegistry.todos.filter(\.pronta).map(\.id) == [.monitores, ..., .agentes, .textoDaTela])`; `struct PluginDeps { ... var textoDaTela = TextoDaTelaEfeitos() }` em Plugin.swift:208-223.

#### A45 — O par 'objeto ocioso + environmentObject' usado pela peça Mensagens tem teto declarado ('se uma 3ª peça precisar do mesmo truque, extrair wrapper') e o environmentObject captura o objeto na criação da janela; o precedente que evita isso é singleton `.shared` conformando PluginServico (Nota rápida, Preview de Link).
- Fonte: Knobler/KnoblerApp.swift:104-113,246-252,640-650
- Contradiz a spec: nao
- Pergunta que levanta: Nenhuma decisão sua aqui: confirma que o estado do WhatsApp como objeto único compartilhado é o caminho certo; desligar a peça precisa só parar a conexão, não destruir o objeto.
- Evidência: 'Teto: se uma 3ª peça precisar do mesmo truque, vale extrair um wrapper genérico'; `plugins.notaRapidaEfeitos = NotaRapidaEfeitos(nascer: { QuickNote.shared })`.

#### A46 — O harness de snapshot compila o código real e zera cada singleton à mão entre cenários; o estado do WhatsApp precisa de reset ali e de um modo sem rede, senão o harness, rodando nesta máquina onde a ponte está de pé na 8099, puxa conversas reais para os PNGs.
- Fonte: tools/main.swift:803-844 e tools/notchview-fontes.txt:1-3
- Contradiz a spec: parcial
- Pergunta que levanta: Tudo bem o estado do WhatsApp ter um modo 'de mentira' só pra teste, com conversas inventadas? Sem isso, rodar os snapshots no seu Mac fotografa suas conversas de verdade.
- Evidência: `NotificationHistory.shared.prune(...)`, `QuickNote.shared.active = false`, `Monitores.shared.displays = []` no laço; fontes da NotchView em lista MANUAL lida por snapshot.sh e cortecheck.sh.
- Verificação: se sustenta — Confere (tools/main.swift:803-844, resets manuais de singletons; notchview-fontes.txt:1-3, lista manual). A parte de 'puxa conversas reais' só vale se o singleton do WhatsApp abrir conexão sozinho ao nascer. É um requisito de desenho (injetar transporte falso ou ficar inerte até start), não um fato do código atual.

#### A47 — O harness já captura ScrollView fora do app: cenários com prefixo agenda-/lembretes-/monitores- renderizam numa janela sintética (NSHostingView + cacheDisplay), e o agenda-criar ainda testa digitação real no campo. A spec diz que lista e conversa só podem ser conferidas no app real.
- Fonte: tools/main.swift:890-930
- Contradiz a spec: sim
- Pergunta que levanta: Quer que a lista de conversas e a conversa aberta entrem no teste automático de imagens (pelo mesmo caminho da Agenda), em vez de depender de você olhar no app? Custa um cenário a mais, mas pega quebra visual sem você abrir nada.
- Evidência: `if scenario.name.hasPrefix("agenda-") || ... { // ScrollView usa backing AppKit e sai preta no ImageRenderer. Uma janela sintética permite capturar a lista real }`.
- Verificação: se sustenta — Confere (tools/main.swift:890-930): cenários com prefixo agenda-/lembretes-/monitores- são capturados por janela sintética com NSHostingView + cacheDisplay, e agenda-criar testa teclado. A spec (linhas 130-131) está errada ao dizer que ScrollView só pode ser conferido no app real. Ressalva: esse caminho precisa de sessão gráfica desbloqueada (há checagem telaBloqueada).

#### A48 — Release MINOR exige página de Novidades e entrada no catálogo; uma feature que não aparece pra quem instala pelo brew ainda teria de ser anunciada na página pública, ou sair como PATCH contrariando 'MINOR = feature'.
- Fonte: tools/release.sh:80-91 e CLAUDE.md (Versionamento)
- Contradiz a spec: parcial
- Pergunta que levanta: Como essa feature sai no versionamento: versão nova com página de novidades (todo mundo lê sobre algo que não pode usar) ou entra calada numa correção? A primeira segue a regra do projeto; a segunda evita confusão pros usuários.
- Evidência: 'release MINOR/MAJOR sem página de novidades: crie $NOVIDADE e acrescente "$VER" a NovidadesCatalogo.versoes'.
- Verificação: se sustenta — Confere (tools/release.sh:80-91). A página de Novidades é HTML embarcado no app (Knobler/Novidades/<versão>.html + NovidadesCatalogo), não uma 'página pública'. O dilema também não é obrigatório: a mudança pode sair numa MINOR que traga outra feature pública e não citar o WhatsApp na página.

### Frente: A ponte (whatsapp-mcp)

#### A49 — A ponte abre uma conta só: pega o primeiro aparelho do cofre e cria um cliente único; nada no código suporta duas sessões.
- Fonte: /Users/luccassilveira/Code/whatsapp-mcp/whatsapp-bridge/main.go:1149
- Contradiz a spec: nao
- Pergunta que levanta: Pra ter as duas contas, a ponte precisa ser reestruturada por dentro (um cliente por conta). Aceita que a primeira entrega seja só essa reforma, com o 4143 seguindo igual e o 8292 entrando depois do QR?
- Evidência: deviceStore, err := container.GetFirstDevice(...); client := whatsmeow.NewClient(deviceStore, logger). O whatsmeow da versão fixada já tem GetAllDevices/GetDevice(jid) (store/sqlstore/container.go:157,182). GetFirstDevice devolve devices[0] sem ORDER BY, e o ramo sql.ErrNoRows em main.go:1151 nunca roda, porque a função já devolve NewDevice() quando o cofre está vazio (container.go:170-171). Se o 8292 entrar no mesmo whatsapp.db sem escolher o 4143 pelo JID, o MCP pode passar a falar pela conta errada.

#### A50 — Versão do whatsmeow: pseudo-versão de 15/09/2026, que já traz tudo o que a spec pede (reação, edição, apagar, marcar como lida, foto de perfil, pareamento por código).
- Fonte: /Users/luccassilveira/Code/whatsapp-mcp/whatsapp-bridge/go.mod:7
- Contradiz a spec: nao
- Pergunta que levanta: A biblioteca já tem tudo, sem precisar atualizar. Quer manter a versão travada durante a feature, pra não misturar atualização com mudança grande?
- Evidência: go.mau.fi/whatsmeow v0.0.0-20260915134308-320ff7ebf928; no cache: BuildReaction send.go:541, BuildEdit :606, BuildRevoke :526, MarkRead receipt.go:195, GetProfilePictureInfo user.go:548, PairPhone pair-code.go:92. go 1.26.0, go-sqlite3 v1.14.49, qrterminal v1.0.1.

#### A51 — O messages.db não tem conta em lugar nenhum: chats tem PK só por jid e messages tem PK (id, chat_jid). Grupo que as duas contas dividem colide e uma conta sobrescreve a outra.
- Fonte: /Users/luccassilveira/Code/whatsapp-mcp/whatsapp-bridge/main.go:68-90
- Contradiz a spec: parcial
- Pergunta que levanta: O grupo COISAS (criado pelo 8292, com o 4143 dentro) e qualquer grupo em comum vão ter a mesma mensagem gravada duas vezes. Prefere que a mensagem tenha conta como parte da chave (cada conta vê a sua cópia, com 'enviada por mim' certo) ou uma linha só compartilhada (economiza espaço, mas perde quem mandou de qual conta)?
- Evidência: chats(jid PK, name, last_message_time); messages(id, chat_jid, ..., PRIMARY KEY (id, chat_jid)). Com INSERT OR REPLACE (main.go:108, :123), a segunda conta grava por cima e inverte is_from_me. Só o índice automático da PK existe, e ele não serve pra 'mensagens de um chat por data'. Grupo 554792508292-1575256960@g.us = 'COISAS' em chats. Hoje são 18.984 mensagens e 963 chats.
- Verificação: se sustenta — Confere: main.go:68-90 tem chats(jid PK) e messages PK (id, chat_jid), sem coluna de conta; os INSERT OR REPLACE ficam em :108 e :123. O banco só tem os índices automáticos das PKs. O jid 554792508292-1575256960@g.us é 'COISAS'. A spec (linhas 46-47) só fala em 'marca da conta' em cada mensagem. Uma coluna nova sem mudar a PK não evita a colisão, então o 'parcial' se sustenta. As contagens cresceram para 18.986 mensagens (963 chats).

#### A52 — O MCP do Claude lê o messages.db e o whatsapp.db direto por SQL e faz JOIN messages↔chats por jid. Coluna nova não quebra (as consultas nomeiam colunas), mas mudar a PK de chats para (conta, jid) duplica linhas no JOIN e mistura as contas.
- Fonte: /Users/luccassilveira/Code/whatsapp-mcp/whatsapp-mcp-server/whatsapp.py:144-145
- Contradiz a spec: parcial
- Pergunta que levanta: Quando o 8292 entrar, o Claude passa a ver as conversas pessoais misturadas com as do Business se o MCP não filtrar por conta. Quer que o MCP enxergue só o 4143 (como hoje) ou as duas contas com a marca de qual é qual?
- Evidência: whatsapp.py:11-12 aponta para ../whatsapp-bridge/store/{whatsapp,messages}.db; JOIN chats ON messages.chat_jid = chats.jid em :145, :242, :265, :288, :347, :472, :519, :570, :614; nenhum SELECT *. search_contacts lê whatsmeow_contacts sem filtrar our_jid (:415) e whatsmeow_lid_map (:413). Tools: search_contacts, list_messages, list_chats, get_chat, get_direct_chat_by_contact, get_contact_chats, get_last_interaction, get_message_context, send_message, add_group_participant, send_file, send_audio_message, request_history, download_media (main.py:23-265). O MCP está registrado no escopo de usuário em ~/.claude.json (uv --directory .../whatsapp-mcp-server run main.py).
- Verificação: se sustenta — Confere: whatsapp.py:11-12 aponta para os .db da ponte e os JOINs por jid estão em :145, 242, 265, 288, 347, 472, 519, 570 e 614, sem nenhum SELECT *. A spec (linhas 47-48 e 122-123) supõe que um padrão 'sem parâmetro de conta vale o 4143' nas rotas protege o MCP. Só que o MCP lê o SQLite direto, não as rotas, então esse padrão não o protege. Detalhe: quem filtra contato por conta em whatsmeow_contacts é a coluna our_jid, que o MCP não usa (:413-415).

#### A53 — O banco também é consultado à mão por sqlite3 (prática registrada na memória), além do MCP e da própria ponte.
- Fonte: /Users/luccassilveira/.claude/memory/tools/whatsapp.md:5
- Contradiz a spec: nao
- Pergunta que levanta: As consultas diretas que o Claude faz no banco (achar grupo, resolver número escondido) vão passar a trazer as duas contas juntas. Tudo bem precisar dizer qual conta toda vez?
- Evidência: Memória 2026-09-22 e 2026-09-29: 'Resolva direto no SQLite: whatsapp.db tabela whatsmeow_lid_map ... messages.db pelo chat_jid' e 'sqlite3 messages.db "select jid,name from chats where jid like '%@g.us'..."'. No momento, lsof mostra só a ponte (pid 968) com o messages.db aberto.

#### A54 — Reação, edição, apagar, figurinha, botão/lista/template e mensagens sem texto nem mídia são descartadas antes de salvar. Citação (ContextInfo) é ignorada e não tem coluna.
- Fonte: /Users/luccassilveira/Code/whatsapp-mcp/whatsapp-bridge/main.go:490-494
- Contradiz a spec: parcial
- Pergunta que levanta: Reação, edição, apagada e citação não existem no banco hoje. O que já passou ficou perdido (só volta pedindo o histórico ao celular). Aceita que o notch mostre essas coisas só daqui pra frente?
- Evidência: if content == "" && mediaType == "" { Skipped ... }. extractTextContent (215-242) só lê conversation/extendedText.Text/captions/vCard; extractMediaInfo (432-467) só image/video/audio/document, sem sticker. grep sem resultado para ContextInfo|StanzaID|Reaction|Sticker|Revoke|IsEdit|ProtocolMessage no main.go. Contagem no log (~/Library/Logs/whatsapp-bridge.log, 396 descartes): senderKeyDistribution 245, protocolMessage (edição/apagar) 36, stickerMessage 34, reactionMessage 32, buttons 13, template 12, secretEncrypted 10, albumMessage 2.
- Verificação: se sustenta — Confere: main.go:490-494 descarta mensagem sem texto e sem mídia. extractTextContent (215-242) e extractMediaInfo (432-467) não tratam sticker, reação, protocolMessage nem citação, e não há ContextInfo/Reaction/Sticker/Revoke no main.go. O unwrapMessage (182-200) só desembrulha FutureProofMessage, então a edição continua caindo como protocolMessage. As contagens do log batem (396 descartes), mas são por campo presente: a mesma mensagem pode contar em mais de um, e senderKeyDistribution não é conteúdo do usuário. A spec (linha 7) pede reações e citação.

#### A55 — Os eventos tratados são só Message, HistorySync, MediaRetry, Connected (só log) e LoggedOut (só log). Não tem Receipt, presença, foto de perfil nem reconexão por conta.
- Fonte: /Users/luccassilveira/Code/whatsapp-mcp/whatsapp-bridge/main.go:1177-1196
- Contradiz a spec: nao
- Pergunta que levanta: Os tiques de entregue e lido são novos pra ponte: hoje ela não guarda nem repassa recibo. Quer o 'lido' também nos grupos (lido por cada pessoa, mais dados e ruído) ou só nas conversas individuais?
- Evidência: switch: *events.Message → handleMessage; *events.HistorySync → handleHistorySync; *events.MediaRetry; *events.Connected → logger.Infof; *events.LoggedOut → logger.Warnf("... scan QR code ..."). Sem *events.Receipt. events.Receipt existe na lib (types/events/events.go:443) com MessageIDs/Type/MessageSender.

#### A56 — Ao ser deslogada, a ponte só escreve no log e segue de pé sem conexão. O servidor HTTP só sobe depois do pareamento, e o QR sai em ASCII no log. Hoje não dá pra parear pelo HTTP sem reestruturar a inicialização.
- Fonte: /Users/luccassilveira/Code/whatsapp-mcp/whatsapp-bridge/main.go:1202-1257
- Contradiz a spec: parcial
- Pergunta que levanta: Parear o 8292 pelo notch exige que a ponte suba a API antes de qualquer conta estar logada, e que perder uma conta não afete a outra. Pro primeiro QR do 8292, aceita escanear pelo terminal/log, deixando o QR no notch pra depois?
- Evidência: if client.Store.ID == nil { qrChan ...; qrterminal.GenerateHalfBlock(evt.Code, qrterminal.L, os.Stdout) ... case <-time.After(3*time.Minute): return }. startRESTServer(...) só na linha 1257, depois de conectar. Em timeout, o processo sai e o launchd religa a cada 10 s (servico.sh: ThrottleInterval 10, KeepAlive). servico.sh:3 'QR e erros: tail -f ~/Library/Logs/whatsapp-bridge.log'.
- Verificação: se sustenta — Confere: o tratamento de LoggedOut (main.go:1193-1194) só registra no log, o QR vai para o stdout (:1215, que o launchd manda para o log), há timeout de 3 min com return (sai do processo) e startRESTServer só roda em :1257. O servico.sh tem KeepAlive e ThrottleInterval 10. A spec (linhas 58-59 e 110-112) supõe pareamento pela rota e a outra conta seguindo de pé. Isso exige reestruturar a inicialização, como o achado diz.

#### A57 — Nenhuma rota faz streaming e não existe número sequencial de evento. As mensagens são gravadas com INSERT OR REPLACE, que troca o rowid, então o rowid não serve de cursor 'desde N'.
- Fonte: /Users/luccassilveira/Code/whatsapp-mcp/whatsapp-bridge/main.go:898-1126
- Contradiz a spec: nao
- Pergunta que levanta: O 'nenhuma mensagem some na queda' exige que a ponte guarde um diário de eventos numerado. Quanto tempo esse diário deve guardar: horas (leve) ou dias (o notch se recupera mesmo depois de o Mac dormir a noite toda)?
- Evidência: Rotas atuais, todas JSON simples no DefaultServeMux: POST /api/send, POST /api/group/add, POST /api/group/create (sem commit), POST /api/history, GET /api/group/info, /api/mediaretry (sem checar método), POST /api/download. Não há listagem de chats/mensagens por HTTP: quem lê é o MCP direto no SQLite. Escuta em 127.0.0.1:8099 (lsof confirma o pid 968).

#### A58 — A mídia é nomeada pelo segundo em que chega (image_YYYYMMDD_HHMMSS.jpg) e salva em store/<chat>/ sem conta. 2.722 mensagens dividem nome com outra no mesmo chat, e o download devolve o arquivo errado.
- Fonte: /Users/luccassilveira/Code/whatsapp-mcp/whatsapp-bridge/main.go:440-453
- Contradiz a spec: parcial
- Pergunta que levanta: Hoje uma foto pode abrir no lugar de outra (num grupo, 173 fotos têm o mesmo nome). Corrigir o nome pelo id da mensagem resolve daqui pra frente, mas as fotos já baixadas com nome repetido continuam suspeitas. Apaga a pasta de mídia e deixa baixar de novo sob demanda?
- Evidência: "image_" + time.Now().Format("20060102_150405") + ".jpg" (usa a hora do processamento, não a da mensagem: no histórico, lotes inteiros caem no mesmo segundo). downloadMedia: chatDir := store/<chat> (main.go:624); if os.Stat(localPath) == nil { return existente } (:662). sqlite: 196 pares (chat, filename) repetidos, 2.722 mensagens; o pior é 120363177450713790@g.us|image_20261013_173908.jpg|173. A memória (whatsapp.md, 2026-10-29) já registra o contorno manual por md5. A store tem 316 MB.
- Verificação: se sustenta — Confere: main.go:440-453 nomeia por time.Now() (hora do processamento), downloadMedia usa store/<chat> (:624) e devolve o arquivo já existente se o nome bate (:662). Os números mudaram com o dado vivo: hoje são 202 pares (chat, nome) repetidos e 2.734 mensagens. O pior caso continua 120363177450713790@g.us|image_20261013_173908.jpg com 173. A contagem também inclui documentos com o mesmo nome original, que colidem do mesmo jeito.

#### A59 — A ponte não tem nenhuma autenticação. O MCP chama as rotas sem cabeçalho nenhum, então ligar a chave quebra o MCP no mesmo instante, a menos que os dois mudem juntos.
- Fonte: /Users/luccassilveira/Code/whatsapp-mcp/whatsapp-mcp-server/whatsapp.py:653
- Contradiz a spec: nao
- Pergunta que levanta: Ligar a chave obriga a trocar ponte e MCP juntos e reconectar o MCP do Claude. Topa uma janela curta em que o Claude não manda WhatsApp, ou prefere um período em que a ponte aceita com e sem chave?
- Evidência: requests.post(url, json=payload) sem headers em :653, :671, :685, :715, :755, :788. main.go:1117 'só o próprio Mac: a API envia mensagem sem senha'. WHATSAPP_API_BASE_URL = http://localhost:{WHATSAPP_BRIDGE_PORT or 8099}/api (:13).

#### A60 — Há mudanças sem commit na ponte (tipo de documento por extensão + FileName, vCard como texto, rota /api/group/create, escuta só em 127.0.0.1), e o binário rodando já as contém. Além disso, a branch está 2 commits à frente de origin.
- Fonte: /Users/luccassilveira/Code/whatsapp-mcp/whatsapp-bridge/main.go:1117
- Contradiz a spec: nao
- Pergunta que levanta: Antes de mexer pesado na ponte, quer que essas correções soltas virem commit e subam pro GitHub, pra ter um ponto de volta seguro se a versão de duas contas der problema?
- Evidência: git diff --stat: main.go +61/-5, ESTILO.md +2/-1. 'Your branch is ahead of origin/main by 2 commits' (063fbed, 0f89267). O binário whatsapp-bridge e o main.go têm a mesma mtime (Oct 31 11:41) e o processo escuta em 127.0.0.1:8099, então o que roda é o código não commitado.

#### A61 — O teste existente é um só (mensagem embrulhada vira documento com legenda) e passa.
- Fonte: /Users/luccassilveira/Code/whatsapp-mcp/whatsapp-bridge/main_test.go:10
- Contradiz a spec: nao
- Pergunta que levanta: Os testes da ponte praticamente começam do zero. Aceita que cada peça nova (conta, diário de eventos, chave) só entre com teste próprio, mesmo que isso atrase a primeira versão?
- Evidência: func TestWrappedDocumentIsStored; go test -count=1 ./... → ok whatsapp-client 0.357s. Não há teste de rota HTTP nem de banco.

#### A62 — O remetente é gravado em dois formatos: ao vivo só o número/LID sem servidor, no histórico o JID completo. Além disso, 23 contatos aparecem como duas conversas (uma por telefone e outra por LID).
- Fonte: /Users/luccassilveira/Code/whatsapp-mcp/whatsapp-bridge/main.go:473
- Contradiz a spec: parcial
- Pergunta que levanta: Sem unificar, a lista do notch vai mostrar a mesma pessoa duas vezes e o nome de quem falou no grupo pode sair como número. Quer que a ponte junte telefone e LID numa conversa só (lista limpa, mas mexe em dado que o MCP já usa)?
- Evidência: Ao vivo: sender := msg.Info.Sender.User; histórico: sender = *msg.Message.Key.Participant (main.go:1433). No banco são 12.143 remetentes sem '@' e 6.841 com. Chats por servidor: @s.whatsapp.net 635, @lid 274, @g.us 53, @broadcast 1 (status). Join com whatsmeow_lid_map: 23 contatos com chat nos dois JIDs.
- Verificação: se sustenta — Impreciso no histórico: main.go:1426-1440 só grava o JID completo quando é Participant (remetente de grupo). Para mensagem minha ou conversa individual, o histórico também grava só a parte do usuário (client.Store.ID.User / jid.User). No banco, todos os 6.841 remetentes com '@' são @lid e em grupo (0 fora de @g.us). Os 12.145 restantes não têm servidor. Confere: chats por servidor (635/274/53/1) e os 23 contatos com conversa por telefone e por LID ao mesmo tempo (join com whatsmeow_lid_map).

#### A63 — Não há contagem de não lidas nem estado de leitura. O histórico traz a contagem de não lidas por conversa, mas a ponte ignora.
- Fonte: /Users/luccassilveira/Code/whatsapp-mcp/whatsapp-bridge/main.go:1361-1396
- Contradiz a spec: nao
- Pergunta que levanta: A contagem de não lidas do notch vai começar do zero e pode não bater com a do celular (o que você leu no celular só aparece como lido se a ponte acompanhar). Basta 'não lidas desde que a ponte viu', ou precisa bater com o celular?
- Evidência: handleHistorySync só lê conversation.ID, nome e Messages; StoreChat(jid, name, timestamp). Sem coluna de lido/não lido. Além disso, handleMessage chama StoreChat antes do filtro de descarte (main.go:479 vs :491): reação e figurinha descartadas mesmo assim empurram o chat para o topo.

#### A64 — O áudio de voz é enviado só se já vier em .ogg Opus. A conversão hoje mora no MCP em Python (ffmpeg), não na ponte. A ponte só calcula duração e forma de onda.
- Fonte: /Users/luccassilveira/Code/whatsapp-mcp/whatsapp-mcp-server/whatsapp.py:743-747
- Contradiz a spec: parcial
- Pergunta que levanta: A gravação do notch precisa virar o formato de voz do WhatsApp em algum lugar. Prefere que a ponte converta (depende do ffmpeg instalado no Mac) ou que o próprio Knobler grave já no formato certo (mais trabalho no app, sem dependência externa)?
- Evidência: if not media_path.endswith('.ogg'): audio.convert_to_opus_ogg_temp(media_path) (ffmpeg). Ponte: case "ogg" → MediaAudio PTT, analyzeOggOpus (main.go:316-318, 368-391); qualquer outro áudio cai em documento. ffmpeg presente em /opt/homebrew/bin/ffmpeg. O envio de mídia recebe um caminho local (media_path, main.go:289 os.ReadFile), não upload.
- Verificação: se sustenta — Confere: whatsapp.py:743-747 converte para .ogg via audio.convert_to_opus_ogg_temp (ffmpeg). A ponte só manda como voz (PTT) quando a extensão é 'ogg' (main.go:316-318) e calcula duração e forma de onda com analyzeOggOpus (:368-391). Qualquer outra extensão cai em documento (:331-338). A ponte lê o arquivo por caminho local com os.ReadFile (:289). O ffmpeg existe em /opt/homebrew/bin/ffmpeg (8.0.1).

#### A65 — Os dois bancos estão em journal_mode=delete (sem WAL) e a conexão Go não define busy_timeout. Com Knobler, MCP e ponte lendo e escrevendo, cresce o risco de 'database is locked'.
- Fonte: /Users/luccassilveira/Code/whatsapp-mcp/whatsapp-bridge/main.go:61
- Contradiz a spec: nao
- Pergunta que levanta: Com o notch consultando a ponte o tempo todo e o Claude lendo o mesmo banco, uma gravação pode falhar por banco ocupado e a mensagem não ser salva. Aceita que a ponte troque o modo do banco pra permitir leitura e escrita ao mesmo tempo (muda arquivos auxiliares na pasta store)?
- Evidência: sql.Open("sqlite3", "file:store/messages.db?_foreign_keys=on"); sqlstore.New(..., "file:store/whatsapp.db?_foreign_keys=on") (main.go:1142). PRAGMA journal_mode → delete nos dois. Falha no StoreMessage só vira logger.Warnf (main.go:514).

### Frente: Pesquisa externa

#### A66 — O MCP do Claude não passa pelas rotas da ponte para ler: ele abre o messages.db e o whatsapp.db da ponte direto no SQLite. Por isso o padrão 'sem conta, vale o 4143' não o protege.
- Fonte: /Users/luccassilveira/Code/whatsapp-mcp/whatsapp-mcp-server/whatsapp.py:11-13,54,409-416
- Contradiz a spec: sim
- Pergunta que levanta: Quando a segunda conta entrar no mesmo banco, o Claude vai enxergar conversas e contatos do 8292 misturados com os do 4143. Você quer que ele veja as duas contas ou que continue vendo só o 4143? Se for só o 4143, o MCP tem que ser ajustado junto, e não depois.
- Evidência: MESSAGES_DB_PATH = .../whatsapp-bridge/store/messages.db; conn.execute("SELECT jid, name, last_message_time FROM chats"); SELECT their_jid... FROM whatsmeow_contacts (não filtra our_jid). Só os envios usam requests.post para :8099.
- Verificação: se sustenta — Se sustenta: whatsapp.py:11-12 aponta direto para store/messages.db e store/whatsapp.db, e :409-416 lê chats e whatsmeow_contacts sem filtro. Só os envios passam pela ponte (requests.post, :653 em diante), e esses ficam protegidos pelo padrão 4143. Detalhe: whatsmeow_contacts já tem a coluna our_jid (o sqlstore multi-aparelho grava por conta), então dá para filtrar contatos sem migração. Já chats e messages não têm coluna de conta.

#### A67 — A chave primária de messages é (id, chat_jid) e a de chats é só jid. Num grupo em que as duas contas estão, a mesma mensagem tem o mesmo id e o mesmo chat_jid nas duas contas. O INSERT OR REPLACE sobrescreve uma com a outra, e a marca de conta fica valendo só a última que chegou.
- Fonte: /Users/luccassilveira/Code/whatsapp-mcp/whatsapp-bridge/main.go:68-89,122-126
- Contradiz a spec: parcial
- Pergunta que levanta: Nos grupos onde estão o 4143 e o 8292 (o 554792508292-1575256960@g.us, por exemplo), a mensagem só fica guardada uma vez. Topa migrar o banco para guardar por conta, com o risco de mexer no histórico que o MCP já lê, ou prefere aceitar que esses grupos apareçam numa conta só?
- Evidência: PRIMARY KEY (id, chat_jid); chats jid TEXT PRIMARY KEY; INSERT OR REPLACE INTO messages. A mídia também vai para store/<chat_jid>/, sem separar por conta.
- Verificação: se sustenta — Confirmado em main.go:68-89 (chats jid PK, messages PK (id, chat_jid)) e :122-126 (INSERT OR REPLACE). O id da mensagem é gerado por quem envia e é igual para todos os membros do grupo, então há colisão de fato. O grupo 554792508292-1575256960@g.us ('COISAS') existe no messages.db. A mídia vai para store/<chat_jid>/ (main.go:624, 852). Ressalva: em conversa individual entre 4143 e 8292 não há colisão, porque cada lado grava o outro como chat_jid. Fora a chave, o is_from_me também se inverte entre as contas.

#### A68 — O whatsmeow aceita várias contas no mesmo processo: um Container com GetAllDevices, um whatsmeow.Client por device e NewDevice para parear uma conta nova. O mautrix-whatsapp faz exatamente assim. A ponte de hoje usa GetFirstDevice, que a própria documentação diz para usar só quando não se quer mais de uma sessão.
- Fonte: ~/go/pkg/mod/go.mau.fi/whatsmeow@v0.0.0-20260915134308-320ff7ebf928/store/sqlstore/container.go:157-174,212; https://github.com/mautrix/whatsapp/blob/main/pkg/connector/client.go (GetDevice + NewClient por login); ~/Code/whatsapp-mcp/whatsapp-bridge/main.go:1149
- Contradiz a spec: nao
- Pergunta que levanta: Juntar as duas contas num processo só da ponte é o caminho que a própria biblioteca suporta. O custo é que, se a ponte cair, as duas contas caem juntas. Aceita isso, ou prefere um processo por conta, como o wacli faz, com o dobro de serviço para manter?
- Evidência: GetFirstDevice: "You should only use this if you don't want to have multiple sessions simultaneously." mautrix: w.Device, err = wa.DeviceStore.GetDevice(ctx, w.JID); w.Client = whatsmeow.NewClient(w.Device, ...); login: device := wl.Main.DeviceStore.NewDevice()

#### A69 — O SQLite da ponte está em journal_mode=delete, sem WAL e sem busy_timeout. Com dois clientes gravando ao mesmo tempo e o MCP lendo, aparece 'database is locked'. O mautrix passou a exigir WAL e recomenda _txlock=immediate.
- Fonte: ~/Code/whatsapp-mcp/whatsapp-bridge/main.go:61,1142 (sqlite3 pragma journal_mode => delete); https://github.com/mautrix/whatsapp/blob/main/CHANGELOG.md (v0.8.0: 'Switched SQLite config ... to sqlite3-fk-wal ... _txlock=immediate is recommended')
- Contradiz a spec: parcial
- Pergunta que levanta: Com as duas contas escrevendo no mesmo arquivo, uma mensagem pode falhar ao ser salva quando chegarem várias juntas, por exemplo na sincronização inicial do 8292. Topa mudar o modo do banco agora, sabendo que isso mexe no arquivo que o MCP também abre?
- Evidência: sql.Open("sqlite3", "file:store/messages.db?_foreign_keys=on"); sqlstore.New(..., "file:store/whatsapp.db?_foreign_keys=on"); sqlite3 store/whatsapp.db 'pragma journal_mode' -> delete
- Verificação: se sustenta — journal_mode=delete está certo nos dois bancos, e a citação do mautrix v0.8.0 confere. Mas 'sem busy_timeout' está errado: o mattn/go-sqlite3 usa busy_timeout de 5000 ms por padrão (go-sqlite3 sqlite3.go:1231) e o sqlite3.connect do Python espera 5 s. O 0 que o CLI mostra vale só para aquela conexão. Então 'database is locked' não é certo de aparecer. O risco que sobra é a promoção de trava em transação deferred, que devolve BUSY sem esperar; é por isso que o mautrix recomenda _txlock=immediate. É um risco menor do que o achado faz parecer.

#### A70 — Hoje a ponte morre por inteiro se não conecta. O pareamento só acontece no terminal com timeout de 3 minutos, e LoggedOut só gera log. Com duas contas, uma conta deslogada derruba as duas, e o launchd fica religando a cada 10 s.
- Fonte: ~/Code/whatsapp-mcp/whatsapp-bridge/main.go:1193-1194,1201-1229,1243-1245; servico.sh (KeepAlive true, ThrottleInterval 10)
- Contradiz a spec: parcial
- Pergunta que levanta: A spec diz que a outra conta segue funcionando quando uma desloga. Hoje, uma conta sem sessão para a ponte toda. Pode contar que a inicialização vai ser reescrita para cada conta subir sozinha?
- Evidência: if !client.IsConnected() { logger.Errorf("Failed to establish stable connection"); return }; case *events.LoggedOut: logger.Warnf(...). GetQRChannel 'must be called *before* Connect()' (qrchan.go:217).
- Verificação: se sustenta — O código confere: return em main.go:1243-1245, QR no terminal com timeout de 3 min em :1201-1229, LoggedOut só gera log em :1193-1194. Mas 'religando a cada 10 s' está errado. Num logout em execução o processo não sai: fica de pé e desconectado, sem religar. Ao subir sem sessão, ele espera o QR (cerca de 160 s até o canal fechar) e depois mais até 3 min antes de sair; aí o launchd religa com intervalo mínimo de 10 s. O ciclo é de minutos, não de 10 s. 'Uma conta deslogada derruba as duas' é uma projeção do código de conta única. Vale como alerta de que a inicialização precisa ser reescrita.

#### A71 — O macOS só passou a tocar Ogg Opus (o formato das notas de voz) nativamente no 15.4. Testei nesta máquina (macOS 26): o .ogg recebido abre direto no AVAudioFile e no AVAudioPlayer. No target de 14.2 isso não é garantido. Opus dentro de CAF toca desde o 10.13.
- Fonte: https://webkit.org/blog/16574/webkit-features-in-safari-18-4/ ; teste local com ~/Code/whatsapp-mcp/whatsapp-bridge/store/157192044961796@lid/audio_20261103_215253.ogg (afinfo: Oggf, 1 ch 48000 Hz opus; AVAudioPlayer ok dur 11.18)
- Contradiz a spec: parcial
- Pergunta que levanta: Como a feature é só para você, que está no macOS 26, o áudio recebido já toca sem conversão nenhuma. Quer pular essa conversão na ponte e deixar o recurso exigir macOS 15.4, ou manter a conversão para funcionar em qualquer Mac a partir do 14.2, com mais código para manter?
- Evidência: WebKit 18.4: Ogg container support for Opus and Vorbis 'on macOS Sequoia 15.4, iOS 18.4...'. O SDK não traz nenhuma constante kAudioFile*Ogg pública. Os 103 áudios recebidos são todos Ogg Opus mono 48 kHz.
- Verificação: se sustenta — A fonte é a nota do WebKit/Safari 18.4: ela fala do suporte a Ogg no navegador, não do AVFoundation/CoreAudio. A versão exata em que o AVAudioFile passou a abrir Ogg não está documentada; o mais seguro é dizer 'confirmado no Mac atual, não garantido no 14.2'. A máquina roda macOS 27.0 (sw_vers), não 26. Há 118 .ogg em store/, não 103. Que o arquivo citado é Oggf, opus, mono, 48 kHz, ~11,2 s, confere.

#### A72 — O macOS grava Opus em CAF nativamente (AVAudioFile e AVAudioRecorder com kAudioFormatOpus, a 16 kHz ou 48 kHz), mas não grava Ogg (erro 'fmt?' até no macOS 26). E o ffmpeg 8 não consegue reembalar CAF-Opus da Apple em Ogg sem reencodar ('No extradata present'). Só reencodando com libopus funciona.
- Fonte: teste local: afconvert -f Oggf -d opus -> 'ExtAudioFileWrite failed (fmt?)'; ffmpeg -i rec.caf -c:a copy back.ogg -> 'No extradata present ... Could not write header'; ffmpeg -c:a libopus -ac 1 -ar 48000 -application voip out.ogg -> ok
- Contradiz a spec: parcial
- Pergunta que levanta: Mandar áudio de voz exige converter a gravação na ponte: reencodar com o ffmpeg ou escrever um empacotador próprio. Prefere depender do ffmpeg do Homebrew, que já está instalado, ou ter um conversor próprio, mais trabalhoso e sem dependência externa?
- Evidência: AVAudioFile(forWriting:) com Opus: .caf 48k/16k 'ok write'; .ogg 'ExtAudioFileWrite' code 1718449215. ffmpeg 8.0.1 com libopus em /opt/homebrew/bin.
- Verificação: se sustenta — Reproduzi: afconvert para CAF/Opus funciona, para Oggf falha com 'ExtAudioFileWrite failed (fmt?)', o ffmpeg com -c:a copy falha com 'No extradata present', e reencodar com libopus funciona. Falta dizer que essa conversão já existe hoje no MCP: whatsapp-mcp-server/audio.py chama o ffmpeg para gerar Ogg Opus. Portanto o caminho ffmpeg já é usado em produção; a decisão é só onde ele mora (ponte ou Knobler).

#### A73 — O serviço da ponte roda com PATH=/usr/bin:/bin:/usr/sbin:/sbin, sem /opt/homebrew/bin. Um exec do 'ffmpeg' pelo nome falha dentro do serviço, mesmo funcionando no terminal.
- Fonte: launchctl print gui/$UID/com.whatsapp-mcp.bridge ('default environment = { PATH => /usr/bin:/bin:/usr/sbin:/sbin }'); ~/Code/whatsapp-mcp/whatsapp-bridge/servico.sh:29 (plist sem EnvironmentVariables)
- Contradiz a spec: parcial
- Pergunta que levanta: Se a conversão de áudio usar o ffmpeg, o envio de voz vai funcionar no teste manual e falhar no serviço, a menos que o caminho seja fixado. Topa fixar no serviço o caminho do Homebrew?
- Evidência: plist: ProgramArguments, RunAtLoad, KeepAlive, ThrottleInterval; nenhum EnvironmentVariables.
- Verificação: se sustenta — Confirmado: o launchctl print mostra 'default environment = { PATH => /usr/bin:/bin:/usr/sbin:/sbin }', e o plist gerado por servico.sh (linhas 24-38) não tem EnvironmentVariables. Detalhe: o plist é regerado pelo servico.sh a cada religada, então a correção tem que ir no script, ou então em chamar o ffmpeg pelo caminho absoluto no código. Hoje o MCP chama o 'ffmpeg' pelo nome sem problema porque roda com o ambiente do Claude, não do launchd.

#### A74 — O envio de nota de voz já existe na ponte (PTT=true, mimetype 'audio/ogg; codecs=opus', Seconds tirado do Ogg). Mas a forma de onda é sintética: gera senos aleatórios em vez do áudio real. A Meta exige Ogg com codec Opus e mono para nota de voz.
- Fonte: ~/Code/whatsapp-mcp/whatsapp-bridge/main.go:316-318,365-391,1518,1616,1634; https://developers.facebook.com/docs/whatsapp/cloud-api/reference/media/ ('audio/ogg (OPUS codecs only; base audio/ogg not supported; mono input only)')
- Contradiz a spec: sim
- Pergunta que levanta: O envio de áudio já funciona na ponte. O que falta é a forma de onda: quem recebe vê um desenho inventado, não o da sua voz. Vale gastar esforço calculando a onda real a partir da gravação, ou o desenho inventado serve?
- Evidência: msg.AudioMessage = {Mimetype, Seconds, PTT: true, Waveform: waveform}; waveform = placeholderWaveform(duration) // 'generates a synthetic waveform'
- Verificação: se sustenta — Confirmado: main.go:316-318 usa o mimetype 'audio/ogg; codecs=opus', :365-391 monta o AudioMessage com PTT=true e Seconds tirado do Ogg, e placeholderWaveform (:1634) gera senos mais ruído aleatório. A citação da Meta é da Cloud API oficial, não do protocolo multi-aparelho que o whatsmeow usa. Serve só como indício do formato, não como exigência da ponte. 'contradiz: sim' só se sustenta porque a spec lista o áudio de voz como rota a construir.

#### A75 — O URLSession.AsyncBytes.lines descarta linhas vazias, e é a linha vazia que fecha cada evento SSE. Confirmei aqui: um stream com 6 linhas (2 vazias) saiu com 4. Além disso, o URLSession corta a conexão depois de 60 s sem dados (timeoutIntervalForRequest), então o servidor precisa mandar um sinal de vida antes disso.
- Fonte: https://developer.apple.com/forums/thread/725162 ; MacOSX.sdk NSURLSession.h:1315-1323 ('wait for additional data ... The default value is 60'); teste local: 'id: 1\ndata: um\n\nid: 2\ndata: dois\n\n' -> 'linhas: 4'
- Contradiz a spec: parcial
- Pergunta que levanta: Com o canal ao vivo em SSE, o Knobler precisa de um leitor próprio e de um sinal de vida a cada ~20 s, senão perde a divisão entre eventos ou cai a cada minuto. Isso é aceitável, ou prefere o outro formato que o app já usa (próximo achado)?
- Evidência: for try await line in b.lines -> [id: 1][data: um][id: 2][data: dois] linhas: 4. O Last-Event-ID tem que ir no cabeçalho manualmente, porque o URLSession não reconecta sozinho.
- Verificação: se sustenta — Reproduzi: o stream de 6 linhas sai com 4 em URL.lines. Mas o sinal de vida não é obrigatório: o timeoutIntervalForRequest de 60 s (NSURLSession.h ~1315-1329, não 1323) se configura por sessão ou requisição; o próprio WebhookClient o põe em 30. O sinal de vida é recomendável para detectar queda, não é imposição. Cuidado também com o timeoutIntervalForResource (padrão de 7 dias) numa conexão longa.

#### A76 — O Knobler já tem um cliente de canal ao vivo pronto e testado: o WebhookClient, sobre WebSocket, com ping a cada 25 s, pong com timeout, backoff de até 30 s, reconexão ao acordar do sleep e NWPathMonitor. Do lado da ponte, a biblioteca de WebSocket (coder/websocket) já está entre as dependências.
- Fonte: /Users/luccassilveira/Desktop/Projetos/knobler/Knobler/WebhookClient.swift:53-68,191-200,222-247,282; ~/Code/whatsapp-mcp/whatsapp-bridge/go.mod (github.com/coder/websocket v1.8.15 // indirect)
- Contradiz a spec: parcial
- Pergunta que levanta: Reaproveitar o canal que o app já usa no webhook economiza o leitor novo e repete uma reconexão que já foi provada. SSE é mais simples só do lado da ponte. Prefere reaproveitar o que já existe ou seguir com SSE?
- Evidência: pingInterval: 25, pongTimeout: 10, backoffCap: 30; @objc private func didWake() { queue.async { self.forceReconnect() } }
- Verificação: se sustenta — O WebhookClient tem mesmo ping de 25 s, pong de 10 s, backoff até 30 s, didWake e NWPathMonitor (WebhookClient.swift:53-68, 191-247, 282). Mas não é reaproveitável como está: ele decodifica PushNotification com type 'notify' e está amarrado ao relay remoto. O que se reaproveita é o esqueleto de reconexão, não a classe. O coder/websocket aparece no go.mod da ponte como '// indirect' (vem do whatsmeow); dá para usar, mas vira dependência direta.

#### A77 — O número sequencial do 'o que mudou desde N' precisa sobreviver a uma reinicialização da ponte. O launchd religa a ponte sozinho (KeepAlive), e um contador só em memória volta a 1, fazendo o Knobler pular ou repetir eventos.
- Fonte: ~/Code/whatsapp-mcp/whatsapp-bridge/servico.sh:31-32 (KeepAlive true, ThrottleInterval 10); WHATWG SSE https://html.spec.whatwg.org/multipage/server-sent-events.html (Last-Event-ID)
- Contradiz a spec: parcial
- Pergunta que levanta: Para a promessa 'nenhuma mensagem some no buraco' valer mesmo quando a ponte reinicia, os eventos precisam ficar gravados em disco por um tempo. Aceita esse registro crescendo no banco da ponte, com limpeza periódica?
- Evidência: <key>KeepAlive</key><true/> <key>ThrottleInterval</key><integer>10</integer>
- Verificação: se sustenta — Confirmado em servico.sh (KeepAlive true, ThrottleInterval 10). A spec não diz onde o número sequencial mora, então o achado é um complemento, não um erro da spec. Vale igual se o canal for WebSocket em vez de SSE.

#### A78 — Marcar como lido usa MarkRead com o remetente, uma chamada por remetente nos grupos. Ler no celular chega à ponte como recibo do próprio usuário (tipo read, ou read-self quando a confirmação de leitura está desligada) e como MarkChatAsRead pela sincronização. A spec não menciona isso, e sem tratar esses dois o contador de não lidas do notch nunca zera quando você lê no celular.
- Fonte: ~/go/pkg/mod/go.mau.fi/whatsmeow@v0.0.0-20260915134308-320ff7ebf928/receipt.go:186-218; types/presence.go:44-47; types/events/appstate.go:94-100
- Contradiz a spec: parcial
- Pergunta que levanta: Quando você lê uma conversa no celular, quer que o notch zere as não lidas sozinho? Isso exige que a ponte repasse esses avisos de leitura.
- Evidência: MarkRead: 'You can mark multiple messages as read ... only if the messages were sent by the same user'; se a privacidade de leitura for None, manda 'read-self'; MarkChatAsRead: 'emitted when a whole chat is marked as read or unread from another device'.
- Verificação: se sustenta — MarkRead (receipt.go:185-218) e read-self (presence.go:44-47) conferem. Impreciso: MarkChatAsRead (appstate.go:94-100) é a ação explícita de 'marcar como lida/não lida' em outro aparelho, não a leitura comum. Ler a conversa no celular chega como recibo do próprio usuário (events.Receipt, tipo read ou read-self). Hoje a ponte não trata nenhum recibo (o grep de Receipt e MarkRead no main.go não acha handler), então as duas coisas são trabalho novo.

#### A79 — A ponte nunca anuncia presença 'disponível', e isso é bom: um aparelho vinculado marcado como online faz o celular parar de receber notificação. Por outro lado, a biblioteca pede um SendPresence depois de conectar para o servidor ter o nome de exibição; sem ele, os outros veem '-'.
- Fonte: ~/go/pkg/mod/go.mau.fi/whatsmeow@v0.0.0-20260915134308-320ff7ebf928/presence.go:60-63; https://github.com/EvolutionAPI/evolution-go/issues/54 ; https://github.com/mautrix/whatsapp/blob/main/pkg/connector/example-config.yaml ('Full presence bridging is not supported', send_presence_on_typing: false)
- Contradiz a spec: nao
- Pergunta que levanta: Mostrar 'online' ou 'digitando' a partir do notch pode silenciar as notificações do celular nas duas contas. Pode ficar fora do escopo nunca anunciar presença?
- Evidência: 'You should call this at least once after connecting so that the server has your pushname. Otherwise, other users will see "-" as the name.' grep SendPresence em main.go: 0 ocorrências.

#### A80 — Citar uma mensagem não exige guardar a mensagem original inteira. O mautrix preenche StanzaID, Participant e QuotedMessage só com o texto (ou texto vazio, se não achar a original), e o banco da ponte já guarda o texto.
- Fonte: https://github.com/mautrix/whatsapp/blob/main/pkg/msgconv/from-matrix.go (generateContextInfo e getQuotedMessage/convertQuote)
- Contradiz a spec: nao
- Pergunta que levanta: A citação pode mostrar só o texto da mensagem citada, sem a miniatura de foto, sem mexer no banco. Isso basta, ou você quer a miniatura na citação, com o banco passando a guardar mais coisa?
- Evidência: contextInfo.StanzaID = msgID.ID; contextInfo.Participant = msgID.Sender.String(); contextInfo.QuotedMessage = ...; return &waE2E.Message{Conversation: &text} (fallback Conversation: "")

#### A81 — A recuperação de mídia expirada e o pedido de histórico ao celular já existem na ponte (/api/mediaretry com SendMediaRetryReceipt e /api/history com BuildHistorySyncRequest). Reação, revogação e edição têm construtores prontos (a edição só vale até 20 min). Uma edição recebida chega como mensagem com IsEdit=true.
- Fonte: ~/Code/whatsapp-mcp/whatsapp-bridge/main.go:1007-1031,1049-1064,1186; ~/go/pkg/mod/go.mau.fi/whatsmeow@v0.0.0-20260915134308-320ff7ebf928/send.go:526-617; types/events/events.go:333
- Contradiz a spec: sim
- Pergunta que levanta: A 'mídia indisponível, tenta de novo pelo celular' já funciona na ponte e é só ligar ao notch. Quer incluir no escopo também editar e apagar as suas próprias mensagens, que a biblioteca já entrega pronto?
- Evidência: http.HandleFunc("/api/mediaretry"...), http.HandleFunc("/api/history"...); const EditWindow = 20 * time.Minute; BuildRevoke/BuildReaction/BuildEdit
- Verificação: se sustenta — /api/history (main.go:1007) e /api/mediaretry (:1049) existem, e o handler de MediaRetry também (:1186-1187). BuildRevoke, BuildReaction e BuildEdit existem (send.go:526, 541, 606), com EditWindow de 20 min (:598); IsEdit está em events.go:333. Ressalvas: a ponte hoje não trata IsEdit nem a revogação recebida (nenhuma ocorrência no main.go), então receber edição/apagamento é trabalho novo. 'contradiz' deveria ser parcial: a spec não diz que isso falta, só o exige.

#### A82 — Dá para parear também por código de 8 dígitos digitado no celular, sem escanear QR. A janela é curta: os QRs se esgotam e a conexão de login fecha em cerca de 160 s. O QR tem que ser pedido antes de conectar.
- Fonte: ~/go/pkg/mod/go.mau.fi/whatsmeow@v0.0.0-20260915134308-320ff7ebf928/pair-code.go:76-91; qrchan.go:215-221
- Contradiz a spec: parcial
- Pergunta que levanta: No notch, um QR pequeno pode ser difícil de escanear. Quer também a opção de parear por código digitado no celular, sabendo que nos dois casos há uns 2 minutos e meio para concluir?
- Evidência: 'QR codes are always generated and the login websocket is closed after the QR codes run out, which means there's a 160-second time limit.'
- Verificação: se sustenta — A janela de 160 s (pair-code.go:83-85) e o QR antes do Connect (qrchan.go:217) conferem. Impreciso: o código tem 8 caracteres alfanuméricos (base32 '123456789ABCDEFGHJKLMNPQRSTVWXYZ', pair-code.go:50,63-64), não 8 dígitos. E o PairPhone exige informar antes o número do telefone e ter o socket já conectado.

#### A83 — Ainda há relatos de aviso 'Your account may be at risk' e de banimento com whatsmeow e Baileys mesmo com pouco volume e só respondendo mensagens (2025-2026). O mantenedor fechou o tema como 'not planned', sem causa confirmada. Chegaram a perguntar se várias contas na mesma máquina pesam, mas ninguém confirmou.
- Fonte: https://github.com/tulir/whatsmeow/issues/810 ; https://github.com/tulir/whatsmeow/issues/561
- Contradiz a spec: nao
- Pergunta que levanta: Ligar o 8292 pessoal aumenta o que você tem em jogo. Se ele for banido, perde o número pessoal, que não tem recurso como o Business tem. Topa colocar o pessoal mesmo assim, ou começa só com o 4143 e liga o 8292 depois de algumas semanas sem aviso?
- Evidência: 'warning is being triggered even for clients that are not performing bulk messaging, but only replying'; 'in some cases, accounts have already been banned, even with legitimate, low-volume usage'; closed as not planned (jul/2026).

#### A84 — O WhatsApp limita a 4 aparelhos vinculados por conta e desloga os vinculados se o celular principal ficar mais de 14 dias sem uso. A ponte ocupa uma vaga em cada conta.
- Fonte: https://www.engadget.com/whatsapp-now-lets-you-use-your-account-on-multiple-phones-163158921.html ; https://greenapi.com/en/docs/faq/how-to-set-up-device-pairing
- Contradiz a spec: nao
- Pergunta que levanta: Se o 8292 já tiver quatro aparelhos vinculados (Desktop, web, tablet), um vai ter que sair para a ponte entrar. E se o celular pessoal ficar parado mais de duas semanas, a ponte cai sozinha. Isso pesa para você?
- Evidência: Fontes secundárias, sem a página oficial da Central de Ajuda: até 4 aparelhos vinculados; logout dos vinculados após 14 dias de celular inativo.

#### A85 — Duas pontes com as mesmas chaves derrubam uma à outra (evento StreamReplaced). Durante a migração para multi-conta, um processo antigo ainda vivo, ou um 'go run' de teste, desconecta o serviço.
- Fonte: ~/go/pkg/mod/go.mau.fi/whatsmeow@v0.0.0-20260915134308-320ff7ebf928/types/events/events.go:143-147; ~/Code/whatsapp-mcp/whatsapp-bridge/servico.sh:19-20
- Contradiz a spec: nao
- Pergunta que levanta: Durante o desenvolvimento, rodar uma ponte de teste com o banco real derruba a do serviço e, com ela, o MCP. Topa que os testes usem uma cópia do banco, ou aceita esses minutos de queda?
- Evidência: 'StreamReplaced is emitted when the client is disconnected by another client connecting with the same keys.'; servico.sh: '# duas pontes com a mesma sessão derrubam uma à outra'; pkill -x whatsapp-bridge

### Frente: Referências visuais

#### A86 — O card de chegada com resposta rápida já existe no Knobler (mensagens da rede local). Ele tem avatar de 30 pt, nome em semibold, prévia de 2 linhas, botão de fechar, campo 'Responder…' com avião de papel e miniatura de mídia opcional, num card de 360 x 72 pt (ou 108 pt com resposta, mais a altura da mídia).
- Fonte: Knobler/IncomingMessageView.swift:12-83; Knobler/NotchPresentation.swift:163-165; docs/images/messages-incoming.png
- Contradiz a spec: parcial
- Pergunta que levanta: O card do WhatsApp pode sair do card de mensagem que você já usa hoje, só com o selo da conta e o nome do grupo a mais. Fica igual ao resto do notch e sai mais rápido. Prefere isso ou quer um card próprio, com cara de WhatsApp?
- Evidência: A spec descreve o 'Card de chegada' (spec:73) como peça nova, mas `IncomingMessageView` já faz header + MediaThumb + replyField e `case .message` já dimensiona o card em 360 de largura
- Verificação: se sustenta — Confere (IncomingMessageView.swift:12-83, NotchPresentation.swift:163-165). Dois detalhes: as alturas 72/108 somam o topInset do notch, e o card está amarrado à rede local (peerID, MessageStore.avatar, vm.onSendReply, vm.openThread). Reaproveitar pede generalizar a origem e o envio, não só pôr o selo da conta.

#### A87 — A seção Mensagens já segue o caminho lista → conversa → campo de envio. As bolhas usam branco a 10% para a mensagem recebida e 22% para a enviada, canto de 8 pt e fonte footnote. Falha aparece como 'não entregue' em laranja. A conversa rola com altura máxima de 200 pt e abre ancorada no fim.
- Fonte: Knobler/MessagesView.swift:66-92; Knobler/MessagesView.swift:94-115; docs/images/messages-online.png
- Contradiz a spec: parcial
- Pergunta que levanta: A conversa do WhatsApp pode herdar o visual das mensagens que o notch já tem (bolha branca translúcida e lista com seta). Fica consistente, mas fica bem diferente do WhatsApp. Prefere manter a cara do Knobler ou a do WhatsApp?
- Evidência: bubble(): `.fill(.white.opacity(m.incoming ? 0.10 : 0.22))`; `Text("não entregue").foregroundStyle(.orange)`; `.defaultScrollAnchor(.bottom).frame(maxHeight: 200)`
- Verificação: se sustenta

#### A88 — O notch aberto não tem 600 x 300. As seções usam 430 pt de largura, e Mensagens tem 272 pt de altura de conteúdo. Só o Link abre um card largo de 780 pt, e a janela que hospeda o notch vai até no máximo 900 pt.
- Fonte: Knobler/NotchView.swift:74; Knobler/NotchPresentation.swift:209-221; Knobler/NotchPresentation.swift:186-190; Knobler/NotchPresentation.swift:251
- Contradiz a spec: parcial
- Pergunta que levanta: Com 430 pt cabe uma coisa por vez: a lista, ou a conversa com botão de voltar. Abrindo largo como o Link (780 pt), dá para ver lista e conversa lado a lado, mas o notch cobre mais da tela. Qual dos dois?
- Evidência: `layout.sectionWidth = NotchMetrics.larguraDoCard(vm.focus, padrao: 430, ...)`; `static let linkCardWidth: CGFloat = 780`; `case .mensagens: return 272`; hostFrame `min(screen.width, 900)`
- Verificação: se sustenta — Os números conferem (NotchView.swift:74 dá 430, NotchPresentation.swift:221 dá 272, :204 dá 780, :187 limita a 900). Mas a spec não fala em 600 x 300 nem cita medida nenhuma, então nada é contradito: o achado completa uma lacuna (contradiz=nao). A altura do card aberto também soma topInset + 60 aos 272 (NotchPresentation.swift:159-160). A pergunta continua valendo.

#### A89 — O sistema visual proíbe uma segunda cor na interface: a hierarquia vem só das camadas de branco, e o vermelho é reservado ao ponto de gravação. A spec pede 'bolha vermelha' para o envio que falha, e o padrão do WhatsApp usa verde nas bolhas e azul no 'lido'.
- Fonte: DESIGN.md:143; DESIGN.md:158-161; DESIGN.md:302; docs/vesta/specs/2026-11-04-whatsapp-design.md:113
- Contradiz a spec: sim
- Pergunta que levanta: Bolha verde, tique azul e falha em vermelho deixam o WhatsApp reconhecível na hora, mas quebram o notch todo preto e branco. Manter tudo em branco é coerente, só que 'lido' e 'falhou' passam a depender de ícone e texto. Abre exceção para o WhatsApp ou fica monocromático?
- Evidência: 'Do construir hierarquia com a escada de opacidade do branco (85% → 6%), não com uma segunda cor' e 'Recording Red: o ponto pulsante de gravação de mic'. Já existe exceção no código: a pílula do Pomodoro usa tomate e verde (Knobler/NotchView.swift:424-426), e Mensagens usa laranja
- Verificação: se sustenta — Exagera. O DESIGN.md:141-145 traz cores terciárias de estado (vermelho, amarelo, laranja), então não proíbe toda segunda cor nem reserva o vermelho ao ponto de gravação: a linha 143 só descreve esse uso. O que a bolha vermelha da spec (spec:113) quebra de fato é a linha 105: 'nunca com uma segunda cor de fundo'. Um texto ou ícone vermelho de falha caberia como cor de estado. A spec não pede bolha verde nem tique azul, isso é suposição do achado.

#### A90 — No WhatsApp o estado de entrega é um tique cinza (enviada), dois tiques cinza (entregue) e dois tiques azuis (lida). Se o 'lido' não puder ser azul, o DESIGN.md já exige que um estado não dependa só da cor ou do fundo.
- Fonte: https://www.pandasecurity.com/en/mediacenter/whatsapp-check-marks/; DESIGN.md:278
- Contradiz a spec: nao
- Pergunta que levanta: Se o lido não for azul, a diferença entre entregue e lido vira só intensidade do branco ou um ícone diferente, e pode passar batido de relance. Isso basta para você, ou o azul do lido é sagrado?
- Evidência: Três estados oficiais: um tique cinza = enviada; dois cinza = entregue; dois azuis = lida. A spec acrescenta 'enviando' (relógio) e 'falhou' com 'tentar de novo'. DESIGN.md:278 diz: 'O estado não depende só do fundo'

#### A91 — O notch não tem seletor segmentado para usar como modelo. O que há de mais perto são os chips do Ask (branco 8% inativo, 18% no hover, 25% selecionado, canto de 8 pt) e o botão Hoje da Agenda (28 pt de altura, canto de 6 pt, branco a 16% quando ativo). O seletor das duas contas, com a bolinha de conexão, sai desse vocabulário.
- Fonte: DESIGN.md:239-243; DESIGN.md:266-270; Knobler/NotchView.swift:1087
- Contradiz a spec: nao
- Pergunta que levanta: O seletor pode ser dois chips pequenos no topo ('4143' e '8292', cada um com sua bolinha de conectado e o número de não lidas), ou uma lista única com as duas contas misturadas e um selo em cada conversa. Os chips separam trabalho de pessoal; a lista única mostra tudo sem trocar de aba. Qual?
- Evidência: O único Picker do notch é o da câmera do espelho (NotchView.swift:1087). Os chips de opção já estão definidos como `option-chip` / `option-chip-hover` no front-matter do DESIGN.md

#### A92 — Já existe linguagem visual de gravação no notch. A pílula do ditado tem bolinha vermelha de 8 pt, o texto 'Ouvindo' e um medidor de nível em cápsula branca de 64 x 6 pt. O visualizador de barras (AudioBarsView) pega a cor da capa do álbum e está reservado à música.
- Fonte: Knobler/NotchView.swift:386-397; Knobler/NotchView.swift:1742; DESIGN.md:250-257
- Contradiz a spec: nao
- Pergunta que levanta: Gravar áudio no notch pode ter a mesma cara do ditado (bolinha vermelha e nível branco), e você já reconhece esse sinal. A forma de onda da mensagem de voz ficaria em barras brancas, sem cor. Serve, ou quer a onda colorida como no WhatsApp?
- Evidência: `case .recording(let level): Circle().fill(.red).frame(width: 8, height: 8); Text("Ouvindo") ... Capsule().fill(.white).frame(width: max(4, 64 * CGFloat(level)))`. A Borrowed Color Rule limita a cor da capa ao visualizador

#### A93 — A imagem de documentação do card de mensagem foi gerada pelo harness de snapshot com o campo de texto quebrado (placeholder amarelo com ícone de proibido). Snapshot de card com resposta rápida não mostra o campo real.
- Fonte: docs/images/messages-incoming.png; Knobler/IncomingMessageView.swift:47-58
- Contradiz a spec: parcial
- Pergunta que levanta: Os estados com campo de digitar (card de chegada com resposta e conversa com o campo de envio) não aparecem certos na conferência automática por imagem. Para esses, aceita conferir no app real por print manual, mesmo sendo mais lento?
- Evidência: A spec põe o 'card de chegada' no tools/snapshot.sh (spec, seção Testes), mas o TextField sai como placeholder amarelo offscreen, como mostra a própria docs/images/messages-incoming.png
- Verificação: se sustenta — Confere: docs/images/messages-incoming.png mostra o TextField como faixa amarela com o ícone de proibido. A própria spec (spec:130-131) já tira do snapshot a lista e a conversa por causa do ScrollView, mas deixa lá o card de chegada, que tem campo de texto. Por isso o achado é parcial e só vale para o card com resposta rápida (e para o QR, se tiver campo).

#### A94 — Referência inspo, Huly: a coluna 'Inbox' dentro do app escuro é uma lista densa (avatar redondo pequeno, nome em negrito, prévia em uma ou duas linhas em cinza, hora à direita), num fundo quase preto com um único acento frio. Ensina como encaixar muitas conversas numa coluna estreita.
- Fonte: https://huly.io
- Contradiz a spec: nao
- Pergunta que levanta: A linha de conversa pode ser compacta como numa caixa de entrada (avatar pequeno, nome, uma linha de prévia, hora e contador). Cabem umas 5 conversas nos 272 pt sem rolar. Prefere ver mais conversas ou linhas maiores com duas linhas de prévia?
- Evidência: Autopsy: 'dark UI dashboard screenshot (Tracker, Issues, Inbox panels)'. Fonte Inter, paleta #0c1c5e / #448cd0, acento só nos destaques da UI. Levar a densidade da lista, não o feixe de luz

#### A95 — Referência inspo, Cron: UI escura quase preta (#0a0a0a), tipografia do sistema (Helvetica Neue), texto branco e um único acento laranja usado só em estado e evento, nunca em título. É o mesmo princípio do DESIGN.md: a cor só marca estado.
- Fonte: https://cron.com
- Contradiz a spec: nao
- Pergunta que levanta: Se abrir exceção de cor, ela pode ficar restrita a um único lugar, como o tique de lido ou a bolinha de conta conectada, sem pintar bolha nem texto. Isso dá o reconhecimento do WhatsApp com um custo visual mínimo. Topa esse meio-termo?
- Evidência: Autopsy: 'Background near-black #0a0a0a. Text white. Accent orange #e74004 on logo, Sign up button, calendar event bars ... not in headline.' displayClass system-native

#### A96 — Referência inspo, Bolt: o campo de envio é uma caixa escura arredondada com '+' de anexo à esquerda, um botão de alternância e a ação principal à direita, tudo dentro da mesma caixa. É um modelo para juntar anexo, microfone e enviar numa linha só.
- Fonte: https://bolt.new
- Contradiz a spec: nao
- Pergunta que levanta: O campo de envio pode ter, na mesma linha, '+' para anexar e o microfone, que vira 'enviar' quando há texto (como no WhatsApp). Economiza espaço, mas esconde o botão de enviar até você digitar. Prefere assim ou com os dois sempre visíveis?
- Evidência: Autopsy: 'Large dark input box centered, placeholder ..., attachment +, "Plan" toggle, blue "Build now" pill with arrow.' Hoje o compositor de Mensagens põe interruptor, foto, link, campo e enviar soltos na linha (MessagesView.swift:117-148)

#### A97 — O arquivo de referências do inspo cobre quase só páginas de site. Para 'chat compacto escuro' a recomendação devolveu Buildkite, Lego, Beehiiv, Bird e Lemonsqueezy, sem nenhuma tela de conversa. Bolhas, citação e reação não têm referência ali; o modelo mais próximo é o próprio Knobler.
- Fonte: https://buildkite.com
- Contradiz a spec: nao
- Pergunta que levanta: Para citação, reação e áudio não há referência externa boa: o desenho sai do zero, em cima do WhatsApp e do visual do notch. Quer que o mockup copie a disposição do WhatsApp (citação numa faixa dentro da bolha, reação num selinho no canto) para você não ter que reaprender?
- Evidência: A recomendação escolheu a macroestrutura 'ecosystem-index' com consenso paperBand=mid e acento frio, e nenhum exemplar é UI de mensagens. A busca por 'chat app bubbles reactions voice' devolveu Music YouTube, Furo, Huly, Bolt, Bun e Cron

#### A98 — Mensagens já tem identidade verde na vitrine de plugins e nos Ajustes. Uma peça WhatsApp instalável à parte precisa de cor e ícone que não se confundam com a seção de Mensagens da rede local, que já existe.
- Fonte: Knobler/PluginsSettingsPane.swift:31; Knobler/SettingsView.swift:119; Knobler/NotchSectionOrder.swift:26-48
- Contradiz a spec: parcial
- Pergunta que levanta: Hoje já existe uma seção 'Mensagens' (verde, ícone de dois balões) para conversar com Macs da rede. O WhatsApp entra como seção nova ao lado dela, ou as duas viram uma seção só com abas? Separadas é mais claro; juntas ocupa menos espaço no notch.
- Evidência: `case .mensagens: return .green` (corDaPeca) e `case .mensagens: return "bubble.left.and.bubble.right.fill"` (NotchSection). A spec (spec:70) cria uma 'Seção WhatsApp' sem citar a Mensagens que já existe
- Verificação: se sustenta
## Fila do grill

Ordenada por dependência — decisão que trava outras vem primeiro. A19 foi refutado e não entra.

1. A51, A67, A52, A66 — Onde a conta mora no banco da ponte, sabendo que o MCP lê o SQLite direto e que grupo em comum colide. (trava 2, 10, 11, A58, A62)
2. A57, A77, A7, A75, A76 — Canal ao vivo: SSE ou WebSocket, e onde mora o número sequencial que sobrevive ao religar. (trava 7, 10)
3. A1, A38, A20 — A chave no Chaveiro fica ilegível entre processos; arquivo 0600 como o token dos agentes?
4. A56, A70, A82, A85 — A ponte precisa subir sem conta e parear pela rota; QR ou código; uma conta caída não derruba a outra.
5. A22, A23, A2, A3, A24, A26 — Como a peça fica invisível pra quem instala pelo brew (vitrine, atalhos, instalação nova, sondagem).
6. A4, A48 — Feature nova exige MINOR com página de novidades pública.
7. A5, A30, A35, A6, A34 — Card de chegada: vaga única sem fila (padrão LAN) ou fila de notificação (silêncio, Histórico em disco); supressão quando a conversa está aberta naquela tela.
8. A29, A31 — Digitar no compositor não protege contra cards, e o rascunho some.
9. A15, A36 — O filtro do banner do Desktop só roda com Acessibilidade e "notificações no notch" ligados.
10. A78, A63 — Não lidas precisam zerar quando você lê no celular.
11. A71, A72, A73, A74, A64 — Áudio: tocar Ogg direto, gravar Opus, conversão com ffmpeg na ponte, forma de onda real.
12. A9, A41, A11 — Gravar áudio longo liga o silêncio por microfone do próprio Knobler; texto da permissão fala só de ditado.
13. A42 — Ditado do Knobler não escreve no compositor do notch.
14. A88, A89, A90 — Tamanho da seção (430 × 272 hoje) e cores de estado (sem bolha vermelha, "lido" sem depender de azul).
15. A62 — Contatos que aparecem duas vezes (telefone e LID).

Decididos sem pergunta, por só haver uma resposta razoável: A47 (o snapshot cobre lista e conversa pela janela sintética; a spec estava errada), A58 (mídia nomeada pelo id da mensagem), A65/A69 (WAL e transação imediata), A8 (reconexão com teto de 30 s e jitter), A54 (salvar reação, edição, apagamento, figurinha e citação), A79 (nunca anunciar presença), A21 e A14/A27/A28/A43/A44/A45/A46/A33/A37 (detalhes de implementação para o plano).
