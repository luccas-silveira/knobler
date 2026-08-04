# Onde vive o "instalado" e como quem já usa atravessa

- map: ../map.md
- label: wayfinder:grilling
- status: closed
- assignee: claude (sessão 2026-08-04)
- blocked-by: — (003 fechado)

## Question

O charting decidiu que instalar é ligar uma chave e que ninguém perde feature na
atualização. Falta a forma:

- **O formato.** Uma lista de ids instalados (`["pomodoro", "lembretes"]`) ou um
  booleano por plugin? A lista morre bem quando um plugin é renomeado ou
  removido do catálogo; o booleano espalhado repete o problema que já existe hoje.
- **Onde.** `AppSettings`/`UserDefaults` como todo o resto, ou arquivo próprio?
  (`NotificationHistory` e `Onboarding` já mostram os dois padrões do projeto.)
- **A migração, uma vez só.** Ler o toggle antigo de cada feature e marcar
  instalado. Onde ela roda, como se garante que roda uma vez (o `Onboarding` já
  versiona por passo — mesmo truque?), e o que fazer com as features que **não
  têm toggle hoje** (shelf, espelho, anotação, link, nota rápida): entram
  instaladas por padrão ou desinstaladas?
- **Instalação nova.** Quem baixa o Knobler amanhã de manhã começa com o quê —
  só o de fábrica, ou de fábrica mais alguns plugins bons de primeira impressão?
- **Chave órfã.** Plugin instalado cujo id sumiu do catálogo (renomeado,
  descontinuado): ignora calado, ou avisa?

## Resolução (2026-08-04)

**O formato: uma lista de ids instalados.** Uma chave só, guardando
`["pomodoro", "lembretes", ...]`; quem não está na lista não nasce. Ganhou do
booleano-por-plugin por três motivos: o `AppDelegate` faz *uma* pergunta ("quem
está ligado?") e a lista responde em uma leitura, enquanto 11 chaves soltas
precisam ser lidas e remontadas toda vez; id que sai do catálogo morre limpo
(ver "chave órfã" abaixo) em vez de virar lixo permanente nos ajustes; e
espalhar 11 toggles novos é exatamente o problema que o ticket 001 achou e que
este mapa existe pra não repetir. A lista não distingue "nunca instalei" de
"desinstalei" — e não precisa: fora da lista é fora, ponto.

**Onde: `UserDefaults`, junto do resto dos ajustes** (chave
`pluginsInstalados`), não arquivo próprio. Arquivo próprio no projeto é padrão
pra dado que cresce (`NotificationHistory`, itens da prateleira); lista de 11
nomes não cresce. `UserDefaults` grava e lê `[String]` sozinho, sem tratar
arquivo corrompido nem decidir quando persistir, e o comando `defaults` já
permite montar cenário de fora — o mesmo truque que o `CLAUDE.md` usa pras
capturas. Só perderia se a lista precisasse sincronizar entre máquinas ou ser
editada à mão, e nada disso está no mapa.

**A migração, uma vez só: todo mundo atravessa com os 11 plugins instalados**, e
os interruptores antigos (ditado etc.) continuam valendo exatamente como estão.
Roda no arranque com o mesmo truque do `Onboarding` — um número de versão numa
chave (`plugins.migracao`); se já está gravado, não roda de novo. Ler o toggle
antigo de cada feature pra decidir foi **descartado**: interruptor desligado não
é feature perdida (a decisão travada é "ninguém perde feature na atualização"),
desinstalar por conta própria faria o interruptor sumir do painel sem a pessoa
entender pra onde foi, e a conta viraria 11 casos especiais — um deles o ditado,
que ainda depende do tap global do VolumeHUD. Features **sem** toggle hoje
(Pomodoro, espelho, anotação, nota rápida, link, conversão) entram instaladas
pelo mesmo motivo.

**Instalação nova: idêntica — os 11 instalados.** Um comportamento só pra máquina
nova e máquina antiga (dois cenários seriam dois pra testar e dois pra
documentar); notch quase vazio na primeira abertura parece app quebrado, e a
loja vende melhor quando a pessoa já viu a peça funcionando e escolhe tirar.
"Fábrica + um punhado escolhido a dedo" ficou fora por não ser decidível hoje:
depende de vitrine, nome e ícone das peças, que o mapa ainda lista como névoa.
Se a loja quiser mudar depois, é trocar a lista padrão — uma linha.

Custo aceito nas duas decisões acima: o ganho de `~0% CPU parado` não aparece
sozinho na atualização nem na instalação nova — só depois de desinstalar de
propósito. É promessa da loja, não da atualização.

**Chave órfã: ignora calado.** Id na lista que não existe mais no catálogo não
vira nada e ninguém é avisado — a pessoa não fez nada errado e não há ação
possível pra ela. É a mesma regra que 002 já fixou pra dependência
Pomodoro→Descanso ("a opção some, sem avisar"), e é o comportamento de graça:
comparar contra `PluginID.allCases` e não achar já ignora sozinho. Ignorar
**não** é apagar: o id fica guardado, então plugin que volte com o mesmo nome
volta instalado do jeito que estava.
