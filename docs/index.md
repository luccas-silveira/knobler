# Documentação do Knobler

O Knobler é um agente macOS que transforma o notch em um canal ambiente para
música, avisos, automações, ditado e pequenas interações.

Esta documentação segue a separação do [Diátaxis](https://diataxis.fr/):
tutoriais curtos para começar, how-to para executar tarefas, referência para
contratos e explicações para entender decisões.

## Comece aqui

- [README](../README.md) — visão geral, instalação e exemplos rápidos.
- [Ajustes](settings.md) — configurar as funções no app.
- [Troubleshooting](troubleshooting.md) — diagnóstico quando algo não aparece
  ou não responde.

## Entender o produto

- [Produto](../PRODUCT.md) — propósito, usuários e princípios de UX.
- [Arquitetura](architecture.md) — composição atual, ownership de estado e
  fluxos importantes.
- [API local](local-api.md) — endpoints, payloads, TTLs e respostas.
- [AskUserQuestion](ask.md) — integração do Claude Code com o notch.
- [Solicitações de agentes](agent-requests.md) — permissões do Claude e
  aprovações do Codex espelhadas no notch.

## Usar as features

- [Boas-vindas](onboarding.md) — a janela da primeira abertura
- [Now Playing](now-playing.md)
- [HUDs](huds.md)
- [Notificações](notifications.md)
- [Avisos do desenvolvedor](avisos.md) — recados sobre o próprio Knobler
- [Countdown de calendário](calendar-countdown.md)
- [Ditado](dictation.md)
- [Pomodoro](pomodoro.md)
- [Descanso](descanso.md)
- [Lembretes](reminders.md)
- [Nota rápida](nota-rapida.md)
- [Shelf de capturas](shelf.md) — inclui conversão de arquivos e AirDrop
- [Preview de link](link-preview.md) — arraste um link e a página abre no card
- [Conta-gotas](color-picker.md)
- [Mensagens LAN](messages.md)
- [Webhooks](webhooks.md)
- [AirPods](airpods.md)
- [Espelho de câmera](mirror.md)
- [Anotação de tela](annotation.md) — desenhe sobre apresentações e qualquer app

## Desenvolver e manter

- [Operação do relay](relay-operacao.md) — pm2, banco, limites e backup do
  serviço de webhooks.
- [Guia de desenvolvimento](development.md) — setup, build, checks, snapshots
  e release.
- [Contribuição](../CONTRIBUTING.md) — fluxo de mudança e checklist.
- [Segurança e privacidade](../SECURITY.md) — trust boundaries, dados e
  reporte responsável.
- [Versionamento](../VERSIONING.md) — SemVer e processo de release.
- [Licença](../LICENSE) — MIT.
- [Proveniência do vendor](../Vendor/PROVENANCE.md) — MediaRemote adapter
  incluído no app.

## Histórico e decisões

- [Changelog](../CHANGELOG.md) — mudanças por release.
- [Handoff](../HANDOFF.md) — estado operacional da última sessão;
  [sessões anteriores](handoffs/2026-07.md) ficam arquivadas.
- [Ideias](IDEIAS.md) — backlog do que ainda não virou feature.
- [Trilhas de implementação](ROADMAP.md) — em que ordem o backlog sai, por substrato compartilhado.
- [Specs e pesquisas](superpowers/specs/) — decisões de design e evidências.
- [Planos de implementação](superpowers/plans/) — planos históricos; não são
  a fonte atual da arquitetura quando o código já mudou.

## Regra de manutenção

O código é a fonte da verdade para comportamento. Ao mudar uma API, permissão,
flag de build, fluxo de instalação ou ownership de estado, atualize a página de
referência correspondente e o `CHANGELOG.md`. Evite copiar a mesma instrução
para vários arquivos; prefira apontar para uma única referência.
