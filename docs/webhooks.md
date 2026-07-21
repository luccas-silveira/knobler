# Notificações externas (Webhooks)

![Painel de Ajustes de Notificações externas](../Snapshots/settings-webhooks.png)

*Ajustes → Notificações externas — lista de perfis.*

![Editor de mapeamento de um perfil](../Snapshots/mapping-editor.png)

*Mapear um perfil — como o JSON recebido vira o card.*

## O que faz

Cada "perfil" webhook tem um link próprio (`push.appzoi.com.br/w/<token>`):
qualquer serviço externo (Zapier, GHL, um script de deploy) que faça POST
nesse link vira um card de notificação no notch, sem precisar da API local
`127.0.0.1:4477` (que só funciona na mesma máquina). O mapeamento define quais
campos do JSON recebido viram título, corpo, ícone, etc. do card. A conexão
com o relay usa um WebSocket sempre ativo, com reconexão automática.

## Como usar

- Ligar/criar perfis: Ajustes → Notificações externas.
- Copiar o link do perfil e configurar o serviço externo pra fazer POST nele.
- "Mapear" um perfil abre o editor visual pra ligar campos do JSON recebido
  (título, corpo, ícone, som) às partes do card.
- Rotacionar ou excluir um perfil invalida o link antigo.

## Permissões

Nenhuma permissão especial (usa rede normal, sem entitlement de sistema).
Os segredos de pareamento ficam no Keychain, nunca em UserDefaults ou log.
