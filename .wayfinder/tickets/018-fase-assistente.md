# Fase 2 — assistente de passos

- map: ../map.md
- label: wayfinder:task
- status: closed
- assignee: sessão 2026-08-04
- blocked-by: 017

## Question

O assistente de 004/013: sheet sobre Ajustes, aberto **sempre** por "Adicionar
perfil" (porta única), passos Nome → Serviço → Link → Primeiro envio → Mapa.
Protótipo executável em `.wayfinder/prototypes/004-forma-da-entrada.swift`.

- Passo Serviço lista os quatro caminhos de 017 + escape "Outro serviço (sem
  preset)". É onde as ressalvas de cada caminho aparecem.
- Passo Primeiro envio: link do perfil + espera ao vivo por `lastPayloadAt`
  (polling de `GET /profiles/:id` a cada 2s enquanto o sheet está visível — 007).
- Fechar no meio deixa o perfil sem mapping (estado captura-only do relay); a
  retomada é **derivada** desse estado, nunca de um passo persistido.
- Linha do perfil no painel passa a mostrar estado ("Esperando primeiro envio" /
  "último webhook há 3 min").

## Resolução (2026-08-04)

Entregue.

- `Knobler/WebhookAssistant.swift` (novo, sem SwiftUI): `PassoAssistente`
  (os cinco passos + `proximo`/`anterior` + `retomada(hasMapping:lastPayloadAt:)`,
  a tabela de 013) e `EstadoDoPerfil.legenda`/`haQuantoTempo`. Tempo relativo
  escrito à mão porque `RelativeDateTimeFormatter` muda com o locale e o texto
  entra no gate.
- `Knobler/WebhookAssistantView.swift` (novo): o sheet. Trilha no topo, passo
  Serviço listando os quatro presets de 017 mais "Outro serviço (sem preset)",
  passo Link com `instrucao` + `ressalva` do caminho, passo Primeiro envio com
  polling de `GET /profiles/:id` a cada 2s via `.task(id: passo)` (007 — cancela
  sozinho ao trocar de passo ou fechar), e passo Mapa que **é** o
  `MappingEditorView` (013), sem trilha nem rodapé duplicado. O perfil nasce no
  "Continuar" do passo Nome; fechar depois disso deixa captura-only.
- `MappingEditorView` ganhou `preset:`: semeia title/body/url/id do
  `mapaSugerido` só quando o perfil ainda não tem mapping, e grava
  `_origem: {preset, versao}` dentro do mapping (006). Editar depois preserva o
  `_origem` que já estava lá.
- `WebhookSettingsView`: o campo "Nome do novo perfil" saiu; entrou o botão
  "Adicionar perfil" (porta única de 013). A legenda da linha virou estado e o
  clique na linha (ou "Continuar a configuração…" no menu) retoma pelo passo
  derivado — com mapa, abre o editor direto.
- Gate `tools/assistentecheck.swift` (`./tools/check.sh` = 32, era 31): a
  derivação da retomada, a ordem dos passos, as três legendas e o tempo
  relativo (inclusive relógio adiantado, que não pode virar "há -1 min"). O
  sheet em si não entra no harness de snapshot (`TextField`, `ScrollView`,
  `HSplitView`). Mutação confirmada: forçar `retomada` a devolver sempre `.mapa`
  faz o gate falhar.

### Desvio

A legenda precisa de `lastPayloadAt` por perfil e `GET /profiles` não o devolve
(só `GET /profiles/:id`, de 016). Em vez de mexer no relay já implantado, o
`listProfiles()` faz um `GET /profiles/:id` por linha — N+1 marcado com
`// ponytail:` no código, com o caminho de upgrade (mover o campo pra lista)
anotado. Perfis são poucos e o painel só recarrega em evento.

### Não entra aqui

"Colar um JSON de exemplo" no passo Primeiro envio é a Fase 3 (019) e o
auto-mapeamento a partir do payload real é a Fase 4 (020); hoje o passo Mapa
semeia a partir do preset (`mapaAplicavelSemPayload`), não do que chegou.
