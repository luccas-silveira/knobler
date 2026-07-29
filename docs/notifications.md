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
