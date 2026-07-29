# Notificações do sistema

![Card de notificação no notch](images/notification.png)

## O que faz

Intercepta banners de notificação do macOS via Accessibility — observa o
processo do Notification Center (`AXObserver` + polling de segurança), lê o
título/corpo do banner, fecha o balão nativo e mostra o mesmo conteúdo como um
card que desce do notch.

## Como usar

- Não exige ação: qualquer notificação do sistema que abriria o banner nativo
  passa a aparecer no notch automaticamente.
- Pode ser desligada em Ajustes → Notch.

## O que NÃO é engolido

Dois casos em que o alerta do sistema **continua na tela** e o card do notch é
só um espelho:

- **AirDrop.** O alerta acompanha uma transferência viva; fechá-lo interrompia o
  recebimento. O card mostra 📥 e clicar nele revela a pasta Downloads.
- **Alertas com botão** (Aceitar/Recusar e afins). Exigem decisão, então o
  original fica de pé. Os botões são espelhados no card: clicar no notch aciona
  o botão real via Accessibility, e o card espera 30s em vez de 5s. Se algo der
  errado no espelho, o alerta do sistema continua ali pra você responder.

O `Fechar`/`Limpar` do próprio alerta nunca vira botão do card.

## Permissões

- **Acessibilidade** — necessária pro `AXObserver` ler e fechar o banner
  nativo do Notification Center.

<!-- TODO screenshot: cortina de histórico aberta, com a alcinha visível no rodapé do card -->

## Histórico (24 h)

Tudo que virou card no notch fica registrado por 24 h: banner de sistema
interceptado, card de webhook, lembrete disparado, fim de fase do Pomodoro e
cor copiada pelo conta-gotas. Não é um log separado — é o mesmo conteúdo que
já passou pelo card, guardado pra consulta. Atividade da API local (a linha
de progresso do deploy) **não** entra: ela não é card, é uma faixa que vive
no notch enquanto dura.

### Como abrir

Puxe o card pra baixo **numa passada só**, sem soltar o mouse: os primeiros
~24 pt abrem o card normal; continuando o mesmo gesto até ~120 pt, ele
transiciona pra cortina de histórico. Recuar dentro do mesmo gesto desfaz —
não precisa soltar e puxar de novo. Um swipe majoritariamente horizontal não
abre nem fecha nada (guarda contra diagonais).

A única dica de que o gesto existe é uma alcinha (uma cápsula) que aparece no
rodapé do card aberto quando há histórico pra puxar.

### Como fechar

Fechar não é gesto — é tirar o mouse de cima do notch, o mesmo hover-out que
já fecha o card normal. Com a cortina aberta, o scroll vertical pertence à
lista (ela realmente rola, com momentum incluso) — mas só quando há lista pra
rolar: com o histórico vazio o gesto continua valendo pra fechar. Clicar numa
linha também recolhe o notch, junto com abrir a origem.

A nota rápida e a cortina não convivem: com a nota ligada naquela tela, o
puxão longo não abre o histórico (o card é da nota). O swipe horizontal, que
troca Música/Mensagens, fica desligado enquanto a cortina está aberta.

### O que aparece em cada linha

Horário à esquerda, nome do app, título e corpo truncado numa linha. **Sem
ícone do app** — `NSWorkspace.icon(forFile:)` não renderiza no harness de
snapshot offscreen do projeto, então a linha ficou só com texto. Clicar numa
linha faz o mesmo que clicar no card original teria feito (abre a URL, foca o
app, revela a pasta do AirDrop) e recolhe o notch.

Quando não há nada nas últimas 24 h, a cortina mostra "Nada nas últimas
24 h".

Um webhook que atualiza o mesmo `webhookID` várias vezes (por exemplo, uma
barra de progresso que muda 40 vezes) substitui a entrada anterior em vez de
empilhar — vira uma linha só no histórico, não quarenta.

### Limitação: não sobrevive ao restart

O histórico mora só em memória: reiniciar o Knobler limpa tudo. Não é
limitação técnica — notificação é efêmera por natureza, e guardar 24 h de
coisa que já passou não vale um arquivo em disco. Se um dia valer, o custo é
pequeno (o único campo chato de serializar é a cor do conta-gotas).

O histórico também tem teto de 300 linhas: uma fonte que dispare em rajada
não cresce sem limite dentro da janela de 24 h. Passando disso, a linha mais
antiga sai.
