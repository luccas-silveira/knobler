# O que acontece com os dados quando se desinstala

- map: ../map.md
- label: wayfinder:grilling
- status: open
- assignee: —
- blocked-by: — (003 fechado)

## Question

Várias features guardam coisa em disco: lembretes salvos, histórico de
notificações, mensagens, itens da shelf, texto da nota rápida, perfis de webhook
(inclusive segredo no Keychain e perfil **no relay**, que é um servidor remoto).

- **Desinstalar apaga ou preserva?** Preservar é o padrão gentil (reinstalou,
  está tudo lá) mas deixa lixo pra sempre. Apagar é limpo e irreversível.
- **Se preserva, por quanto tempo** e quem cobra a limpeza?
- **Keychain e relay**: o webhook tem estado **fora** do app. Desinstalar o
  plugin apaga o perfil no relay (chamada de rede que pode falhar) ou deixa lá?
- **Reinstalar reencontra o dado?** Se sim, a chave do dado tem que sobreviver ao
  desinstalar — o que amarra o id da peça (003) ao nome do arquivo/preferência.
- **A regra é por plugin ou é uma só pra todos?** Uma regra só é mais fácil de
  explicar; por plugin é mais justo (histórico de notificação é descartável,
  lembrete futuro não é).
