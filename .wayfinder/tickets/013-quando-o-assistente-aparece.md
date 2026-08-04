# Quando o assistente aparece e por onde se sai dele

- map: ../map.md
- label: wayfinder:grilling
- status: closed
- assignee: —
- blocked-by: —

## Question

004 decidiu que o primeiro perfil nasce num assistente de passos. Falta decidir
a moldura dele:

- **Onde vive**: janela própria (`NSWindow`, como o wizard de boas-vindas) ou
  sheet sobre a janela de Ajustes? A janela própria abre de qualquer lugar e
  não prende o painel; o sheet reaproveita a janela que já está aberta.
- **Quando aparece**: só quando não existe nenhum perfil? Sempre que se clica em
  "Adicionar perfil"? Ou existem as duas portas — assistente por padrão e
  "criar sem assistente" pra quem já sabe?
- **Por onde se sai**: fechar no meio deixa um perfil pela metade ou não cria
  nada? Se deixa, a linha do perfil no painel oferece "continuar de onde parou"?
- **Segundo perfil em diante**: o assistente vira estorvo depois do primeiro?

O protótipo de 004 (`.wayfinder/prototypes/004-forma-da-entrada.swift`) mostra os
cinco passos mas monta o assistente numa janela única sem entrada nem saída —
essa parte é exatamente o que este ticket decide.

## Resolução (2026-08-04)

### Onde vive: **sheet sobre a janela de Ajustes**

O assistente nasce do botão "Adicionar perfil", que só existe dentro do painel
de webhooks em Ajustes — não há entrada de fora do app, ao contrário do wizard
de boas-vindas (que precisa de `NSWindow` porque abre antes de qualquer janela
existir). O editor de mapeamento já é sheet, e o passo Mapa **é** o editor:
janela própria criaria uma janela que abre um sheet, ou dois níveis de janela
solta. Prender os Ajustes durante o assistente não custa nada — no passo
Primeiro envio o usuário está no navegador, no ClickUp/Notion, não no painel.

### Quando aparece: **sempre que se clica em "Adicionar perfil"**

Porta única. Duas portas ("com assistente" / "sem assistente") obrigam o usuário
a escolher antes de saber a diferença, e o assistente não é penalidade: o passo
Nome é um campo, o Link é copiar, o Mapa é o editor de sempre. A válvula de
escape mora **dentro** do passo Serviço, como opção "Outro serviço (sem
preset)", que só tira o conteúdo do preset — não pula passo.

Não existe "só quando não há nenhum perfil": o gatilho é a ação, não a contagem.

### Por onde se sai: **o perfil criado permanece; o assistente é retomável**

O perfil é criado no relay no passo Nome (o link do passo seguinte exige perfil
existente), então fechar depois disso deixa um perfil **sem mapping** — que já é
estado legítimo e nomeado no relay: captura-only (`server.js:107`, responde
`202 captured`). Nada de perfil fantasma, nada de rollback.

Fechar **antes** do passo Nome não cria nada.

A linha do perfil no painel mostra o estado e retoma no clique. O passo de
retomada é **derivado**, nunca persistido:

| Estado | Retoma em |
|---|---|
| sem `lastPayloadAt` (007) | Primeiro envio |
| com payload, sem mapping | Mapa |
| com mapping | abre o editor direto, sem assistente |

Zero campo novo de "passo em que parei": o estado do perfil já responde. Um
passo persistido seria um segundo estado a manter em sincronia com o primeiro.

### Segundo perfil em diante: **o mesmo assistente**

Sem modo avançado e sem lembrar preferência. O que torna o assistente repetitivo
é o conteúdo do preset, não a moldura, e quem cria o segundo perfil geralmente
está num serviço diferente — é justamente quando o preset vale. Se a repetição
doer na prática, a resposta é encurtar passo, não criar uma segunda porta.

### Fica pra execução

- `Knobler/WebhookSettingsView.swift`: botão "Adicionar perfil" abre o sheet do
  assistente; linha do perfil ganha o estado e o clique de retomada.
- Protótipo de 004 (`.wayfinder/prototypes/004-forma-da-entrada.swift`) vira a
  base dos cinco passos; falta a moldura decidida aqui.
- Depende de 007 pro `lastPayloadAt` que decide o passo de retomada.
