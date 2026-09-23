# Pesquisa — Uso e sessões de Claude/Codex no notch

Spec: `docs/superpowers/specs/2026-09-23-agentes-uso-design.md`
Clone de referência: `scratchpad/codenotch/Sources` (caminhos abaixo relativos a ele).

## Achados

### A1 — Ler o limite do Claude usa o token OAuth do Claude Code num endpoint não documentado
- Fonte: `Providers/ClaudeOAuthProvider.swift:34,376`; Consumer Terms de 2026-02-20 (https://www.theregister.com/2026/02/20/anthropic_clarifies_ban_third_party_claude_access/); 429 sem `User-Agent: claude-code/<v>` (https://github.com/anthropics/claude-code/issues/31021)
- Contradiz a spec: sim
- Pergunta: o anel do Claude depende de algo que os termos cobrem ao pé da letra e que pode quebrar sem aviso. Liga por padrão, fica atrás de um interruptor desligado, ou sai?

### A2 — Ler o token do Claude no Keychain gera prompt de senha várias vezes por dia
- Fonte: Claude Code recria o item a cada renovação (~8h), apagando o "Permitir sempre" (https://github.com/steipete/CodexBar/issues/485, /2115, /3798); `Providers/ClaudeCredentials.swift:48`
- Contradiz a spec: sim
- Pergunta: o usuário aceita ver "Knobler quer acessar o Keychain" algumas vezes por dia em troca do anel do Claude?

### A3 — `KeychainPrompt` desliga a interação do Keychain pro app inteiro durante a leitura
- Fonte: `Providers/KeychainPrompt.swift:116-125` (`SecKeychainSetUserInteractionAllowed(false)`)
- Contradiz a spec: parcial
- Pergunta: isso pode fazer a leitura dos segredos do webhook do próprio Knobler falhar em silêncio se coincidir. Reescrevemos essa parte?

### A4 — `ClaudeTokenRefresher` e `ClaudeUsageCLI` rodam o `claude` em subprocesso
- Fonte: `Providers/ClaudeTokenRefresher.swift:216-230` (reescreve o item do Keychain); `Providers/ClaudeUsageCLI.swift:54` (cria sessão em `~/.claude/projects` a cada refresh)
- Contradiz a spec: sim (a spec traz o refresher)
- Pergunta: renovar o token por fora pode deslogar o Claude Code. Cortamos os dois?

### A5 — O Codex tem limite local, sem rede e sem token
- Fonte: eventos `token_count` com `rate_limits` em `~/.codex/sessions/YYYY/MM/DD/*.jsonl` (https://github.com/steipete/CodexBar/blob/main/docs/codex.md); `CodexLocalProvider` usa `chatgpt.com/backend-api/wham/usage`
- Contradiz a spec: parcial
- Pergunta: o anel do Codex fica mais seguro lendo o arquivo local, com a ressalva de só atualizar quando você usa o Codex. Aceita?

### A6 — Sessões do Codex bridge do Knobler vão aparecer na lista
- Fonte: `Sessions/CodexActivityMonitor.swift:229-330` lê a tabela `threads` do SQLite, não pid; `tools/codex-agent-bridge.mjs:72`
- Contradiz a spec: sim (`ignoredPIDs` não funciona pro Codex)
- Pergunta: sessão iniciada pela ponte deve aparecer? Provavelmente sim — é uma sessão real do usuário.

### A7 — O conjunto depende de ~10 tipos fora dele; zstd é evitável
- Fonte: `Model/UsageModel.swift` (530L, `L10n` 35×), `Providers/ProviderAccount.swift`, `ProviderGlyph.swift` (puxa `GlyphOutline` 92 KB), `UsageArchive`, `SQLiteStore` (70L), `Log`, `Runtime`, `Preferences`; `ClaudeDesktopUsageCache` é injeção opcional
- Contradiz a spec: não (shim previsto)

### A8 — macOS 14.2 não é bloqueio
- Fonte: nenhum símbolo 15+ nos 25 arquivos; `@Observable` extra é 14.0; Swift 5.0 nos dois `project.yml`
- Contradiz a spec: parcial (a spec supunha trabalho de port de SO; não há)

### A9 — `~/.claude/sessions/<pid>.json` é local, sem token, mas não documentado
- Fonte: arquivo real v2.1.280 tem `status` idle/busy/waiting; arquivo órfão após kill (https://github.com/minchenlee/c9watch/pull/132) — `ProcessLiveness` já trata
- Contradiz a spec: não

### A10 — `ActivityRingView` serve pro anel de %
- Fonte: `Knobler/NotchView.swift:1624` (`progress: Double?` 0–1); uso igual em `Knobler/AirPodsViews.swift:27`
- Contradiz a spec: não

## Fila do grill

1. A1 + A2 — anel do Claude via rede/Keychain: padrão ligado, opt-in, ou fora? (trava A3, A4)
2. A4 — cortar refresher e CLI
3. A3 — reescrever a leitura do Keychain sem desligar a interação global
4. A5 — Codex pelo arquivo local em vez da rede
5. A6 — sessões da ponte aparecem
