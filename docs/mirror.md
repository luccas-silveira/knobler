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

- Fixe **Espelho** em Ajustes › Notch (o alfinete na linha): a seção passa a
  ficar sempre na faixa do rodapé, e **abrir a aba já acende a câmera** — não
  há botão pra clicar. Enquanto a sessão sobe (cerca de um segundo), o preview
  mostra "Ligando a câmera…".
- Sem fixar, o espelho só aparece na faixa quando já está ligado — pela API
  local (`POST /mirror`) ou por um atalho que a chame.
- Recolher o notch desliga o espelho: a câmera nunca fica ligada escondida.
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
