# Ajustes

![Painel Geral](images/settings-geral.png)

*Geral.*

![Painel Notch](images/settings-notch.png)

*Notch — liga/desliga cada feature individualmente.*

## O que faz

Janela única de configuração no estilo do Ajustes do Sistema: sidebar com
todos os painéis, detalhe em formulário agrupado à direita. Cada feature do
Knobler tem seu painel — os detalhes de cada um estão documentados na página
da própria feature, linkada abaixo.

## Como usar

- Abrir Ajustes: pelo menu do Knobler ou clicando na pílula do Pomodoro (que
  abre direto no painel de Pomodoro).
- Painéis e onde encontrar os detalhes de cada um:
  - **Geral** — login automático, versão do app, atualizações.
  - **Notch** — liga/desliga individualmente HUDs, notificações, countdown de
    calendário, visualizador de áudio, API local, AirPods, screenshots na
    prateleira, espelho de câmera. Traz também a **ordem das seções do card
    aberto**: uma lista arrastável que define quem aparece primeiro quando não
    há evento recente promovendo ninguém. Ver `docs/huds.md`, `docs/notifications.md`,
    `docs/calendar-countdown.md`, `docs/now-playing.md`, `docs/local-api.md`,
    `docs/airpods.md`, `docs/shelf.md`, `docs/mirror.md`.
  - **Ditado** — ver `docs/dictation.md`.
  - **Pomodoro** — ver `docs/pomodoro.md`.
  - **Lembretes** — ver `docs/reminders.md`.
  - **Descanso** — ver `docs/descanso.md`.
  - **Notificações externas** — ver `docs/webhooks.md`.
  - **Mensagens** — nome/foto exibidos aos outros; ver `docs/messages.md`.
  - **Permissões** — estado de cada permissão que o app usa; ver abaixo.

## Atualizações

No painel **Geral**. O Knobler consulta o GitHub uma vez por dia e avisa quando
sai versão nova: um card desce do notch (uma vez por versão — **Depois** silencia
até a próxima) e a linha nos Ajustes fica lá enquanto o update existir.

**Atualizar** instala na hora e o app reinicia sozinho. Quem instalou pelo
Homebrew recebe o update pelo próprio `brew upgrade --cask knobler`, o que mantém
o Caskroom em dia; quem baixou o `.zip` recebe o download direto. Antes de trocar
o app, o Knobler confere de onde veio o download, a assinatura e o identificador
do que baixou — se algo não bater, nada é substituído e o card mostra o motivo.

Quando não dá pra instalar sozinho — sem Homebrew, release sem `.zip`, ou o app
rodando fora de `/Applications` — o botão vira **Ver release** e abre a página no
navegador. **Verificar agora** força uma checagem fora do ciclo diário, e o
toggle **Verificar atualizações automaticamente** desliga a checagem de vez.

> Depois de atualizar, o macOS pode pedir a permissão de **Acessibilidade** de
> novo (o ditado para em silêncio até você reconceder). Isso acontece quando a
> identidade de assinatura do app muda entre versões; ver
> [`troubleshooting.md`](troubleshooting.md).

## Permissões

![Painel Permissões](images/settings-permissoes.png)

*Permissões — o que o app usa, o estado de cada uma e o que quebra sem ela.*

O painel **Permissões** lista as sete permissões que o Knobler pode usar, com o
estado atual de cada uma e o botão **Abrir**, que leva direto ao painel certo do
Ajustes do Sistema.

O Knobler pede cada permissão **no primeiro uso do recurso**, não na abertura —
o microfone só quando você segura a ⌥ direita pela primeira vez, a câmera só ao
abrir o espelho, a rede local só ao pôr a seção Mensagens em foco. Recusar não
quebra o app: só desliga aquele recurso.

A exceção é a **Acessibilidade**, a única pedida na abertura. Sem ela o
`CGEventTap` nem chega a ser criado, então a ⌥ direita nunca chega ao app e não
existe "primeiro uso" que dê pra esperar — o ditado ficaria impossível de
acionar. É também a permissão que os HUDs de volume e brilho usam.

Três permissões não expõem status ao app — **Rede local**, **Arquivos e pastas**
e **Gravação de áudio do sistema**. O macOS não oferece API para consultá-las, só
para usá-las. Elas aparecem como *Ainda não usada* até o recurso rodar uma vez;
a partir daí o painel mostra o resultado real.
