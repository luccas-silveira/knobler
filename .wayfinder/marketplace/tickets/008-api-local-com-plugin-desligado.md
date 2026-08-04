# A API local quando o plugin está desligado

- map: ../map.md
- label: wayfinder:grilling
- status: open
- assignee: —
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
