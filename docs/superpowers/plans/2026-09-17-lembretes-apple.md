# Integração com Lembretes da Apple

Plano aprovado em 17/09/2026: fonte EventKit única, ações rápidas no notch e
janela dedicada para consulta, edição, recorrência e gestão de listas.

## Implementado

- Serviço compartilhado no AppDelegate, consultas assíncronas e atualização por
  eventos do EventKit/retorno do app; permissão de Lembretes separada de Calendários.
- Seção permanente `lembretesApple`, com ordenação/fixação existentes, teclado
  durante o rascunho e rolagem entregue à lista; dados não promovem nem abrem o notch.
- Sessão de edição e janela reutilizáveis, sem gravação local dos dados Apple.
- Alterações concorrentes verificadas antes de salvar; rascunhos mantidos nos erros.
- Alertas próprios renomeados na apresentação para Alertas programados, sem
  alterar identificadores, armazenamento ou scheduler.
- Self-checks de modelos, sessão UI, permissões, apresentação e ciclo de edição;
  snapshots sintéticos do notch e da janela, sem consultar lembretes pessoais.

## Validação

- `xcodegen generate`: concluído.
- Build Debug Xcode: concluído (`/tmp/knobler-apple-reminders-final-build.log`).
- Self-checks: 41 passaram na execução completa
  (`/tmp/knobler-apple-reminders-final-checks.log`); o único restante,
  `eventoscheck`, passou após corrigir o isolamento do harness com `@MainActor`
  (`/tmp/knobler-eventos-final.log`). Total: 42 checks validados.
- Snapshots sintéticos gerados e estados do notch inspecionados. Lista e editor
  da janela nativa capturados pelo macOS e inspecionados; controles corretos.
  As capturas substituem as imagens de `cacheDisplay`, que distorcia os controles
  AppKit, em `Snapshots/lembretes-janela.png` e
  `Snapshots/lembretes-janela-editor.png`.
- Operações em contas reais da Apple e sincronização entre dispositivos não foram
  executadas automaticamente: a validação usa dados sintéticos e objetos locais.

## Limites aceitos

A Apple cuida de notificações e sincronização. Sem migração dos alertas próprios,
endpoints locais, subtarefas, tags, anexos ou gestão de compartilhamento nesta entrega.
