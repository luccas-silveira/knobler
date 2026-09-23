# Bloquear teclado — design

Data: 2026-09-23. Status: aprovado em chat.

## Objetivo

Travar o teclado inteiro por um tempo pra limpar as teclas, sem desligar o Mac. Mouse e
trackpad continuam livres; o clique é a saída.

## Comportamento

- **Ligar:** item "Bloquear teclado" no menu da barra; `POST /keyboard/lock` na API local.
- **Enquanto ligado:** todo `keyDown`, `keyUp`, `flagsChanged` e evento de sistema
  (`NX_SYSDEFINED`, teclas de mídia/brilho) é descartado.
- **Notch:** card fixo "Teclado bloqueado — clique para destravar" em todas as telas.
  Vence notificação e HUD. Clique destrava.
- **Destravar:** clique no card; `POST /keyboard/unlock`.
- **Sem Acessibilidade:** não liga; abre Ajustes › Permissões (mesmo caminho do ditado).
- **Campo de senha focado** (`IsSecureEventInputEnabled()`): não liga; notificação comum no notch "Saia do campo de senha antes de bloquear".
- **Segurança:** estado só em memória. Crash ou saída do app = teclado livre. Nada
  persiste pra travar de novo na próxima abertura.

Limites do macOS (não bloqueáveis, aceitos): botão liga/Touch ID, Ctrl+⌘+Q.

## Componentes

- `Knobler/TecladoBloqueado.swift` — singleton injetado (padrão de `QuickNote`). Cria um
  `CGEventTap` próprio só enquanto ativo e o destrói ao desligar. Não reusa o tap do
  `VolumeHUD`: aquele não escuta teclas comuns, e escutar sempre faria toda tecla do Mac
  passar pelo app.
- Função pura `deveEngolir(tipo:)` — a decisão testável.
- Menu da barra, rota da API, ramo novo no `NotchViewModel.mode` e no `currentSize`.

## Testes

- `tools/tecladocheck.swift` (entrada no `tools/check.sh`): `deveEngolir` por tipo de
  evento; `tapDisabledByTimeout` reativa em vez de engolir.
- Snapshot do card em `tools/snapshot.sh`.

## Fora de escopo

Destrava por tempo ou atalho. Entra se o clique não bastar.

## Decisões do grill

- **A1** — recusa ligar com entrada segura ativa e avisa por notificação comum. Motivo:
  com campo de senha focado o macOS entrega as teclas por fora do tap.
- **A2** — sem Acessibilidade, abre Ajustes › Permissões. Motivo: reusa
  `KnoblerApp.swift:1438` e o notch não tem card de aviso hoje.
