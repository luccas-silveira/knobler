# A API local quando o plugin está desligado

- map: ../map.md
- label: wayfinder:grilling
- status: closed
- assignee: claude (sessão 2026-08-04)
- blocked-by: — (003 fechado)

## Question

O `NotchAPIServer` (127.0.0.1:4477) é o diferencial do produto e tem contrato
publicado (`docs/local-api.md`) — script de terceiro depende dele. Se uma feature
com rota própria vira plugin desinstalável, o contrato passa a mudar conforme o
que a pessoa instalou.

- **Rota de plugin desligado responde o quê?** 404 (como se nunca tivesse
  existido) ou algo que diferencie "não existe" de "existe mas está desligado"
  — porque o script do outro lado precisa saber se dá pra pedir pro usuário
  instalar.
- **`GET /status`** hoje devolve o estado do app inteiro. Ele passa a listar o
  que está instalado? Os campos de um plugin desligado somem do JSON ou vêm
  nulos? Sumir quebra quem lê sem checar; vir nulo engorda a resposta.
- **O que é contrato estável e o que é opcional.** Documentar a fronteira em
  `docs/local-api.md`, senão a próxima conversão quebra script alheio em
  silêncio.
- **Vale a pena a API poder instalar plugin?** (`POST /plugins/...`) Cheiro de
  YAGNI — provavelmente não —, mas decidir explicitamente pra não voltar.

## Resolução (2026-08-04)

O medo do ticket era maior que o problema: **uma rota só é de plugin**. Varrendo
o `NotchAPIServer.swift` contra a lista de 002, `/notify` e `/activity` são das
notificações (de fábrica), `/ask` e `/agent-requests` são do canal de agentes
(nem entra nas 15 features), e `/status` é diagnóstico. Sobra **`POST /mirror`**
(Espelho). O Pomodoro, a cobaia, não tem rota nenhuma — logo este ticket **não
bloqueia o piloto**, só evita que a próxima conversão quebre script alheio.

### 1. Rota de plugin desinstalado responde `404` com motivo no corpo

```json
{"ok":false,"error":"plugin desinstalado","plugin":"espelho"}
```

`404` porque é o que o servidor já devolve pra rota inexistente (script que só
olha o código HTTP não muda de comportamento) e o campo `plugin` é o que deixa o
script do outro lado dizer *"instale o Espelho no Knobler"* em vez de *"erro
desconhecido"* — que era a pergunta do ticket. Descartado `503`: mais correto no
papel, mas ninguém trata, e vira exceção nova no doc.

Sem o guard, o comportamento atual seria **mentira silenciosa**: a rota chama um
callback opcional (`onMirror?`), e chamar callback vazio em Swift não dá erro —
responderia `{"ok":true}` sem ligar câmera nenhuma. O guard é literalmente
`guard onMirror != nil` — **não consulta o registro de plugins**, só pergunta se
o callback foi preenchido. Fica no arquivo da API, sem acoplar a API ao registro.

### 2. `GET /status`: campos somem, mais um campo `plugins`

Campos de peça desligada **somem**, e isso sai de graça: o `statusProvider` é
uma closure montada no `AppDelegate` (`KnoblerApp.swift:514`) que pergunta
`?.diagnostics ?? [:]` a cada serviço — serviço que não nasce não põe campo.
Fazer vir nulo seria código novo pra publicar vazio de propósito. Quem lê
`/status` sem checar se o campo existe já estava errado antes deste mapa: o doc
diz desde sempre que o schema é extensível e não é contrato de persistência.

Ganha **um campo novo**, a lista de ids de 005:

```json
"plugins": ["pomodoro", "lembretes", "descanso", ...]
```

Uma linha no `statusProvider`. É o que permite o script perguntar **uma vez** o
que existe, em vez de descobrir batendo em cada rota e colecionando `404`. Sem
objeto aninhado, sem nome, sem versão — só os ids.

### 3. A fronteira fica marcada na rota, não em seção nova

Sem seção "contrato estável vs opcional" no `docs/local-api.md` — documento
separado desatualiza e ninguém lê. Três marcas:

1. No título da rota de plugin: `### POST /mirror` **(plugin: Espelho)**. Sem
   marca = de fábrica, sempre responde. Hoje aparece **uma vez só**.
2. Em "Erros e limites": `404` também quando a rota é de plugin desinstalado, com
   `plugin` no corpo.
3. Em `/status`: `plugins` lista os ids; campo de plugin desinstalado não aparece.

### 4. A API **não** instala plugin — decidido, não volta

Não é só YAGNI, é segurança: as rotas antigas da API **não têm autenticação**
(só `/agent-requests` exige token — `docs/local-api.md`). Rota de instalar sem
senha = qualquer processo local liga Ditado (microfone), Anotação
(Acessibilidade) ou Espelho (câmera) sem a pessoa ver. Hoje a API só *usa* o que
já está ligado; instalar seria a API mudando **o que o app é**. E instalar já é
um clique na vitrine de 006.

O caminho que fica: o script lê `plugins` no `/status`, ou leva o `404` com o id,
e **pede pra pessoa instalar**. A pessoa decide.

### Custo total

Um `guard` na rota `/mirror`, uma linha no `statusProvider`, três linhas de doc.
Nenhum gate novo: o Pomodoro não tem rota, então não há o que o harness do piloto
possa provar aqui.
