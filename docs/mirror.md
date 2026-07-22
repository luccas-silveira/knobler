# Espelho de câmera (Mirror)

> Sem screenshot automático nesta página: gerar um exigiria ligar a câmera de
> verdade dentro do script de build (`tools/snapshot.sh`), o que não é
> apropriado pra um processo não-interativo. Se quiser, tire um screenshot
> manual do app rodando e adicione a imagem aqui depois.

## O que faz

Mostra a câmera como um espelho dentro do notch expandido — útil pra se olhar
rapidamente antes de uma reunião de vídeo, sem abrir o Photo Booth ou uma
chamada de verdade.

## Como usar

- No notch aberto, clique no botão de câmera pra ligar/desligar o espelho.
- Na primeira vez, o macOS pede a permissão de câmera.
- Com mais de uma câmera na máquina (webcam USB, OBS Virtual Camera, Câmera de
  Continuidade), a **setinha no canto do preview** abre a lista pra escolher
  qual entrada aparece. Com uma câmera só a setinha nem aparece. Em
  "Automática" o app usa a embutida. A troca vale na hora, sem fechar o
  espelho; se a câmera escolhida for desconectada, ele volta pra embutida
  sozinho.

## Permissões

- **Câmera** — *"Knobler mostra sua câmera no notch como espelho antes de
  reuniões."*
