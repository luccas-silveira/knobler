# WhatsApp no notch — duas contas, conversa completa

## Objetivo

Ligar as duas contas de WhatsApp do Luccas (4143, Business, e 8292, pessoal)
ao Knobler, com conversa completa no notch: ler e responder texto, foto, vídeo,
documento, áudio, grupos, reações e citação.

Sucesso: mensagem chegando em qualquer das duas contas vira card no notch em
até 2 segundos, e tudo listado acima funciona sem abrir o celular nem o
WhatsApp Desktop.

## Público e alcance

Só o Luccas. A feature depende de uma ponte local que só ele roda; quem
instala o Knobler pelo brew não vê nada dela (nem na vitrine de plugins).

## Restrições

- Sai numa versão MINOR. A página de novidades dessa versão fala do resto da
  versão, não do WhatsApp; o WhatsApp entra como uma linha discreta no
  `CHANGELOG.md` (integração opcional com ponte local, invisível sem ela).

- Conexão não oficial (whatsmeow, multi-device). Risco de banimento aceito
  pelo dono; nada que pareça automação em massa.
- Deployment target do app segue macOS 14.2.
- O MCP do Claude (`whatsapp-mcp-server`) continua funcionando durante e
  depois da mudança.
- A ponte escuta só em `127.0.0.1`.

## Arquitetura

Duas partes, em dois repositórios.

**Ponte** (`~/Code/whatsapp-mcp/whatsapp-bridge`, Go, serviço do macOS
`com.whatsapp-mcp.bridge`): único ponto que fala com o WhatsApp. É a fonte da
verdade de conversas, mensagens e mídia.

**Knobler**: só cliente da ponte. Não guarda conversa em disco; mantém um
cache em memória e um cache de mídia descartável. A exceção é o Histórico de
notificações, que guarda o texto do card por 24 h, como já faz com o banner do
WhatsApp Desktop.

Com a ponte fora do ar, a seção mostra o aviso e as notificações do WhatsApp
Desktop voltam a virar card como hoje.

## Componentes

### Ponte

1. **Cofre multi-conta.** As sessões das duas contas no mesmo processo, cada
   uma com sua identidade de aparelho (um cofre de sessões só, um cliente por
   aparelho). Mensagens ficam num banco por conta: o `messages.db` atual vira
   o do 4143 sem migração, e o 8292 ganha banco e pasta de mídia próprios.
   Toda rota aceita o parâmetro de conta; sem ele, vale o 4143. O MCP lê o
   SQLite direto, então aprende a escolher o banco da conta (padrão 4143).
2. **Canal ao vivo** (WebSocket, com ping de sinal de vida). Eventos:
   mensagem nova, recibo (entregue, lido), reação, mensagem editada/apagada,
   estado da conexão de cada conta. Cada evento é gravado em disco com número
   sequencial, que sobrevive ao religar da ponte, e fica guardado alguns dias;
   o cliente pede "o que mudou desde N" ao reconectar.
3. **Rotas de leitura.** Contas e estado, conversas (com não lidas e última
   mensagem), mensagens paginadas por conversa, mídia, foto de perfil, dados
   de grupo (nome, participantes).
4. **Rotas de ação.** Texto, mídia (foto, vídeo, documento), áudio de voz,
   reação, responder citando, marcar como lida.
5. **Pareamento.** A ponte sobe e abre as rotas mesmo sem nenhuma conta
   logada; cada conta conecta, cai e religa independente da outra. Uma rota
   inicia o pareamento de conta nova e devolve o QR (que troca sozinho) e o
   estado dele até a conta conectar. A janela de pareamento fecha em cerca de
   160 s; depois disso o notch oferece gerar outro. Só QR, sem código.
   Durante a migração, nenhum processo antigo da ponte pode estar vivo com a
   mesma sessão (duas pontes derrubam uma à outra).

Autenticação: a ponte passa a exigir uma chave, guardada num arquivo
legível só pela conta do usuário (permissão 0600 numa pasta 0700, mesmo
padrão do `TokenDeAgente`), lido pela ponte, pelo Knobler e pelo MCP.
Requisição sem a chave é recusada, e também a que vem de página de navegador
(Host/Origin/Sec-Fetch-Site, como o `NotchAPIGuard`).

### Knobler

1. **Cliente da ponte.** Chamadas HTTP e o canal ao vivo, com reconexão
   sozinha e recuperação do que mudou durante a queda. Reaproveita o padrão de
   reconexão do `WebhookClient` (espera crescente com teto de 30 s e jitter,
   volta do sleep, App Nap), não a classe.
2. **Estado do WhatsApp.** Contas, conversas, mensagens, não lidas. Singleton
   injetado em todas as janelas (como `AskStore`), nunca um por monitor.
3. **Seção WhatsApp do notch.** Seletor de conta (com estado de conexão),
   lista de conversas (individuais e grupos), conversa, campo de envio com
   anexo, gravação de áudio, reação e citação. Com o campo de envio em uso,
   nenhum card (de WhatsApp ou de outro app) toma a tela: entram na fila e
   descem quando o campo perde o foco; a conversa aberta recebe a mensagem
   nova na hora. O rascunho é guardado por conversa em memória (no estado do
   WhatsApp, não na view) e sobrevive a fechar o notch. Com o campo do
   WhatsApp (seção ou card) em uso, a tecla do ditado escreve nele, como o
   destino `.ask` do ditado (`Dictation.swift:275`) já faz; a pílula do ditado
   não toma o lugar do campo.
4. **Card de chegada.** Conta, quem mandou (e o grupo, se for), prévia
   (texto ou miniatura), resposta rápida. Passa pela fila de notificação
   (`publicar`/`enqueue`): ganha fila, o silêncio em reunião e o Histórico
   (texto guardado 24 h, como o banner do WhatsApp Desktop já é hoje). O
   campo de resposta é capacidade nova desse card. Mensagens seguidas da
   mesma conversa se juntam num card só. Não desce card da conversa que está
   aberta naquela tela (a conversa aberta é estado por monitor). O card é
   montado uma vez, fora do laço por tela.
5. **Peça instalável.** Segue o sistema de plugins (`Plugin.swift`), com
   `PluginID` e `NotchSection` novos (`whatsapp`, nunca reaproveitando
   `mensagens`, que é a LAN). Nasce desinstalada em instalação nova e não é
   acrescentada a quem já migrou. Vitrine e lista de atalhos das Ações rápidas
   só a mostram quando a ponte responde com a chave certa numa rota de
   identificação — porta aberta não basta. A sondagem só roda se o arquivo
   da chave existir, então Mac sem ponte não abre conexão nenhuma.

Mais o **filtro no interceptor de notificações**: descarta o banner do
WhatsApp Desktop enquanto a ponte está conectada; deixa passar quando ela cai.
A regra mora em `NotificationRules` (Foundation pura, sem puxar o estado do
WhatsApp) e reusa a limpeza do U+200E. Ela só age com "notificações no notch"
ligado e Acessibilidade concedida, como todo o interceptor; com isso
desligado, o banner do sistema aparece junto do card. Banner cujo nome de app
a heurística não reconhece passa como hoje.

### Visual

Segue o `DESIGN.md`: hierarquia por camadas de branco, sem segunda cor de
fundo. Envio que falha não vira bolha vermelha: ícone e texto "não enviada"
em cor de estado, com "tentar de novo". Os estados de entrega usam tiques
(um, dois, dois preenchidos para lido), diferentes pela forma, não só pela
cor. Formato aprovado no mockup (`docs/vesta/mockups/2026-11-04-whatsapp/`,
variante A): largo em duas colunas, 780 pt como o card de Link, conteúdo de
360 pt de altura; coluna esquerda de 260 pt com o seletor de conta no topo e
a lista; conversa à direita. Peça em índigo do sistema, ícone próprio
(`phone.bubble.fill`, com reserva se não existir no 14.2), distinto do verde
de Mensagens LAN.

## Fluxo de dados

**Recebimento.** Celular, ponte (salva no banco da conta), canal ao vivo,
estado do Knobler. Se a conversa não está aberta naquela tela, desce o card
pela fila de notificação.

**Envio.** O Knobler chama a ação na ponte. A bolha aparece na hora como
"enviando", vira "enviada" com a confirmação, e ganha entregue e lido conforme
os recibos chegam pelo canal.

**Mídia.** Fica na ponte. O Knobler pede o arquivo só quando a bolha aparece
na tela e guarda numa pasta de cache que pode ser apagada.

**Áudio.** Tocar: o Ogg Opus recebido toca direto no AVFoundation do Mac do
dono (confirmado no macOS 27; não garantido no 14.2, o que não importa para
uso pessoal). Gravar: o Knobler grava pelo gravador que o ditado já usa
(trata fone Bluetooth e troca de dispositivo), codifica em Opus e monta ele
mesmo o envelope Ogg (cabeçalhos OpusHead/OpusTags e páginas), sem ffmpeg. A
forma de onda enviada vem do nível do microfone durante a gravação, no lugar
da onda sintética que a ponte gera hoje. A ponte só recebe o arquivo pronto e
manda como nota de voz.

**Microfone.** O silêncio de cards por "microfone ligado há 20 s" desconta o
uso do próprio Knobler (ditado e gravação de áudio). O texto de permissão do
microfone passa a falar de ditado e gravação de áudio, em termos genéricos.

**Queda do canal.** Ao reconectar, o Knobler pede à ponte os eventos desde o
último número que viu. Nenhuma mensagem some no buraco.

**Leitura.** O Knobler nunca marca como lida sozinho: nem abrir a conversa,
nem ver o card. Marca quando o usuário pede (botão) ou quando responde
naquela conversa. As não lidas zeram quando você lê no celular ou noutro
aparelho: a ponte trata o recibo de leitura da própria conta (tipos `read` e
`read-self`) e a marcação explícita de lida/não lida. A contagem inicial vem
da sincronização de histórico, que hoje a ponte ignora.

**Contatos.** Conversa que existe duas vezes (por telefone e por LID) aparece
como uma só, unida pelo mapa de LID da própria ponte.

**Presença.** A ponte nunca se anuncia como "disponível": aparelho vinculado
online faz o celular parar de receber notificação.

## Erros

- **Ponte fora do ar:** aviso na seção com o comando de religar; card volta a
  vir do WhatsApp Desktop; reconexão automática com espera crescente até
  30 s, sem travar a UI.
- **Conta deslogada** (o celular removeu o aparelho vinculado): o seletor
  marca a conta como desconectada e oferece o QR para parear de novo no
  próprio notch. A outra conta segue funcionando.
- **Envio que falha:** ícone e texto "não enviada" em cor de estado, com
  "tentar de novo". Nada é reenviado sozinho.
- **Mídia expirada no servidor:** bolha mostra "mídia indisponível" e tenta a
  recuperação pelo celular uma vez.
- **Chave errada ou ausente:** a seção diz que a chave não confere, em vez de
  "ponte fora do ar".

## Testes

**Ponte (Go):** cofre multi-conta, marca de conta nas mensagens, rotas sem
parâmetro de conta respondendo como hoje (o MCP não quebra), recorte "desde o
evento N", recusa sem chave.

**Knobler:** gate novo em `tools/check.sh` cobrindo a lógica pura sem rede:
aplicar eventos ao estado, deduplicar, ordenar conversas, contar não lidas,
transição da bolha (enviando, enviada, entregue, lida, falhou), regra do
filtro do banner do Desktop. Estados visuais (seção vazia, ponte fora, conta
desconectada, card de chegada, QR, lista, conversa) no `tools/snapshot.sh`.
Lista e conversa rolam: entram pela janela sintética que agenda, lembretes e
monitores já usam no harness, não pelo `ImageRenderer`. O estado do WhatsApp
nasce inerte (sem rede até `start`) e tem reset entre cenários no
`tools/main.swift`, para o harness nunca puxar conversa real da ponte.

**Ponta a ponta:** 4143 e 8292 um contra o outro. Mandar do 4143 para o 8292
e o card descer em até 2 segundos; responder citando, reagir, mandar foto,
documento e áudio pelo notch; conferir pelo recibo da ponte e pelo histórico
da outra conta. Exige parear o 8292 na ponte por QR uma vez (passo do
usuário).

## Pré-condições e efeitos colaterais

- A ponte tem mudanças sem commit (tipo de documento, vCard, criação de
  grupo, escuta só em 127.0.0.1) que o binário rodando já contém. Elas viram
  commit antes de qualquer mudança desta feature.
- O ícone da seção WhatsApp na faixa do rodapé mostra sinal de não lidas (a
  seção Mensagens LAN não mostra porque lá não existe "não lida").
- Foto de perfil vem da ponte por um carregador próprio com a chave: o
  `RemoteAvatarLoader` recusa http e loopback de propósito; só a miniatura e
  o cache dele são reaproveitados.
- `docs/ROADMAP.md` e `docs/IDEIAS.md` trocam a ideia antiga de WhatsApp Web
  por esta.
- Risco conhecido e aceito: relatos de aviso e banimento com clientes não
  oficiais mesmo em uso leve. O WhatsApp limita a 4 aparelhos vinculados por
  conta (a ponte ocupa um em cada) e desloga os vinculados se o celular
  ficar 14 dias sem uso.

## Fora do escopo

- Ligação de voz/vídeo, status/stories, comunidades, canais.
- Feature pública para quem instala pelo brew.
- Envio em massa ou automação de mensagens.

## Decisões do grill

- **A51, A67, A52, A66** — um banco de mensagens por conta, em vez de marca de
  conta numa tabela só. Motivo: grupo em comum faria uma conta sobrescrever a
  outra (chave da mensagem é id + conversa), e o MCP lê o SQLite direto, então
  o padrão "sem conta vale o 4143" nas rotas não o protegia. Banco separado
  dispensa migrar as mensagens existentes.
- **A57, A77, A7, A75, A76** — canal ao vivo em WebSocket, não SSE; eventos
  numerados gravados em disco. Motivo: o app já tem o padrão de reconexão
  testado em WebSocket; o leitor de linhas do macOS descarta a linha vazia que
  fecha cada evento SSE; contador em memória volta a 1 quando o launchd religa
  a ponte.
- **A8** — reconexão com teto de 30 s e jitter. Motivo: tentativa a cada
  poucos segundos por horas enche o log do sistema.
- **A1, A38, A20** — chave em arquivo 0600, não no Keychain; recusa de pedido
  vindo de navegador. Motivo: a ACL do Keychain pertence a quem gravou e a
  ponte muda de assinatura a cada build, o que trancaria a chave para os
  outros dois; loopback sozinho não barra página aberta no navegador.
- **A56, A70, A82, A85** — ponte reorganizada para subir sem conta, com conta
  caindo e religando sozinha; pareamento só por QR. Motivo: hoje o HTTP só
  sobe depois do login, o QR sai no log e uma conta deslogada fica parada sem
  avisar; o código de 8 caracteres exige informar o número e só ajuda sem
  câmera.
- **A22, A23, A2, A3, A24, A26, A21** — peça escondida até a ponte se
  identificar. Motivo: vitrine e atalhos listam tudo sem filtro, e peça nova
  nasce instalada em Mac novo; sondar só a porta daria falso positivo com
  outro serviço na 8099.
- **A4, A48** — MINOR, com a página de novidades sem o WhatsApp e uma linha
  discreta no CHANGELOG. Motivo: mantém a regra MINOR = feature sem anunciar
  na tela de todo usuário algo que só o dono usa; a página é por versão, não
  por feature.
- **A5, A30, A35, A6, A34, A33** — card pela fila de notificação, com campo
  de resposta novo, agrupamento por conversa e supressão da conversa aberta
  naquela tela. Motivo: o card da LAN é vaga única (mensagem nova apaga a
  anterior), ignora o silêncio em reunião e cobriria a conversa aberta; o
  Histórico em disco já existe hoje para o banner do Desktop.
- **A29, A31** — com o campo em uso, cards esperam na fila; rascunho por
  conversa no estado, não na view. Motivo: hoje um card qualquer tira o
  compositor da tela, a tecla seguinte vai pro app da frente e o texto some.
- **A15, A36, A37** — filtro no interceptor, regra pura em
  `NotificationRules`. Mantido o limite de só agir com o interceptor ligado.
  Motivo: no Mac do dono "notificações no notch" está ligado (padrão) e a
  Acessibilidade já é exigida pelo ditado.
- **A78, A63** — recibos de leitura da própria conta zeram as não lidas;
  contagem inicial da sincronização. Motivo: sem isso o contador do notch
  nunca zera quando você lê no celular.
- **A62** — unir conversa por telefone e por LID. Motivo: 23 contatos aparecem
  hoje como duas conversas.
- **A79** — nunca anunciar presença. Motivo: aparelho vinculado online corta a
  notificação do celular.
- **A54, A80, A81** — a ponte passa a salvar reação, edição, apagamento,
  figurinha e citação (citação só com o texto da original). Motivo: hoje tudo
  isso é descartado antes de salvar; os construtores de envio já existem na
  biblioteca.
- **A58** — mídia nomeada pelo id da mensagem. Motivo: o nome por segundo
  colide (202 pares hoje) e o download devolve o arquivo errado.
- **A65, A69** — bancos em WAL com transação imediata. Motivo: ponte, MCP e
  consultas à mão no mesmo arquivo; transação adiada devolve "locked" sem
  esperar.
- **A47** — corrigido o trecho de testes: o snapshot cobre lista e conversa
  pela janela sintética que agenda/lembretes/monitores já usam (exige sessão
  gráfica desbloqueada).
- **A71, A72, A73, A74, A64** — o Knobler empacota a nota de voz sozinho, sem
  ffmpeg; toca o Ogg recebido direto; onda real do nível do microfone. Motivo:
  o Mac grava Opus mas não Ogg, o ffmpeg não reembala o Opus da Apple sem
  recodificar e o serviço da ponte não enxerga o Homebrew no PATH; dependência
  externa que muda de lugar numa atualização é o oposto de estável.
- **A9, A41, A11, A10** — o silêncio por microfone desconta o uso do próprio
  Knobler; texto de permissão genérico; gravação reusa o gravador do ditado.
  Motivo: um áudio de mais de 20 s silenciaria os cards do próprio WhatsApp.
- **A42** — ditado escreve no campo do WhatsApp, como no Ask. Motivo: hoje a
  pílula toma o lugar do card e o texto vai pro app da frente.
- **A88, A89, A90, A98, A91, A92** — formato da seção decidido no mockup com
  as duas variantes; falha sem bolha vermelha; tiques diferentes pela forma.
  Motivo: o `DESIGN.md` proíbe segunda cor de fundo e exige que estado não
  dependa só de cor; 430 × 272 aperta grupo com mídia.
- **A19** — descartado: o cético refutou (a chave fica num arquivo que o
  usuário nunca copia nem cola, então não esbarra na decisão de não ter
  pareamento por chave).
- **A60** — commitar as mudanças soltas da ponte antes de começar. Motivo: o
  binário em uso já as contém e a feature mexe nos mesmos trechos.
- **A18** — sinal de não lidas no ícone da seção. Motivo: a LAN não tinha
  "não lida"; o WhatsApp tem.
- **A12** — carregador próprio de foto de perfil. Motivo: o atual recusa http
  e loopback por segurança, e assim deve continuar.
- **A16** — ROADMAP e IDEIAS atualizados. Motivo: a ideia registrada era
  outra (WhatsApp Web) e não envolve o ditado, que segue sem escrever em app
  terceiro.
- **A83, A84** — risco de banimento e limites de aparelho registrados como
  aceitos.
- Demais achados (A13, A14, A17, A25, A27, A28, A40, A43–A46, A86, A87, A93
  a A97) são detalhes de implementação ou referências visuais que vão para o
  mockup e o plano, sem mudar a spec.
- **Mockup** — aprovada a variante A (larga, duas colunas, 780 pt). Motivo:
  troca de conversa num clique e espaço para grupo com mídia.
