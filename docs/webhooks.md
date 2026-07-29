# Notificações externas (Webhooks)

![Painel de Ajustes de Notificações externas](images/settings-webhooks.png)

*Ajustes → Notificações externas — lista de perfis.*

![Editor de mapeamento de um perfil](images/mapping-editor.png)

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

## Quando o painel diz "Credenciais inacessíveis"

Os três segredos do pareamento (`deviceId`, `deviceSecret`, `publishToken`) têm
uma ACL presa ao requisito de assinatura de quem os gravou. Se a assinatura do
app mudar — passar a ser notarizado com Developer ID, por exemplo — a ACL deixa
de bater e o Keychain não abre mais os itens. O app lê com a interação
desligada, então em vez do diálogo de senha do macOS aparece o aviso no painel,
com o botão **Parear de novo**.

Ele **não** re-pareia sozinho de propósito: o `publishToken` é a URL pública que
você já colou nos serviços externos, e um registro novo a invalidaria em
silêncio. Clicar em **Parear de novo** troca o link — os POSTs para o link
antigo param de chegar, e é preciso atualizar o serviço externo.

Distinguir "nunca pareado" de "pareado mas trancado" é decisão de
`WebhookKeychainStore.pairingState()`, coberta pelo `webhookcheck`.

## Permissões

Nenhuma permissão especial (usa rede normal, sem entitlement de sistema).
Os segredos de pareamento ficam no Keychain, nunca em UserDefaults ou log.
