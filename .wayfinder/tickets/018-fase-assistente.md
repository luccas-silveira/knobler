# Fase 2 — assistente de passos

- map: ../map.md
- label: wayfinder:task
- status: open
- assignee: —
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
