# Troubleshooting

Comece pelo diagnóstico barato antes de reinstalar:

```bash
curl -sS http://127.0.0.1:4477/status | jq .
/Applications/Knobler.app/Contents/MacOS/Knobler --selfcheck
```

O endpoint `/status` só existe quando a API local está ligada em Ajustes →
Notch. Os campos variam por integração; normalmente incluem `notches`,
`player`, `dictation`, `ask`, `micInUse` e `lanMessaging`.

## O app fecha sozinho ao abrir (versões até a 0.13.0)

Sintoma: o ícone aparece por um instante e o app morre, sempre, em Mac onde ele
nunca rodou antes. Em quem já usava, não acontece.

Causa: o monitor de AirPods pedia permissão de Bluetooth sem a chave
`NSBluetoothAlwaysUsageDescription` no `Info.plist`, e o macOS aborta o processo
nesse caso — só no **primeiro** pedido, por isso máquinas antigas escapavam.

Correção: atualize para a **0.13.1** ou posterior.

```bash
brew update && brew upgrade knobler
```

Pra confirmar que era isso, o motivo fica no relatório de falha:

```bash
ls -t ~/Library/Logs/DiagnosticReports/Knobler* | head -1 | xargs grep -o '"namespace":"TCC"[^]]*]'
```

## O Knobler não aparece na lista do Ajustes do Sistema

Sintoma: instalação nova, o usuário abre Ajustes do Sistema → Privacidade e
Segurança → Acessibilidade (ou Microfone, Câmera…) e o Knobler simplesmente não
está lá para ser marcado.

Comece pelo diagnóstico — ele roda sem UI e serve para pedir por mensagem a quem
está com o problema:

```bash
/Applications/Knobler.app/Contents/MacOS/Knobler --permissoes
```

A linha `instalação:` é a que decide:

| Leitura | Causa | Correção |
| --- | --- | --- |
| `ok` | A instalação está sadia; ver abaixo | Adicionar à mão pelo **+** |
| `translocado` | O Gatekeeper está rodando uma cópia temporária read-only; a entrada do TCC aponta pra um caminho fantasma | Mover para `/Applications`, `xattr -dr com.apple.quarantine`, reabrir |
| `emQuarentena` | Instalado pelo `.zip` sem remover a marca do Gatekeeper | `xattr -dr com.apple.quarantine /Applications/Knobler.app` |
| `foraDeApplications(...)` | Rodando do Downloads/DerivedData; a permissão gruda naquele caminho | Mover para `/Applications` e abrir de lá |

O app avisa sozinho: nesses três estados o painel **Ajustes → Permissões** abre
a cada inicialização com a causa e o passo de correção no topo.

Com a instalação sadia, a razão é outra e é do próprio macOS: **o Ajustes do
Sistema só lista um app depois que ele pede a permissão**. Como o Knobler roda
como agente (`LSUIElement`), o usuário que fechou o painel da primeira abertura
fica sem nada visível. Duas saídas, ambas no painel **Ajustes → Permissões**:

- Botão **Permitir**, na linha da Acessibilidade — reabre o diálogo do sistema
  enquanto o TCC ainda não tiver decisão gravada.
- Botão **Revelar o Knobler no Finder** — abre o Finder com o app selecionado;
  no painel do Ajustes do Sistema clique em **+** e arraste o app pra lista.

Se o Knobler aparece na lista **marcado** e mesmo assim nada funciona, a entrada
é de uma assinatura antiga: veja
[Reconceder a Acessibilidade](#reconceder-a-acessibilidade).

## Concedi a permissão e o painel continua dizendo "Sem status até usar"

Vale pra **Rede local**, **Arquivos e pastas** e **Gravação de áudio do
sistema**: o macOS não dá API pra consultar essas três, só pra usá-las. O painel
mostra *Concedida* depois que o recurso roda uma vez — não antes, por mais que o
interruptor já esteja ligado no Ajustes do Sistema.

Atalho: o botão **Verificar**, na própria linha, força esse primeiro uso na hora
(liga o Bonjour, lê a Mesa). A *Gravação de áudio do sistema* não tem o botão —
ela só se prova com um player tocando, que é quando o tap de áudio é criado.

## O countdown do calendário não aparece

Desde a 0.19.0 o Knobler **não pede** a permissão de Calendário na abertura (o
balão caía por cima da janela de boas-vindas). Quem pede é **Ajustes →
Permissões**, botão *Permitir* na linha *Calendários*. Concedida, o countdown
liga em segundos — sem reabrir o app.

## O app está aberto, mas o notch não aparece

1. Confirme se o processo está ativo:

   ```bash
   pgrep -fl Knobler
   ```

2. Encerre e abra a cópia instalada:

   ```bash
   killall Knobler 2>/dev/null || true
   open -a /Applications/Knobler.app
   ```

3. Em monitores externos, confirme que a ilha simulada está posicionada no
   monitor esperado e que o app não está em modo de tela cheia exclusivo.

## API local indisponível

- Ligue Ajustes → Notch → API local.
- Confira se outra aplicação ocupou a porta:

  ```bash
  lsof -nP -iTCP:4477 -sTCP:LISTEN
  ```

- Teste o endpoint mínimo:

  ```bash
  curl -i -X POST 127.0.0.1:4477/notify \
    -H 'Content-Type: application/json' \
    -d '{"title":"teste"}'
  ```

O servidor escuta apenas loopback. Para scripts, `tools/knobler` retorna erro
quando a API está desligada; isso é intencional para que o caller possa decidir
se deve usar `|| true`.

## Ask não aparece no notch

1. Confirme a API:

   ```bash
   curl -sS http://127.0.0.1:4477/status | jq '.ask'
   ```

2. Para Claude Code, instale o hook e inicie uma nova sessão:

   ```bash
   ./tools/claude-hook/install.sh
   ```

3. O hook falha aberto: se o Knobler estiver desligado, cancelado ou sem
   resposta, a pergunta deve continuar no terminal.

4. Perguntas pendentes expiram em 15 minutos. Ao desligar a API, o app limpa a
   apresentação e invalida callbacks antigos.

Para testar sem Claude Code, use a CLI:

```bash
./tools/knobler ask "Continuar?" "Sim" "Não"
```

## Aprovação do Codex não aparece no notch

Rode o gate — ele diz em qual etapa parou:

```bash
node tools/codex-integration-check.mjs
```

| Saída | Significado |
|---|---|
| `capability: …` | esta versão do Codex não expõe os três pedidos de aprovação |
| `daemon indisponível (instalação não-standalone)` | app e IDE ficam com aprovação nativa; só a CLI pela ponte espelha |
| `OK` | a ponte funciona — o pedido veio de uma sessão fora dela |

A causa mais comum do último caso: a sessão foi aberta com `codex` direto. Só o
que passa por `tools/knobler codex bridge` é espelhado. Uma linha em stderr
começando com `codex bridge:` explica cada recusa (token ausente, API fora,
sem resposta a tempo) — em todas elas a aprovação nativa continua valendo, e
nenhuma decisão é inventada.

## Ditado não inicia

Sintoma típico: segurar a ⌥ direita não faz absolutamente nada — sem pílula,
sem erro, sem log. O silêncio total é a assinatura de um problema de
permissão, não de um problema no ditado.

O primeiro sinal está na barra de menus: com o ditado ligado e sem
Acessibilidade, o ícone do Knobler vira **◐⚠** e o menu ganha
**⚠ Ditado precisa de Acessibilidade…**, que abre o painel direto. A marca some
sozinha assim que a permissão é concedida (a checagem roda a cada 3s).

Para o diagnóstico completo, comece pelo `/status`, que separa as duas metades
do fluxo:

```bash
curl -sS http://127.0.0.1:4477/status | jq '{axTrusted, tapExists, tapEnabled, dictation, keyLog}'
```

| Leitura | Significado |
| --- | --- |
| `axTrusted: false` | Sem Acessibilidade — **é a causa em quase todos os casos** |
| `tapExists`/`tapEnabled: false` | O `CGEventTap` não existe; nenhuma tecla chega ao app |
| `keyLog: []` após teclar | Confirma que o tap está morto, não que o ditado está |
| `dictation.enabled: false` | O recurso está desligado em Ajustes → Ditado |
| `dictation.modelReady: false` | O Parakeet ainda está baixando ou falhou |

Se `dictation` está `enabled: true` e `modelReady: true` mas `axTrusted` é
`false`, o ditado está sadio e o problema é só a permissão: sem ela o
`CGEventTap` (`VolumeHUD.swift:142`) nem é criado, então o `flagsChanged` da
⌥ direita nunca chega ao `rightOptionChanged`.

### Reconceder a Acessibilidade

A UI pode mostrar o Knobler **marcado** enquanto a concessão não vale nada: o
TCC ancora a permissão na assinatura do binário e guarda entradas antigas.
Nesse estado, desmarcar e marcar de novo **não resolve** — é preciso apagar as
entradas:

```bash
tccutil reset Accessibility com.zoi.knobler
killall Knobler; open -a Knobler
```

Ao reabrir, o app dispara o prompt do sistema (`Dictation.swift:277`). Conceda
por ele, ou adicione `/Applications/Knobler.app` à lista com o botão **+**
(remova a entrada antiga com **−** antes, se ainda estiver lá).

Não é preciso reiniciar de novo depois de conceder: o `checkTapHealth`
(`VolumeHUD.swift:107`) roda em timer, percebe a mudança e recria o tap
sozinho. Confirme:

```bash
curl -sS http://127.0.0.1:4477/status | jq '{axTrusted, tapEnabled}'
```

Os dois precisam ler `true`.

### Por que isso volta a acontecer

O TCC casa a concessão contra a assinatura de código do binário. Se a
assinatura muda, a permissão anterior deixa de valer. Isso acontecia quando a
identidade mudava entre uma instalação e outra — o `xcodebuild` assinava com a
identidade de desenvolvimento do Xcode e o `tools/release.sh` com
`Knobler Local Signing`. Hoje as duas vias usam `Knobler Local Signing`, mas
**uma** troca ainda acontece ao instalar por cima de uma cópia antiga, assinada
com a identidade anterior. Veja
[Instalação local do build](development.md#instalação-local-do-build).

Verifique com que identidade a cópia instalada está assinada:

```bash
codesign -dv --verbose=2 /Applications/Knobler.app 2>&1 | grep Authority
```

Também confira o Microfone em Ajustes do Sistema → Privacidade e Segurança →
Microfone. A falta dele é um sintoma diferente: o ditado *começa* e falha com
a pílula "Sem acesso ao microfone".

## Formatação local da transcrição não funciona

- Confirme que Ollama ou LM Studio está rodando.
- Confirme endpoint e modelo em Ajustes → Ditado.
- Desative temporariamente “Formatar transcrição” para separar o problema do
  motor de transcrição.

A falha do formatter deve devolver o transcript bruto; ela não deve impedir o
  ditado.

## Câmera ou espelho não aparece

- Dê acesso à Câmera.
- O espelho só tem seção própria depois de ligado: fixe **Espelho** em
  Ajustes › Notch pra chegar nele sem depender da API local.
- **"Câmera indisponível"** no lugar do preview = abrir o dispositivo falhou:
  nenhuma webcam, o USB caiu, ou outro app está com a câmera. Confira
  `GET /status` (`mirrorFailed: true`, `cameraDevice`) e o console
  (`knobler mirror: câmera indisponível`). Fechar e reabrir o espelho tenta de
  novo — a preferência é relida a cada abertura.
- "Ligando a câmera…" parado por mais de alguns segundos, **sem** virar
  "Câmera indisponível", é a câmera acordando devagar (Continuity costuma
  demorar mais).
- Abra o espelho e escolha a câmera pelo menu quando houver mais de uma.
- Se um dispositivo USB sumiu, volte para “Automática”; a preferência usa
  `uniqueID`, não índice.

## Webhook não entrega notificações

- Ligue o recurso e confirme que o perfil não foi rotacionado ou apagado.
- Verifique se o processo do relay está disponível e se o token está no
  Keychain.
- Use o diagnóstico do app e os logs do processo; não cole tokens em issues.

## Nunca recebi um aviso do desenvolvedor

Provavelmente não há nenhum publicado — o canal é raro por natureza. Antes de
suspeitar de defeito:

- O app só consulta **uma vez por dia** (e ~45 s depois de abrir). Um aviso
  publicado agora pode levar até 24 h.
- Cada aviso aparece **uma vez só**. Se você já o viu, ele não volta — o
  registro fica em `avisos.vistos`.
- Um aviso pode ser dirigido a uma **faixa de versão**: "atualize, a 0.19 tem um
  bug" não é enviado a quem já está na 0.20.
- Com **Silenciar durante reuniões** ativo e uma reunião acontecendo, o aviso
  foi direto pro Histórico — role a seção Histórico do card.
- Se o interruptor **Ajustes › Geral › Avisos do desenvolvedor** está desligado,
  só os críticos chegam.

Ver [Avisos do desenvolvedor](avisos.md).

## Logs úteis

```bash
log stream --style compact --info \
  --predicate 'process == "Knobler"'
```

Para um relatório de bug, inclua versão do app, macOS, feature afetada,
resultado de `/status`, comando reproduzível e se o problema ocorre em um ou
em todos os monitores. Remova tokens, nomes, áudio, imagens e textos privados.
