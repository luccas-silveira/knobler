# Bateria dos AirPods

![Card de conexão com bateria por componente](../Snapshots/airpods-connect.png)

*Conectou — bateria por componente (esquerdo/direito/case).*

![Aviso de bateria baixa](../Snapshots/airpods-low.png)

*Bateria baixa.*

## O que faz

Mostra o nível de bateria de cada componente dos AirPods (esquerdo, direito,
case) quando eles conectam. A conexão é detectada por notificação
event-driven do IOBluetooth (sem ficar checando toda hora); a bateria em si
vem do `system_profiler SPBluetoothDataType`, lido no connect e depois a cada
60s enquanto os AirPods seguem conectados.

## Como usar

- Não exige ação: conectar os AirPods já dispara o card sozinho.
- Pode ser desligado em Ajustes → Notch.

## Permissões

- **Bluetooth** — *"Knobler mostra o nível de bateria dos seus AirPods no
  notch quando eles conectam."*
