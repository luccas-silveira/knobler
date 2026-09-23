# Spec — Uso e sessões de Claude/Codex no notch

## Context
O codenotch (vinzdg/codenotch, MIT) mostra, por assistente, o consumo do limite do plano e o estado de cada sessão (ocupada / esperando você / concluída / ociosa). Queremos a mesma função no Knobler, reaproveitando o backend dele e desenhando a UI no nosso notch. Recorte decidido: **as duas funções, só Claude + Codex**.

Clone de referência: `scratchpad/codenotch` (recriar com `git clone --depth 1 https://github.com/vinzdg/codenotch`).

## Abordagem
Copiar (vendorizar) os arquivos de backend em `Vendor/Codenotch/` preservando o cabeçalho MIT + `LICENSE`, como já foi feito com `Vendor/MonitorControl/`. Cortar dependências de UI/prefs deles com um shim mínimo; não trazer SwiftNIO, Sparkle, zstd, PhoneLink, Ollama.

### Arquivos trazidos (Sources/ do codenotch)
- Sessões: `Sessions/AgentSession.swift`, `AgentActivityMonitor.swift`, `ActivityCoordinator.swift`, `ClaudeSessionMonitor.swift`, `ClaudeSessionRecord.swift`, `ClaudeTranscript.swift`, `ClaudeSessionOwnership.swift`, `ProcessLiveness.swift`, `CodexActivityMonitor.swift`, `SessionCompletionWatcher.swift`, `SessionFocus.swift`, `TerminalTabFocus.swift`.
- Uso: `Providers/UsageProvider.swift`, `ClaudeOAuthProvider.swift`, `ClaudeCredentials.swift`, `ClaudeProfile.swift`, `ClaudeTokenRefresher.swift`, `ClaudeCLI.swift`, `CodexLocalProvider.swift`, `CodexCredentials.swift`, `CodexProfile.swift`, `CodexUsage.swift`, `CredentialCache.swift`, `KeychainItem.swift`, `KeychainPrompt.swift`, `SQLiteStore` (onde estiver).
- Fora: `ClaudeDesktopUsageCache` (exige zstd) e `ClaudeDesktopSessionIndex`, `ClaudeUsageCLI` — entram só se a compilação provar que são obrigatórios. `// ponytail:` sem cache do app desktop do Claude.
- Shim `Vendor/Codenotch/CodenotchShim.swift`: `L10n.t` (identidade), `Preferences.stored…` (constantes), `ProviderGlyph` (enum vazio de casos usados), `UsageArchive` (backoff em UserDefaults) — só o que o compilador pedir.
- Deployment: o codenotch exige macOS 15; o nosso é 14.2. Trocar chamadas 15+ por equivalentes ou guardas `if #available`. Verificar cada símbolo no MCP `xcode` (DocumentationSearch).
- `project.yml`: incluir `Vendor/Codenotch`, linkar `libsqlite3`; `xcodegen generate`.

### Integração no Knobler
- `Knobler/AgentesUso.swift` (novo): `final class AgentesUso: ObservableObject`, singleton injetado em todas as janelas (padrão de `AgentRequestStore`, criado uma vez em `KnoblerApp.swift` ~:891 e passado no laço por tela ~:1169). Dono de `ActivityCoordinator` (sessões) e de um poll de 60 s nos dois providers (substitui o `UsageStore` deles, que traz muitas prefs). Publica `snapshots` e `sessions`.
- UI: nova `NotchSection` `agentes` em `Knobler/NotchSectionOrder.swift` (caso, título, ícone, entrada em `padrao` :70) alimentada por `NotchSectionInputs` (`Knobler/NotchPresentation.swift:261`). Conteúdo: dois anéis (reusar `ActivityRingView`, `NotchView.swift:1598`) com % e hora do reset, e lista de sessões com estado; clique chama `SessionFocus` (pede permissão de Automação uma vez).
- Fechado: indicador discreto quando alguma sessão está "esperando você" — reaproveitar o `SessionCompletionWatcher` pra enfileirar notificação no notch (construir a `NotchNotification` acima do laço por tela).
- API local: `GET /agents` no `NotchAPIServer.respond(to:)` (:243) + `docs/local-api.md`. Opcional; cortar se não houver consumidor.
- `tools/notchview-fontes.txt`: acrescentar os arquivos novos que a `NotchView` arrasta.

### Versionamento/docs
- `CHANGELOG.md` `## [Unreleased]`, `Knobler/Novidades/<versão>.html` + `NovidadesCatalogo.versoes` (feature = minor). Crédito ao codenotch no README.

## Verificação
1. `tools/agentescheck.swift`: parse de `ClaudeSessionRecord` com fixtures JSON (blocked/busy/idle/vazio), parse de `CodexUsage` com resposta gravada, `ProcessLiveness` com pid morto. Entrada em `tools/check.sh`.
2. `./tools/check.sh` verde.
3. `xcodebuild … build` (XcodeBuildMCP).
4. Cenário no `tools/main.swift` (seção agentes com dados fake) + `./tools/snapshot.sh`, ler o PNG.
5. Ao vivo: abrir uma sessão `claude` e uma `codex`, conferir estado mudando busy → waiting → done no notch e % batendo com `/usage`.

## Observação de processo
O CLAUDE.md manda feature passar pelo `spec-flow` (spec → pesquisa → grill → plano). Na execução, este plano vira o insumo do spec em `docs/superpowers/specs/2026-09-23-agentes-uso-design.md`.

Spec aprovada pelo usuário como plano em 2026-09-23 (plan mode).

## Decisões do grill

- **A1/A2** — anel do Claude atrás de interruptor nos Ajustes, desligado por padrão, com aviso de termos de uso e prompts do Keychain. Motivo: endpoint interno + token OAuth do Claude Code (termos de 2026-02-20) e item do Keychain recriado a cada ~8h. Sessões do Claude e Codex seguem ligadas.
- **A4** — mantido como no original: `ClaudeTokenRefresher` e `ClaudeUsageCLI` entram (renovação e fallback via subprocesso `claude`). Motivo: decisão do usuário, fidelidade ao comportamento do codenotch. Só rodam com o interruptor do A1 ligado.
- **A5** — mantido como no original: Codex via `CodexLocalProvider` (rede, `wham/usage`). Motivo: mesma diretriz de fidelidade.
- **A3** — divergência única do original: a leitura silenciosa do Keychain passa a valer só para a query do item do Claude (`kSecUseAuthenticationUI = kSecUseAuthenticationUIFail` / `LAContext.interactionNotAllowed` na própria query), em vez de `SecKeychainSetUserInteractionAllowed(false)` global. Motivo: o global pode derrubar a leitura dos segredos do webhook do Knobler se coincidir. Marcar com `// knobler:` no arquivo vendorizado.
- **A8** — sem trabalho de port de SO: nenhum símbolo macOS 15+ no conjunto.
- **Aviso de sessão** — igual ao original: `SessionCompletionWatcher` dispara aviso no notch fechado + som (chime/peek do codenotch) em busy→done/waiting.
