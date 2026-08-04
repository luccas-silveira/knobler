# Histórico dos últimos N payloads no relay

- map: ../map.md
- label: wayfinder:grilling
- status: closed (out of scope)
- assignee: —
- blocked-by: — (007 fechado)

## Question

O relay guarda só o último payload por perfil. Decidir se passa a guardar os
últimos N e o editor deixa escolher qual usar de base — útil quando o serviço
manda vários tipos de evento no mesmo link e o último não é o que se quer mapear.

Decidir: N e a política de retenção (tamanho, idade), o que muda na API do
relay, o custo em banco, e se o histórico aparece como lista dentro do editor
ou como algo mais simples ("evento anterior"/"próximo").

## Fora de escopo — 2026-08-04

O cenário âncora do mapa é "primeiro perfil, do zero": nesse cenário existe um
payload só e o último é sempre o certo. Histórico serve pra link maduro
recebendo vários tipos de evento — outro problema, e caro: esquema novo no
banco do relay, política de retenção e API nova. Fica de fora deste destino;
volta como esforço próprio se o produto precisar.
