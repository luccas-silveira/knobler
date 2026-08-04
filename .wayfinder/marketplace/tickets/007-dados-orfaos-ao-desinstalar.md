# O que acontece com os dados quando se desinstala

- map: ../map.md
- label: wayfinder:grilling
- status: closed
- assignee: claude (sessão 2026-08-04)
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

## Resolução (2026-08-04)

**Desinstalar não apaga nada. Nunca. Uma regra só, sem exceção por plugin.**

Levantamento que embasou (arquivo:linha conferido nesta sessão): só quatro peças
guardam trabalho insubstituível — Lembretes (`reminders` em `UserDefaults`,
`AppSettings.swift:183`), Descanso (`screenBreaks`, `AppSettings.swift:192`),
Mensagens LAN (`messages.json` + `media/` + `avatars/` em Application Support,
`MessageStore.swift:22`) e Anotação (`annotations/display-<id>.json`,
`AnnotationController.swift:83`). Pomodoro, Espelho e Conversão de arquivo só têm
preferência; Nota rápida e Preview de Link não guardam nada.

As quatro decisões:

1. **Não apaga nada** — nem dado, nem preferência. Padrão do macOS (app vai pro
   lixo, `~/Library` fica), o dado é caro e insubstituível, o "lixo" é de poucos
   KB (as conversas já têm teto de 20 por contato), e não apagar custa **zero
   linha**: desinstalar já é só tirar um id da lista de 005. Escrever rotina de
   limpeza por peça é onde mora o bug que apaga demais. Efeito colateral bom:
   desinstalar deixa de ser assustador, dá pra experimentar.
2. **Keychain e relay também ficam** — o único estado fora do Mac (Webhooks:
   segredo em `WebhookKeychainStore.swift:14`, perfis no relay `relay/src/db.js`)
   segue a mesma regra. Apagar no relay é chamada de rede que pode falhar
   (precisaria de erro, retry, fila), o perfil parado não faz mal (o app nem
   busca com o plugin desligado; a fila do relay já expira em 24h / 50 itens), e
   apagar mataria todo link público já entregue pra fora. Quem quiser mesmo
   remover usa o botão que já existe na tela de Webhooks, **antes** de
   desinstalar.
3. **Sem diálogo de confirmação** — confirmação protege de perda, e aqui não há
   perda; o card não muda de lugar (006), então o botão vira `INSTALAR` ali mesmo
   e reinstalar é o desfazer. Perguntar "tem certeza?" ensinaria um medo falso.
   Em vez disso, **uma linha de texto no menu ⋯**: "Desinstalar (seus dados ficam
   salvos)".
4. **As chaves de armazenamento ficam com o nome que já têm** — nada de
   `plugin.<id>.*`. Renomear é migração (código que lê o nome velho, copia,
   roda uma vez pra toda a base instalada), não resolve problema de ninguém, e
   quebraria justamente a promessa do item 1. A peça sabe onde guarda o dela; o
   id de 003 é do catálogo, não do disco.

**Consequência de execução:** desinstalar/reinstalar **não toca em disco**.
"Reinstalar reencontra o dado" sai de graça — sem código, sem migração e sem gate
novo em `tools/check.sh`. O único trabalho que este ticket manda pro piloto é a
string do menu ⋯ do 006.
