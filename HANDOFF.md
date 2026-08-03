# 🏁 SESSÃO 2026-08-03 (fim de tarde) — nota que não toma o card, player centrado, histórico que se apaga

Micro-correções pedidas na tela, todas validadas no app Debug rodando.

## O que foi feito

**A nota rápida deixou de ser modo exclusivo.** A faixa de seções continua no
rodapé com o rascunho em foco, e a altura do card soma a faixa sempre. Sair pela
faixa não apaga nada: `active` e `text` seguem. A zona de escrita ganhou fundo
`white 7%` (cantos 8) pra se separar da moldura preta — `alturaDaSecao(.nota)`
subiu de +20 pra +28 por causa do padding.

**Clique na faixa durante a nota era desfeito.** Só o swipe zerava
`QuickNote.editing`; o clique não, e o `recalcularSecoes` seguinte via
`travadaNaNota` ainda true e puxava o foco de volta. A trava agora cai dentro de
`NotchViewModel.focar` — o caminho que clique e swipe atravessam. A linha
duplicada no handler de scroll de `KnoblerApp` saiu.

**Player descentralizado.** Era um `HStack` de 4 com Spacers iguais, então o
play caía à direita do centro. O trio anterior/play/próxima virou um HStack
centrado com espaçamento fixo e o shuffle virou `.overlay(alignment: .leading)`.

**Apagar o histórico.** `NotificationHistory.remover(_:)` e `limpar()` (esta
escreve na hora, sem esperar o debounce de 1 s). Na lista: `X` por linha, visível
só no hover, e "Limpar" no topo direito. `historycheck` ganhou `testApagar`.

**Espelho sem câmera não trava mais.** `MirrorController` virou `ObservableObject`
com `falhou` publicado quando abrir o dispositivo falha; o preview troca o
spinner por "Câmera indisponível". `GET /status` ganhou `mirrorFailed`.

**Rodapé do painel de Permissões** corrigido: a acessibilidade é pedida na
abertura, não no primeiro uso.

## Estado

- 22 checks verdes, 55 snapshots gerados, build Debug rodando.

## Riscos e dívidas

- **Nada disso entra no harness de snapshot** a não ser o player
  (`music-expanded.png`, que confirma o trio centrado). Nota (`TextEditor`),
  histórico populado (`ScrollView`) e espelho (câmera real) só têm teste manual.
- **"Câmera indisponível" não foi visto de verdade**: a máquina tem webcam e não
  dá pra desconectar a FaceTime HD. O caminho de erro está exercitado só por
  leitura de código.

---

# 🏁 SESSÃO 2026-08-03 (tarde) — espelho que liga sozinho, link que se cola

Quatro pedidos curtos do usuário, todos validados no app rodando. Saiu a
`v0.18.0`.

## O que foi feito

**Espelho fixado liga sozinho** (`NotchView.ligarEspelhoSeEmFoco`, chamado no
`onChange` de `vm.focus` e de `vm.expanded`). O `expanded` também entra porque
recolher o card desliga a câmera — na reabertura o `focus` não muda.

**Abrir a câmera congelava o card por ~1 s.** Causa: `MirrorController.acquire()`
criava o `AVCaptureDeviceInput` na main thread. A sessão agora sobe vazia e
recebe a entrada no background; o preview mostra spinner + "Ligando a câmera…"
até o `AVCaptureSessionDidStartRunning`. Sem isso o spinner nem chegava a ser
desenhado — foi por isso que a primeira tentativa "não mostrou nada".

**Ícone de câmera saiu do player** (fila de controles e estado "Nada tocando").
O espelho agora se liga pela própria seção.

**Barra de endereço na seção Link.** Sem página, a seção mostra um `TextField`
já focado: ⌘V + Enter. `keyboardAllowed` deixou de exigir `linkPreview.hosted`
(o campo existe antes de haver página) e os atalhos de edição do `LinkPreview`
(⌘C/⌘V/⌘X/⌘A — o app não tem menu bar) passaram a `internal` pra serem
instalados também pelo campo. `alturaDaSecao`/`larguraDoCard` ganharam
`linkAberto`: os 780 pt são do preview, não da barra.

## Estado

- `v0.18.0` publicada (tag, GitHub Release, cask) e instalada em
  `/Applications`, rodando em 3 monitores.
- 22 checks verdes.

## Riscos e dívidas

- **Sem câmera utilizável o espelho fica no "Ligando a câmera…" pra sempre**
  (`ponytail:` em `Mirror.swift`). Vira estado de erro quando alguém sem webcam
  reclamar.
- Nada disso tem check automatizado: espelho e link dependem de `NSView` real e
  ficam fora do harness de snapshot.

---

# 🏁 SESSÃO 2026-08-03 — seções fixadas, e a nota que prendia o card

Uma feature pedida em uma frase ("escolher as funções fixadas no notch") que
expôs três bugs de interação na nota rápida — todos achados com o app rodando e
log real, não com leitura de código.

## O que foi feito

**Seções fixadas** (`v0.17.0`): alfinete por linha em Ajustes › Notch. Seção
fixada aparece no card mesmo sem conteúdo, na posição da ordem-base.
`NotchSectionOrder.ordenar` ganhou o parâmetro `fixadas`;
`AppSettings.notchSectionsFixadas` persiste (chave homônima, padrão vazio, sem
migração). Estados vazios novos: atividade, Pomodoro, Link e espelho desligado.
Foi executada por subagentes (5 tasks, spec + plano em `docs/superpowers/`).

**Foco inicial passou a ser a primeira seção COM conteúdo.** Sem isso, fixar a
Música abre o card em "Nada tocando" toda vez.

**A nota rápida deixou de ser uma armadilha.** Três bugs, nesta ordem:

| Sintoma | Causa real |
|---|---|
| "perdi o texto ao sair" | não havia saída: o swipe era engolido com a nota em foco (`KnoblerApp.swift`, gate `vm.focus != .nota`) e a única saída era o interruptor, que apaga |
| "seção fixada não aceita teclado" | `keyboardAllowed` exigia `noteVisible`, mas a seção fixada desenha o campo antes de a nota ter dono → `QuickNote.adotar(_:)` |
| "não encolhe com o mouse fora" | `mode` devolve `.music` enquanto `typingNote`; zerar só o `expanded` deixava o card na tela, e o campo desenhado segurava o `editing` que sustentava o modo |

O card agora encolhe 3 s depois de o mouse sair (0,3 s no resto), e
`fecharPorHoverOut()` derruba `editing` junto. Só o **link** ainda congela o
card contra o hover-out.

## Como os bugs foram achados

`NSLog` temporário em `keyboardAllowed`, `setHover` e no work de fechar; app
Debug rodado com stdout em arquivo; o usuário reproduziu o gesto real. Os dois
últimos bugs eram invisíveis na leitura do código — o log mostrou
`fechar work rodou` seguido do card ainda aberto. **Vale repetir a receita:**

```bash
APP=~/Library/Developer/Xcode/DerivedData/Knobler-*/Build/Products/Debug/Knobler.app/Contents/MacOS/Knobler
nohup "$APP" > /tmp/knb.log 2>&1 &
```

O menu da barra é acionável por AppleScript (`System Events` → `menu bar item 1
of menu bar 1`), o que dá pra ligar a nota sem tocar no mouse. Clique e scroll
sintéticos **não** funcionaram nesta máquina (3 monitores).

## Estado

- 22 checks verdes; `eventoscheck` ganhou 6 casos novos (fixadas, swipe, adotar,
  atraso de fechar, hover-out).
- O harness agora zera `notchSectionsFixadas` no `main()`: um teste que aborta
  no meio contaminava a rodada seguinte.
- Instalado em `/Applications` e validado no app rodando.

## Pendências deixadas de propósito

- **Persistência da nota em disco** — o usuário adiou explicitamente ("persistência
  vemos depois"). A nota continua morrendo com o app.
- **Link fixado não reabre o último link**: a seção mostra "Nenhum link copiado".
- `docs/images/settings-notch.png` foi recapturado com o alfinete ainda como
  botão; hoje é um checkbox. Vale refazer na próxima captura de painéis.
- Harness de snapshot não cobre os quatro estados vazios novos (são `Image` +
  `Text`, a lógica de quando aparecem está travada por asserção).

# 🏁 SESSÃO 2026-07-29 (noite, 2) — o roadmap não sobreviveu ao código

Sessão **só de documentação** (commit `5ed1b22`): zero linha de Swift. O produto
dela é uma ordem de implementação que agora corresponde ao que existe no repo, e
a spec/plano/pesquisa do sync pela LAN.

## O que foi feito

Pedido inicial: ordenar o backlog do `IDEIAS.md` de forma que cada feature deixe
pronta a peça da próxima. Saiu um `docs/ROADMAP.md` com 6 trilhas — escrito por
dedução a partir de nomes de arquivo, **sem ler o código**. Ao começar a
implementar a Trilha 1, ela caiu inteira:

| O que o roadmap prometia criar | Onde já estava |
|---|---|
| "Camada de envio de webhooks" (`WebhookClient.send`) | **não existe** — o cliente é só entrada; e webhook de saída está em Descartadas |
| Motor de template de payload | `relay/src/template.js` (`{{ dot.path }}`) + `MappingEditorView` |
| Retry com backoff | `WebhookClient.scheduleReconnect()` (exponencial + jitter, cap 30 s) |
| Fila offline com retry | `relay/src/db.js` — `enqueue`/`drainQueue`, dedupe, TTL 24 h, cap 50 |
| "Card que cresce" | `AgentRequestCard` (expandir + `ScrollView` + "Ver detalhes") |
| "Extrair sink do ditado" | `DictationDestination` (`.ask` / `.application`) |
| Wrapper de persistência | padrão já repetido em `NotificationHistory` e `MessageStore` |

Auditadas as 6 trilhas: **3 eram falsas**, 1 sobreviveu (a do Wire), 2 viraram
itens soltos. `ROADMAP.md` reescrito com uma tabela do que **já existe**, pra o
próximo roadmap não repetir o erro. `IDEIAS.md` podado (13 ideias descartadas
pelo dono + as 4 que morreram com o webhook de saída).

Depois, grilling sobre o item que sobrou grande — sync entre máquinas — e fase de
pesquisa com experimento rodado nesta máquina.

## Validação

- `./tools/check.sh` → **20 checks ok** (o plano dizia 18; corrigido).
- TLS-PSK provado por probe compilado e executado, não por memória: matriz de
  versão/ciphersuite, metadata da conexão, e rejeição de PSK/identity errados.

## O que a pesquisa provou (e derrubou)

- **PSK não funciona em TLS 1.3.** `min = TLSv13` → `-9858: handshake failed` em
  toda variação. Fecha em 1.2 negociando `TLS_PSK_WITH_AES_128_GCM_SHA256`
  (0x00A8) — suite que o enum `tls_ciphersuite_t` do Swift **nem expõe** (zero
  ocorrências de "PSK" no header). Fixar `min = max = .TLSv12` de propósito.
- **Sem forward secrecy**: PSK puro deriva a sessão só do segredo. PSK vazado
  depois torna tráfego gravado antes decifrável. Aceito + botão de rotação; a
  alternativa era handshake ECDH caseiro.
- **TOFU com certificado por dispositivo descartado por viabilidade**: não há API
  pública no macOS pra gerar X.509 auto-assinado (`SecCertificateCreateWithData`
  exige DER pronto). Era o desenho superior.
- `NSBonjourServices` só declara `_knobler._tcp` — serviço novo precisa entrada.
- O PSK no Keychain herda a ACL presa à assinatura (mesmo caso do webhook): troca
  de assinatura trava o par nas duas máquinas. Aqui re-parear pode ser
  automático, porque não invalida nada público.

## Bloqueio de segurança registrado

`LANMessaging.serve()` **não autentica nada**: qualquer host da LAN abre conexão
e manda `.message`. Defesas são só UUID canônico no `from`, teto de 2000
caracteres e validação dos bytes do anexo. Aceitável pra mensagem (pior caso é
card de spam); **inaceitável** pra Ajustes, lembretes e histórico numa rede
compartilhada. Por isso o passo 1 da trilha é pareamento, não a feature.

## Pendências e followups

- **Nada implementado.** O plano
  (`docs/superpowers/plans/2026-07-29-sync-lan.md`) tem 7 tarefas; começar pela
  Task 1 (HLC + merge puros + `tools/synccheck.swift`), que não toca rede.
- **Não medido**: tempo de reconciliação com histórico cheio de mídia — decide se
  precisa indicador de progresso no card.
- **Não testado**: dois listeners Bonjour no mesmo processo (mensagens + sync).
- **Ressalva registrada, decisão do dono**: escopo é os 3 tipos de dado com mídia
  junto desde já. A mídia é a maior parte do esforço e o dado mais sensível;
  "sob demanda depois" não custaria retrabalho se quiser cortar.
- `CHANGELOG.md` intocado de propósito: sessão sem mudança de comportamento.

---

# 🏁 SESSÃO 2026-07-29 (noite) — cinco features, e o app foi quem achou os bugs

Sessão de feature, **não publicada**: tudo está em `## [Unreleased]` do
CHANGELOG. Cinco entregas, todas commitadas em `master` (5 commits à frente do
`origin`, **sem push ainda**).

## O que entrou

| Feature | Commit | Onde ler |
|---|---|---|
| Preview da conversão do shelf | `66d5135` | `docs/shelf.md` |
| Silêncio em reunião + estado do AirDrop | `c054e0d` | `docs/notifications.md`, `docs/shelf.md` |
| Preview de link dentro do card | `690aa4b` | `docs/link-preview.md` |
| Teclado no preview + histórico em disco | `2b6dc3a` | `docs/link-preview.md`, `docs/notifications.md` |

**Preview da conversão**: converter pelo menu de contexto gravava às cegas ao
lado do original. Agora converte pra pasta temporária e mostra miniatura, tamanho
antes/depois e presets de Qualidade/Tamanho; Salvar move, Descartar não deixa
rastro. PDF multipágina passou a converter todas.

**Silêncio em reunião** (opt-in, Ajustes › Notch): evento com link de call em
curso manda notificação de app/API/webhook direto pro histórico. Lembretes,
Pomodoro e Ask continuam aparecendo — são coisas que o usuário agendou.

**AirDrop**: atividade indeterminada enquanto envia, card no fim, e um
`↗ Enviar por AirDrop…` no menu da barra com seletor de arquivo.

**Preview de link**: arrastar link abre a página numa seção nova (Link) do card,
16:9, com teclado e ⌘C/⌘V. Link **não** entra na prateleira (decisão do usuário).

**Histórico em disco**: consequência direta do silêncio em reunião — ver abaixo.

## O que a sessão ensinou

**Os dois bugs do drop foram achados abrindo o app, não pelos gates.** O
`shelfdropcheck` tinha 27 asserções verdes com a feature 100% inacessível:

1. `onDrop(of:)` filtra os tipos **antes** do delegate. Eu atualizei o
   `validateDrop` e esqueci a lista do modificador — link recusado em silêncio.
2. O Chrome anuncia link como `com.apple.pasteboard.promised-file-url`, que
   conforma a `public.file-url`. Filtrar por conformidade pescava o link e o
   mandava pro caminho de arquivo, onde o `loadItem` devolvia nada.

Lição pra próxima: **gate de lógica pura não alcança fiação de SwiftUI.** Toda
feature que depende de `onDrop`, `onChange` ou modificador de view precisa de uma
passada no app rodando antes de ser dada como pronta.

**Uma decisão minha foi desmentida por medição.** Eu implementei os dois eixos de
preset em vídeo; medindo um 1080x1920 real, `MediumQuality` devolveu 320x568 pra
um pedido de 50% — os presets nomeados carregam teto de resolução próprio e o
multiplicam pelo `renderSize`. Vídeo ficou só com o eixo de tamanho. A tabela das
medições está na spec (`docs/superpowers/specs/2026-07-29-preview-conversao-design.md`).

**Eu documentei um limite que não existia.** Escrevi que teclado não chegava no
preview "porque o painel é nonactivating" — mas a nota rápida digita no mesmo
painel desde sempre. Era uma linha faltando em `NotchView.keyboardAllowed`.
Antes de chamar algo de limite da plataforma, procure quem no próprio app já faz
aquilo.

**Uma feature abriu buraco em outra.** O silêncio em reunião fez do histórico o
único destino de uma notificação silenciada — e o histórico era só memória, por
escolha registrada no cabeçalho do arquivo ("virar disco se alguém reclamar de
perda num restart"). A premissa mudou antes de alguém reclamar. Isso virou a
feature seguinte.

## Validação

- `./tools/check.sh` → **20 checks** (era 18 no começo da sessão). Gates novos:
  `conversionpreviewcheck` e `shelfdropcheck`; `historycheck` e `sharingcheck`
  ganharam casos.
- `./tools/snapshot.sh` → **55 PNGs** (era 54), com `shelf-preview-imagem` novo e
  hash estável entre rodadas.
- Build Debug limpo.
- **No app rodando**: conversão de imagem pra JPEG (usuário confirmou), preview
  de link, silêncio em reunião ponta a ponta (evento de teste criado e apagado do
  calendário), e histórico sobrevivendo a `pkill` + subir.
- **Headless com arquivos reais**: `.mp4` 1080x1920 nos três presets e PDF de 6
  páginas — foi o que pegou o problema do vídeo.

## Pendências

1. **Push não foi feito** — 5 commits locais à frente de `origin/master`.
2. **Release não foi publicada.** Tudo em `## [Unreleased]`; a próxima é
   **v0.16.0** (`./tools/release.sh minor`) — são features, não fixes.
3. **AirDrop nunca foi testado ao vivo**: precisa de outro aparelho por perto. O
   caminho de código está coberto por gate (rótulo, cancelamento), mas o envio
   real não.
4. **Teclado do preview de link não foi testado pelo usuário** — implementado e
   compilando, mas o teste é digitar num campo de site de verdade.
5. **Zoom do preview em 0,575** deixa texto em ~9 px. Se incomodar, baixar
   `LinkPreview.larguraCSS` de 1280 pra 1024 dá 0,72 e ainda entrega layout
   desktop. É um número só.
6. **`NotchNotification` agora tem init manual de 16 parâmetros.** Campo novo
   precisa entrar em três lugares (propriedade, `CodingKeys`, init). Esquecer a
   `CodingKeys` não dá erro de compilação — o campo só não persiste.
7. **VoiceOver segue fora**, por decisão explícita do usuário nesta sessão. O
   código tem uma única ocorrência de `accessibility*`.

## Estado da máquina do usuário

- `silenciarEmReuniao` ficou **ligado** nos defaults (eu liguei pra testar).
  `defaults delete com.zoi.knobler silenciarEmReuniao` volta ao padrão.
- Build Debug de `/tmp/knobler-dd/` foi encerrada e o `/Applications/Knobler.app`
  relançado no fim da sessão.

---

# 🏁 SESSÃO 2026-07-29 (fim de noite) — a limpeza das pendências herdadas

Sessão de pendência, sem feature nova, fechada com **v0.15.0 publicada**. A
pergunta foi *"o que vem agora pro nosso app?"*, a resposta saiu da leitura do
HANDOFF anterior — e **duas das três prioridades já estavam fechadas**, só não
no papel.

## O que já estava feito (e o HANDOFF mentia)

| Pendência anotada | Realidade |
|---|---|
| "`fix/nota-rapida-ux` não mergeada" | Branch nem existe. `git log master..feat/historico-nota-rapida` volta **vazio** — entrou inteira via 0.13.x |
| "monitor desconectado ainda não bate a perda da nota" | `KnoblerApp.swift:893-901` já desliga a nota quando a tela dona some; o `didSet` copia pro clipboard. Os três caminhos estão cobertos |

Lição pra próxima: **o HANDOFF acumula pendências que o código já fechou.**
Vale conferir cada uma contra o repo antes de planejar em cima delas — as duas
acima custaram menos de cinco minutos de verificação e teriam custado uma
sessão inteira de trabalho redundante.

## O que foi feito

**Bluetooth entrou no painel de Permissões.** O app usa oito permissões e o
painel listava sete: a do Bluetooth, que o monitor dos AirPods pede *na
abertura*, não tinha linha nem estado. O `Permission` ganhou o case entre
`calendario` e `redeLocal` (agrupa com as que têm status real, antes das
opacas); os quatro `switch` são exaustivos, então o compilador cobriu o resto e
o `SettingsView`, que itera `allCases`, não precisou de uma linha.

O estado vem de `CBManager.authorization` — **CoreBluetooth num app que só usa
IOBluetooth**. Os dois batem no mesmo `kTCCServiceBluetoothAlways`, e só o
CoreBluetooth expõe o estado sem instanciar um manager. Verificado compilando
contra o target 14.2 antes de escrever, não pela memória.

**`fatiaDoCiclo` era bug, não só duplicação.** A pendência dizia "reimplementa
`Pomodoro.duration(of:config:)`". Reimplementava — e **divergia**: o engine
aplicava `max(1, …)` nos minutos e a view não. Com uma fase configurada em 0, o
relógio contava 1 minuto e o anel do ícone não desenhava nada. Agora os dois
saem do mesmo `AppSettings.pomodoroConfig`, que substituiu
`Pomodoro.Config.fromSettings()`.

A config foi pra `AppSettings`, não pro `Pomodoro`: o engine tem
`configProvider` justamente pra não conhecer os Ajustes, e mover pra lá
quebraria esse isolamento. Os dois arquivos já estavam no harness de snapshot,
então nada mudou em `tools/snapshot.sh`.

**`expanded-shelf.png` recapturado.** Era anterior à faixa de ícones.

**`zoneWidth` do scroll fechado: nada a fazer.** O `400` já não é literal —
virou `NotchGesture.larguraFechada`, nomeado e comentado. Não deriva de nada
porque não existe card fechado de onde derivar; é deliberadamente mais largo
que o notch físico pra pegar dois dedos na moldura. A pendência pedia derivar
de algo inexistente.

## O buraco de cobertura que apareceu no caminho

**Nenhum dos nove cenários de Pomodoro o deixava na faixa** — todos o punham em
foco. O anel do `fatiaDoCiclo`, que a v0.14.0 lista como fix ("o ícone do
Pomodoro na faixa ganhou o anel"), **nunca teve um único PNG cobrindo**.
Cenário `faixa-pomodoro` adicionado.

Vale como padrão: quando uma seção tem comportamento *em foco* e *na faixa*,
são dois estados, e o harness tende a cobrir só o primeiro.

## Validação

- `./tools/check.sh` → **18 checks**, e build Debug limpo.
- `./tools/snapshot.sh` → **54 PNGs** (era 53). Rodado **duas vezes com hash
  comparado**: 4 não-determinísticos (os mesmos de sempre), **50 byte-idênticos**
  — os números do `CLAUDE.md` foram recontados, não estimados.
- Painel de Permissões conferido **no app rodando** (`--ajustes=permissoes`), não
  por leitura: o Bluetooth aparece com estado real.
- O anel de `faixa-pomodoro` bate com a conta (900 s de 25 min ≈ 60% do arco).

## O custo da recaptura da prateleira — leia antes de repetir

A recaptura do `expanded-shelf.png` **mexeu na máquina do usuário e ele mandou
parar no meio** ("para de mexer na porra do meu mouse"). Com razão: eu pedi
autorização pra fechar o app dele, mas **não** pra dirigir o cursor e clicar na
tela dele, que é o que a receita exige.

O que a receita exige, agora anotado no `CLAUDE.md`:

- fechar o Knobler que estiver rodando (senão são dois notches na mesma tela);
- `defaults write` em `shelfItems` e `notchSectionOrder`;
- **mover o cursor e clicar** — o hover só acorda com
  `CGWarpMouseCursorPosition` em passos pequenos (`mouseMoved` postado não
  basta), e o clique no ícone da faixa *encolhe* o card, então o ponteiro tem
  que subir logo depois ou ele recolhe antes do `screencapture`;
- conferir por `GET /status` (`notches[].focus == "shelf"`), que foi o que
  provou que o clique tinha funcionado enquanto as capturas saíam fechadas.

**Peça autorização explícita pra isso, não só pra fechar o app.**

Um card de **Ask de outra sessão** ("Qual repo-alvo? ghraphnizer / codegraph")
tomou o notch no meio das tentativas e estragou uma captura. Não foi respondido
nem cancelado — mas o app do usuário esteve fechado nesse intervalo, então
**aquela sessão pode ter ficado sem resposta**. Fica o aviso.

Estado devolvido no fim: `shelfItems` e `notchSectionOrder` originais, app de
`/Applications` relançado, processos de automação mortos.

## Pendências e followups

- **Não existe `settings-ditado.png`.** São 9 painéis de Ajustes e 8 imagens;
  o do ditado nunca foi capturado.
- **Nenhum self-check cobre `Permission`** no `check.sh` — o `_selfCheck()`
  existe em `Permissions.swift` e roda só em `DEBUG`, no launch. O case novo é
  coberto pela exaustividade do compilador, mas o `status` do Bluetooth não tem
  gate.
- Herdadas e ainda abertas: **digitar na nota nunca foi testado no app rodando**;
  **Aceitar/Recusar espelhado** precisa de AirDrop de outro Apple ID;
  **notarização** espera o Apple Developer Program.

---

# 🏁 SESSÃO 2026-07-29 (noite) — o card parou de empilhar

A sessão começou por uma queixa de UX, não por um bug: *"a organização e a
hierarquia da informação no notch não acompanha o usuário — parece uma coisa
fixa da qual ele que precisa se curvar."* Terminou com **v0.14.0** publicada,
depois de um desvio pro ícone do app.

## O que foi feito

**O card aberto virou uma lista ordenada + um índice de foco.** Antes ele
empilhava tudo que existia numa ordem hardcoded (pomodoro > espelho > shelf >
atividade > música), com a altura somada à mão por constantes combinatórias e
**três** mecanismos de navegação concorrentes: abas com pontinhos, cortina do
histórico e swipe. Agora a seção em foco ocupa o card e declara a própria
altura; as outras viram ícones no rodapé, com sinal vivo mínimo (anel de
progresso, contagem, ponto de tocando).

A ordem sai de três camadas: base do usuário (arrastável em Ajustes › Notch),
filtro de conteúdo, e promoção por **evento de transição** nos últimos 10 s —
congelada no instante da abertura, pra nada pular debaixo do cursor.

**A distinção evento × tique é o coração da feature, e quase passou batido.**
O spec original dizia "seção que mudou nos últimos 10 s sobe". A pesquisa de
viabilidade derrubou isso: `PomodoroState.remaining` muda a cada segundo e o
`MediaController` publica posição continuamente — "mudou" deixaria os dois
permanentemente promovidos e a regra degeneraria em "pomodoro sempre no topo".
Virou uma tabela fechada de transições por seção, com `tools/eventoscheck.swift`
provando por mutation testing que cada guarda tem seu matador.

**Antes disso, o ícone.** O app usava um ícone que não conversava com o site, e
a barra de menus não tinha ícone nenhum — era o caractere `◐` no título do
`NSStatusItem`. Os dois viraram a silhueta do notch, que é a marca real do
site (o `favicon.svg` de lá era o logo padrão do Astro, nunca trocado — também
corrigido, no repo `knobler-site`). `tools/makeicon.swift` gera o `.icns` do
vetor. Dois aprendizados: a arte precisa **sangrar até a borda** do canvas,
senão o macOS 26 compõe tudo dentro de uma moldura clara dele (a "borda
gigante"); e o ícone da barra é desenhado em runtime como `NSImage` template,
sem asset novo.

## Validação

- `./tools/check.sh` → **18 checks** (era 16; a branch somou `sectionordercheck`
  e `eventoscheck`).
- `./tools/snapshot.sh` → 53 PNGs, cenários reescritos no eixo "qual seção em
  foco". 49 byte-idênticos entre rodadas (recontado, não estimado).
- Gesto medido no app real via `CGEvent.postToPid(_:)` — inclusive a folga de
  16 pt, com controle negativo.
- Ícone conferido lendo o que o **sistema** compõe (`NSWorkspace.icon(forFile:)`
  do app instalado), não o PNG de origem.

O processo foi SDD: 7 tasks, cada uma com implementador e revisor próprios. A
revisão pegou um **Critical** (ligar a nota abria o card na seção errada *e* o
app tomava a janela-chave sem campo focado — teclas engolidas em silêncio) e
três Important, entre eles um `focoPendente` que sequestrava a abertura
seguinte e travava a promoção pela sessão inteira. Um "Important" era **falso
positivo** e o implementador provou com repro: `@Published` torna a propriedade
computada, então `didSet` **reentra** — ao contrário da regra que vale pra
propriedade armazenada.

## Pendências e followups

- **`docs/images/expanded-shelf.png` é anterior à faixa** e pede recaptura
  manual no app rodando (as miniaturas dependem do `QLThumbnailGenerator`, que
  não renderiza offscreen). Já anotado na própria página.
- **`fatiaDoCiclo` reimplementa `Pomodoro.duration(of:config:)`** e ignora o
  `configProvider` injetado. Trocar o `switch` pela chamada mata a duplicação
  sem mudar contrato.
- **`zoneWidth` do scroll fechado (400) segue literal** — o aberto já deriva de
  `NotchGesture.larguraDoCard + 2×folgaDeHover`.
- **Digitar na nota nunca foi testado no app rodando** (painel `nonactivating`,
  `keystroke` do System Events vai pro app da frente). É o único ponto da
  feature cuja garantia é leitura de código, e é justamente o caminho da perda
  silenciosa de teclas — vale um teste manual humano.
- O app em `/Applications` pode estar num build Debug desta sessão. `brew
  upgrade knobler` pra ficar com a release; a assinatura muda e o TCC ancora a
  Acessibilidade no cdhash, então o ditado pode pedir permissão de novo.

# 🏁 SESSÃO 2026-07-29 (tarde) — o crash em Mac novo e a conversa que abria no topo

Sessão curta e reativa: dois bugs relatados de fora, dois releases publicados
(**v0.13.1** e **v0.13.2**). O primeiro era grave — o app não abria em nenhuma
máquina limpa desde sempre.

## O que foi feito

**v0.13.1 — o app morria no launch em todo Mac que não fosse este.** Relato:
"crasha na hora que abre". O crash log entregou a resposta em uma linha:
`"termination": {"namespace":"TCC", ...}` pedindo
`NSBluetoothAlwaysUsageDescription`. O `BluetoothMonitor` registra
`IOBluetoothDevice.register` no startup (`KnoblerApp.swift:462`, e
`airpodsNotch` tem default `true`), o TCC pede a permissão, não acha a chave no
`Info.plist` e chama `__TCC_CRASHING_DUE_TO_PRIVACY_VIOLATION__` — `abort`, não
erro recuperável. Fix: a chave em `project.yml`.

**Por que era invisível aqui.** O TCC só aborta no **primeiro** pedido. Esta
máquina já tinha a decisão gravada, então o caminho fatal nunca era percorrido —
o bug era 100% reproduzível lá fora e 0% aqui. Nenhum gate pegaria: não é
compilação, não é lógica, é uma chave de plist ausente exercitada só por TCC
virgem.

**v0.13.2 — a conversa abria no topo.** O `ScrollView` de `MessagesView.swift`
não tinha âncora, então nascia no histórico mais antigo e obrigava a rolar até
o fim toda vez. `.defaultScrollAnchor(.bottom)` (macOS 14.0+, dentro do target)
resolve abertura e mensagem nova de uma vez — sem `ScrollViewReader`, `id` ou
`onChange`.

**Documentação.** O `README.md` afirmava *"não pede Bluetooth"* e o caveat do
cask dizia o mesmo — a premissa errada que manteve a chave fora do plist.
Corrigidos os dois, mais `docs/airpods.md` (texto real do prompt),
`docs/messages.md` (âncora da conversa) e uma seção nova em
`docs/troubleshooting.md` pro sintoma "o app fecha sozinho ao abrir".

## Validação

`tools/check.sh` **16 ok**. Build Release limpo nos dois releases.

O fix do Bluetooth foi validado **com controle**, não por leitura de código:

| | TCC | Build | Resultado |
|---|---|---|---|
| A | Bluetooth resetado | v0.13.0 | morreu, `namespace: TCC`, assinatura idêntica à relatada |
| B | Bluetooth resetado | com a chave | vivo |
| C | 9 serviços resetados (tudo menos Acessibilidade) | com a chave | vivo 30 s, sem crash log novo |

`tccutil reset <Serviço> com.zoi.knobler` é o único jeito de simular Mac limpo
sem ter um. O serviço chama-se **`BluetoothAlways`**, não `Bluetooth`. O zip
publicado da 0.13.1 foi baixado e conferido: sha256 bate com o cask e a chave
está no `Info.plist` de dentro.

O fix da conversa **não tem validação automatizada** — `ScrollView` não
renderiza no harness de snapshot (`NSScrollView` por baixo, área preta) e a
conversa exige um peer real na rede. Confirmado só no app, pelo usuário.

## Pendências e followups

- **`Permission` não lista Bluetooth** (`Permissions.swift:27`). O painel
  Ajustes → Permissões mostra 7 permissões e o app usa 8 — a de Bluetooth não
  tem linha nem estado. As docs já foram corrigidas; falta o código.
- **Hipótese descartada, registrada pra não voltar:** o `codeSigningTrustLevel:
  4294967295` do crash log **não** indica problema de assinatura. É o normal de
  app não-notarizado com quarentena removida, e não impede o launch. O primeiro
  palpite da sessão (cert self-signed) estava errado.
- Notarização segue não feita — `release.sh` já tem o caminho pronto
  (`KNOBLER_NOTARY_PROFILE`), falta o Apple Developer Program.

# 🏁 SESSÃO 2026-07-29 (fim de manhã) — crítica de UX da nota rápida e os quatro fixes

Sessão de auditoria, não de feature. `/impeccable critique` na nota rápida
entregue de manhã deu **15/40 (Poor)** — nota concentrada em segurança do dado
e controle, não em aparência (visualmente a feature já estava dentro do
DESIGN.md). Quatro dos cinco achados foram fechados; o quinto virou brief.

## O que foi feito

Tudo em `fix/nota-rapida-ux` (`3d61617`), **não mergeado em `master`**.

**P0 — a tecla ia pro app errado.** `mode` prioriza `.notification`/`.hud`
acima de `.music`. Quando uma delas entrava, o `TextEditor` saía da árvore, o
`.onDisappear` zerava o foco, `keyboardAllowed` caía e `KnoblerApp.swift:815`
chamava `panel.resignKey()`. As teclas seguintes iam pro app frontmost, sem
sinal nenhum, por até 5 s — e depois o `.onAppear` roubava o foco de volta no
meio da palavra. Agora `typingNote` vence as duas no `mode`. **Esconder pelo
`mode` não bastava**: o auto-dismiss de 5 s correria invisível e a notificação
morreria sem ninguém ver, então ela também passou a ser enfileirada, com
`resumePendingNotifications()` no fim da digitação.

**P1 — desligar apagava sem volta**, por três caminhos (menu, monitor dono
desconectado, quit). O `didSet` de `active` copia pro `NSPasteboard` antes de
zerar; nota vazia ou só com espaço não encosta no clipboard.
`applicationWillTerminate` desliga a nota pra cobrir o quit.

**P1 — os pontinhos de página mentiam.** Ficavam visíveis e clicáveis com a
nota aberta, mudando `vm.tab` por baixo do campo: o ponto de Mensagens acendia
numa tela que seguia mostrando a nota. Saíram, e o eixo horizontal do gesto
ficou de fora na tela dona (card fechado ainda pula faixa).

**P2 — nem o campo vazio nem a nota cheia se anunciavam.** Placeholder no campo
e ponto de 4 pt na asa do notch fechado.

## Validação

`tools/check.sh` **16 ok** (o `quicknotecheck` é novo — cobre copiar-antes-de-
apagar, os dois casos de nota vazia, `hosted(by:)` e `typing(on:)`; validado por
mutação: tirando a chamada do stash, o gate quebra na asserção certa).
`tools/snapshot.sh` **62 PNGs**, exit 0 — o cenário `closed-note` é novo.

**O screenshot manual achou dois bugs que o harness nunca pegaria** (o campo é
um `ScrollView`): uma barra de rolagem do sistema parada dentro do card mesmo
vazio, e o placeholder 8 pt abaixo de onde a primeira letra nasce — pularia na
primeira tecla. Os dois só apareceram no app rodando de verdade.

## Pendências e followups

- **Branch não mergeada e não decidida.** `fix/nota-rapida-ux` está local e
  pushada; falta merge em `master` ou PR.
- **Brief do caminho de entrada rápido aguarda OK.** `/impeccable shape`
  produziu o brief completo (atalho global configurável + puxão longo pra cima +
  alcinha no topo, os três confirmados pelo usuário). **A única questão aberta é
  o blink**: com o card aberto, chegar a −120 passa antes por −24, que fecha.
  Recomendação registrada: gesto pra cima só liga a nota a partir do card
  **fechado**, onde −24 é no-op. Nada disso foi implementado.
- **Restos da crítica não atacados**: puxão longo pra baixo com a nota ligada é
  gesto morto (não abre a cortina, correto, mas não dá feedback nenhum);
  `noteEditorHeight` fixo em 120 sem indicação de que há texto acima; sem
  limite de tamanho no colar.
- **Mensagem recebida (`.message`) ainda interrompe a digitação** — ficou fora
  do escopo do P0 de propósito (tem campo de teclado próprio), mas segue sendo
  vetor de tecla no app errado.

---

# 🏁 SESSÃO 2026-07-29 (manhã) — histórico de notificações + nota rápida, **v0.13.0 publicada**

Duas features do `IDEIAS.md` entregues juntas porque dividem o mesmo pedaço de
tela: o card expandido do notch. Ciclo completo — brainstorm, spec, plano, nove
tasks em TDD com subagentes, review de branch inteira, release.

## O que foi feito

**Histórico das últimas 24 h** (`docs/notifications.md`). Tudo que virou card
entra num `NotificationHistory` singleton em memória: banner do sistema, card de
webhook, lembrete disparado, fim de fase do Pomodoro e conta-gotas. Abre com um
**puxão longo pra baixo numa passada só** — ~24 pt abre o card, ~120 pt no mesmo
gesto entra na cortina. Fechar é tirar o mouse, **não** é gesto: assim o eixo
vertical fica livre pra lista rolar de verdade, inércia inclusive.

**Nota rápida** (`docs/nota-rapida.md`). Interruptor no menu da barra liga um
`TextEditor` que toma o card. Enquanto o campo tem foco, o hover-out não recolhe
— digitar nunca é interrompido. Esc solta o foco (explicitamente, via
`onExitCommand`; o padrão do SwiftUI não garante isso). Desligar apaga.

## As três decisões que valem lembrar

| Decisão | Por quê |
|---|---|
| Gesto vertical virou **função pura do acumulado** | Menos código que o `scrollActed` que existia, e recuar dentro do mesmo gesto passou a desfazer de graça |
| Nada em disco, nas duas | Notificação e nota são efêmeras por natureza. **A justificativa antiga era falsa**: `NotchNotification` não carrega `NSImage` nem `AXUIElement` (o `AXUIElement` mora no interceptor, indexado por `actionToken`) |
| A nota tem **uma tela dona** (`hostDisplayID`) | Sem dono, ligar expandia todos os monitores sem nada recolhê-los, e as N cópias da `NotchView` disputavam foco escrevendo no mesmo `editing` |

## O que só a review de branch inteira pegou

Nenhuma review por task podia ver, e é o padrão que vale carregar pra próxima
vez: **cada task estava certa isolada; o defeito morava na costura.**

- **`currentSize` nunca aprendeu sobre os dois estados novos.** A cortina
  desenhava ~325 pt num quadro de ~176 pt e o SwiftUI centraliza o excedente:
  as notificações **mais recentes** ficavam acima da borda da tela e o cursor
  descendo na lista caía fora do hover, fechando o card. O
  `expanded-history-empty.png` já mostrava isso e ninguém tinha lido o PNG.
- **Lembrete e Pomodoro construíam a `NotchNotification` dentro do `forEach`
  das telas** — `id` é `let id = UUID()`, então cada monitor gerava uma linha
  no histórico. Os outros quatro call sites já construíam fora do laço.
- **Rodinha de mouse comum nunca emite `.began`**, então o acumulador nunca
  zerava: cruzava 120 sozinho e a cortina virava um beco sem saída.

Três defeitos foram **do plano**, não de quem implementou: a guarda de diagonal
(`|Δy| > |Δx| × 1,5`) que sumiu na reescrita, a inércia engolida antes de chegar
na lista, e a justificativa falsa acima.

## Validação

- `./tools/check.sh`: **15 checks** (`historycheck` novo — store, gesto, teto de
  300, `isGestureStart`). Os asserts do gesto foram conferidos com **controle
  negativo**: removendo a guarda, o assert falha.
- Release: build Release + `satisfies its Designated Requirement`, v0.13.0 no
  GitHub Releases e no cask.

## Pendências e followups

- **Nada foi exercitado num trackpad de verdade.** Todo o comportamento de gesto
  e foco é verificado só por leitura de código. O roteiro de 15 itens saiu na
  conversa da sessão; os checklists por task ficaram em `.superpowers/sdd/` (que
  é gitignored — se sumir, o roteiro se perde).
- **Dois screenshots faltando**: `docs/nota-rapida.md` e a seção do histórico
  estão com `<!-- TODO screenshot -->`. Precisam do app rodando.
- **`ScrollView` não renderiza offscreen** — descoberto aqui, já no `CLAUDE.md`.
  Por isso o cenário de histórico populado saiu do harness (PNG preto é gate
  falso, pior que gate nenhum).
- **Quatro PNGs do snapshot não são determinísticos** (`closed-music`,
  `closed-music-external`, `expanded-activity-only`, `update-installing`): mudam
  de hash a cada rodada sem mudança de código. Neles o harness não detecta
  regressão. Está no `CLAUDE.md` e no README.

---

# 🏁 SESSÃO 2026-07-29 (madrugada, 4ª) — pendências fechadas + **v0.12.0 publicada**

Sessão de pendência, não de feature nova: das cinco abertas no topo do handoff
anterior, **três fecharam** — duas com código, uma só com teste. As duas que
sobraram dependem de coisa que não está nesta mesa.

## O que foi feito

**1. O adiamento do lembrete sobrevive ao restart** (`aa65f8d`). O `ScheduleEngine`
ganhou um `snoozed: [UUID: Date]` espelhado no UserDefaults: `snooze()` grava,
`init` lê, e o primeiro `tick()` depois do restart semeia o `nextFire` a partir
dele. Vencido (ou lembrete apagado), o adiamento some sozinho — continua valendo
uma vez só.

O hash do schedule **não** é persistido junto de propósito: `hashValue` é
randomizado por processo e não sobreviveria ao restart de qualquer jeito. O
preço é editar o horário com um adiamento no ar mantendo o adiamento; está
comentado no código.

**2. Tabela, imagem embutida e regra horizontal no Markdown → PDF** (`151c5c7`).
As três lacunas que o conversor carregava desde que nasceu.

| Peça | Como |
|---|---|
| Paginação | saiu do **CoreText** e foi pro **TextKit** — um `NSTextContainer` por página |
| Tabela | célula da mesma linha vira `\t`, um tab stop por coluna, alinhamento `:---`/`---:` respeitado |
| Imagem | `run.imageURL` resolvido contra a pasta do `.md` → `NSTextAttachment` reduzido pra caber |
| Régua | o "⸻" do parser repetido até a caixa, com `kern` negativo |

A troca de motor foi o nó: era o `CTFramesetter` que ignorava anexo e tab stop.
`NSLayoutManager` dá os dois de graça e custa menos código que a alternativa
(`CTRunDelegate` reservando espaço + desenho manual).

## As duas descobertas que só o olho pegou

Ambas saíram de rasterizar o PDF e **olhar**, não de teste passando.

- **A citação saía invisível.** O cinza vinha de `.secondaryLabelColor` — cor
  dinâmica, que resolve pela aparência do sistema e no modo escuro vira branco.
  Em papel branco, nada. Bug que já existia desde a 0.11.0 e nenhum assert
  pegaria. Agora é tinta fixa (`quoteGray`), com assert de brilho no self-check.
  Foi ele também que escondeu a régua na primeira tentativa e me fez trocar o
  traço por um tab sublinhado antes de achar a causa real.
- **O parser omite célula vazia.** `| Total | | 50,50 |` não gera run pra célula
  do meio, então um tab por run puxava o valor pra coluna errada. O contador de
  coluna virou explícito (`tableCell(intent)`).

**3. `Compartilhar…` (menu nativo)** — fechada sem código: exercitada ao vivo,
o menu abre e envia. O plano B (`NSSharingService.sharingServices(forItems:)`)
não foi preciso.

## Validação

- `./tools/check.sh`: **14 checks**. `reminderscheck` ganhou o caso do restart
  (engine A adia, engine B com `nextFire` zerado dispara na hora certa, engine C
  confirma que o adiamento vencido não ressuscita); `documentconvertercheck`
  ganhou três (tabela + régua + brilho da tinta; imagem com anexo medido e
  caminho quebrado caindo no alt).
- **PDF real rasterizado e conferido a olho** — foi o que achou os dois bugs
  acima. Vale repetir o hábito: `DocumentConverter.pngPages(fromPDF:)` num md de
  exemplo e ler o PNG.
- Release: build Release + `satisfies its Designated Requirement`, v0.12.0 no
  GitHub Releases e no cask.

## Pendências e followups

Sobraram as duas de bloqueio externo — nenhuma depende de código:

- **Aceitar/Recusar espelhado nunca foi exercitado** — precisa de um AirDrop
  vindo de **outro Apple ID**. Entre dispositivos do mesmo ID o macOS aceita
  sozinho e esse par de botões nem aparece.
- **Sem notarização**: `KNOBLER_NOTARY_PROFILE` espera uma conta Apple Developer
  paga. A 0.12.0 saiu com o cert local; o cask remove a quarentena no install e
  os caveats explicam.

Ideias que a sessão deixou registradas em `docs/IDEIAS.md`: preview da conversão
(hoje é às cegas, sem escolher qualidade/resolução).

---

# 🆕 SESSÃO 2026-07-29 (madrugada, 3ª) — adiar lembrete + **v0.11.0 publicada**

Sessão curta de uma feature só. O `[Unreleased]` que a sessão anterior deixou
acumulado **saiu**: `v0.11.0` está no GitHub Releases e no cask.

## O que foi feito

**Adiar lembrete direto no card do notch** (`1a29ef4`). Quando um lembrete
dispara, o card traz **Adiar 5 min** e **30 min**.

O diff é pequeno porque quase tudo já existia — a UI de botão no card
(`actionTitles` / `actionToken`) tinha sido escrita na sessão anterior pro
AirDrop e **só rodava em alerta de Apple ID alheio**. Agora roda todo dia.

| Peça | Onde |
|---|---|
| `snooze(_:minutes:now:)` — empurra o `nextFire` sem tocar na agenda | `Reminders.swift` (engine) |
| `onFire` manda `actionToken: r.id` + os dois títulos | `KnoblerApp.swift:336` |
| Roteamento por token: lembrete → snooze, resto → interceptor | `KnoblerApp.swift:749` |
| `snoozeOptions` (títulos + minutos, fonte única) | `KnoblerApp.swift:66` |

Duas decisões que valem lembrar:

- **O adiamento vence uma vez só.** Ao disparar, o tick recomputa a agenda
  normal — um diário adiado pras 09:05 volta pras 09:00 no dia seguinte.
- **Um `oneShot` precisa ser religado no snooze.** O `onFire` já o desligou
  quando o card apareceu, e o tick pula item desabilitado — sem religar, o
  adiamento nunca venceria. Custou uma linha, mas é invisível na leitura.

## A descoberta que matou a feature que eu ia fazer

A recomendação inicial era **notificações de app com ações** (Responder,
Marcar como lida) — parecia barata, já que a infra de botão existe. Não é.

Acionar a ação exige o `AXUIElement` do banner **vivo**, e o interceptor fecha
o banner justamente pra o notch substituí-lo. Ou o balão do sistema fica na
tela duplicado com o card, ou não há ação — não existe meio-termo via AX.
Anotado com ⚠️ em `docs/IDEIAS.md` pra não custar essa descoberta de novo.

Trocamos pelo snooze, que é a mesma UI sem nenhum AX no caminho.

## Validação

- `./tools/check.sh`: **14 checks** (eram 13). O `reminderscheck` entrou —
  o `-D REMINDERS_SELFCHECK` existia desde sempre no `Reminders.swift` mas
  **nunca rodava no CI**. O novo assert cobre adiar → não dispara antes →
  dispara na hora → não redispara → agenda diária intacta no dia seguinte.
- **Ao vivo, ciclo completo** (lembrete de teste via `defaults write`, removido
  depois): card com os dois botões às 00:14 · clique roteou pro snooze
  (o `enabled` do `oneShot` voltou a `true` no plist, coisa que **só** o snooze
  faz) às 00:16 · card reapareceu às **00:21**, exatos 5 min depois.
- Release: build Release + `satisfies its Designated Requirement` (cert local
  `Knobler Local Signing`, então o TCC não revoga a Acessibilidade).

## Pendências e followups

Novas desta sessão:

- **O adiamento mora na memória.** Reiniciar o Knobler antes de vencer devolve
  o lembrete ao horário original. Registrado no IDEIAS; persistir junto do
  `Reminder` resolveria. ✅ **Fechada na sessão de 29/07 (madrugada, 4ª).**

Herdadas e ainda abertas:

- ~~**`Compartilhar…` (menu nativo) não teve confirmação visual**~~ — exercitado
  ao vivo em 29/07: o menu abre e envia. Fechada sem código.
- **Aceitar/Recusar espelhado nunca foi exercitado** — precisa de um AirDrop de
  Apple ID diferente.
- ~~**Markdown → PDF ignora tabela, imagem embutida e regra horizontal.**~~ ✅
  **Fechada na sessão de 29/07 (madrugada, 4ª).**
- **Sem notarização**: `KNOBLER_NOTARY_PROFILE` não estava setado, então a
  0.11.0 saiu com o cert local. Quem instalar fora do cask vê o Gatekeeper.

---
