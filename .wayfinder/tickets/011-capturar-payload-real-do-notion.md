# Capturar um POST real da automação do Notion

- map: ../map.md
- label: wayfinder:task
- status: open
- assignee: —
- blocked-by: —

## Question

O research fechou a via (automação de database → "Send webhook"), mas não há
fonte primária com o JSON literal: a Notion não publica um e a UI não tem
preview. Os nomes das chaves de topo e o formato das propriedades estão em
confiança média — provavelmente o objeto de propriedade da API
(`properties.<Nome>.title[0].plain_text`, `.select.name`), mas ninguém viu.

Trabalho manual (HITL): criar uma database de teste com propriedades de tipos
variados (title, select, date, person, number, formula `link()`), montar uma
automação "Send webhook" apontando pra webhook.site (ou pro link de um perfil
do Knobler), disparar, capturar o corpo cru.

Resolvido quando o payload real estiver anexado em
`.wayfinder/research/notion.md` e a confiança dos caminhos subir de média pra
alta — sem isso o preset do Notion não pode ser escrito.

## Bloqueio encontrado (2026-08-04)

Tentado nesta sessão junto de 010 e 012, **não** executado. O login no Notion
(via Google, mesma conta usada no ClickUp) cai num **onboarding de conta nova**:
não há workspace existente, e a automação de database "Send webhook" é recurso
de **plano pago**. Criar workspace e assinar/ativar trial numa conta pessoal é
decisão do dono da conta, não desta sessão — nada foi criado.

Para desbloquear, uma destas:
- apontar um workspace Notion **já existente** em plano que tenha automações de
  database (o research diz Plus/Business), e refazer o checklist abaixo;
- ou aceitar ativar trial numa conta nova.

Checklist pronto para quando houver workspace:
1. Criar database de teste com propriedades de tipos variados — title, select,
   date, person, number e uma fórmula `link()`.
2. No canto superior direito da database: ⚡ → **Nova automação** → gatilho
   *Página adicionada* → ação **Enviar webhook**.
3. Colar `https://webhook.site/f6a3a698-cf9d-446a-8821-9168855e7d91`
   (token já criado nesta sessão, sem expiração configurada).
4. Adicionar uma página preenchendo todas as propriedades.
5. Avisar — o payload é lido daí sem mais nada.

O que a captura precisa responder continua igual, mais um item vindo de 014:
confirmar que **não vem `url`** (o deep link teria que sair do id via o filtro
`semHifens`), e se as propriedades chegam como o objeto de propriedade da API
(`properties.<Nome>.title[0].plain_text`) ou já achatadas.
