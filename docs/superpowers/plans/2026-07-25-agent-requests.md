# Agent Requests in the NOB Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Mirror Claude Code and Codex questions and approval requests in the NOB while preserving the original terminal/app/IDE interaction and first-response-wins semantics.

**Architecture:** Add an AgentRequest domain/store and loopback API beside Ask. Claude uses AskUserQuestion and PermissionRequest hooks. Codex uses an adapter around the local app-server approval RPCs, guarded by a capability check because that protocol is experimental. The NOB only displays data and returns decisions; it never executes commands or applies diffs.

**Tech Stack:** Swift 5.9, SwiftUI/AppKit, existing NotchAPIServer and AskStore patterns, shell hooks, Node.js bridge, Codex CLI app-server JSON-RPC.

## Global Constraints

- Keep transport on 127.0.0.1 or a Unix socket.
- New resolution endpoints require an ephemeral 0600 session token; existing /ask remains compatible.
- First valid response wins; duplicates are no-ops.
- Commands, paths, diffs, and answers are data only.
- Compact card by default; details require explicit expansion.
- Timeout, malformed payload, unavailable bridge, or closed NOB must leave native agent flow safe.
- No OCR, coordinate clicks, synthetic keystrokes, or terminal scraping.
- No new package dependency.

---

### Task 1: Codex app-server capability spike

Files:
- Create tools/codex-agent-spike.mjs
- Create tools/fixtures/codex-command-approval.jsonl
- Modify docs/superpowers/specs/2026-07-25-agent-requests-research.md

Interfaces:
- Consumes codex app-server --listen stdio:// JSON-RPC.
- Produces a deterministic capability report and fixture approval response.

- [ ] Step 1: Create `tools/fixtures/codex-command-approval.jsonl` with exactly these two JSON lines: `{"jsonrpc":"2.0","id":7,"method":"item/commandExecution/requestApproval","params":{"threadId":"thread-fixture","turnId":"turn-fixture","itemId":"item-fixture","command":"printf fixture","cwd":"/tmp","reason":"fixture","availableApprovalDecisions":["accept","decline","cancel"]}}` and `{"jsonrpc":"2.0","id":7,"result":{"decision":"accept"}}`.
- [ ] Step 2: Run node tools/codex-agent-spike.mjs --fixture tools/fixtures/codex-command-approval.jsonl. Expected before implementation: non-zero, codex spike: missing.
- [ ] Step 3: Implement the Node harness: spawn app-server, send initialize with experimentalApi true, validate platformOs/platformFamily/userAgent, parse the fixture, emit the exact response, and print codex spike: OK. It must not execute a real command.
- [ ] Step 4: Run the check and git diff --check; record the installed-version limitation in the research document.
- [ ] Step 5: Commit with git add tools/codex-agent-spike.mjs tools/fixtures/codex-command-approval.jsonl docs/superpowers/specs/2026-07-25-agent-requests-research.md and git commit -m "test: probe Codex app-server approval protocol".

### Task 2: AgentRequest domain and reducer

Files:
- Create Knobler/AgentRequestModels.swift
- Create Knobler/AgentRequestStore.swift
- Create tools/agentrequestcheck.swift
- Modify project.yml

Interfaces:
- Produces AgentRequest, AgentRequestAction, AgentRequestState, AgentRequestReducer and AgentRequestStore.send(_:) for later tasks.

- [ ] Step 1: Write agentrequestcheck assertions for enqueue, FIFO promotion, resolve, dismiss, expiry, duplicate IDs and terminal-vs-NOB first-response.
- [ ] Step 2: Run swiftc tools/agentrequestcheck.swift -o /tmp/agentrequestcheck and verify it fails because the domain types do not exist.
- [ ] Step 3: Implement Codable models with explicit fields: `AgentName` = `claude|codex`; `AgentRequestKind` = `question|permission`; `AgentRequestSource` = `terminal|cli|ide`; `AgentRequestAction` = `allow|allowForSession|deny|cancel|option(String)|text(String)`; `AgentRequestResult` stores the winning action and responder; `AgentRequest` contains `id`, `agent`, `kind`, `title`, `summary`, optional `details`, `source`, `actions` and `state`; `AgentRequestState` contains optional `active`, FIFO `queue` and `results` keyed by request ID.
- [ ] Step 4: Implement a pure reducer with enqueue, resolve, dismiss and expire actions. Resolution is idempotent and promotes the next queued request synchronously.
- [ ] Step 5: Implement @MainActor AgentRequestStore with @Published private(set) state and resolveRemote/dismissRemote closures, then run the check and xcodebuild Debug.
- [ ] Step 6: Commit as feat(agent-requests): add shared request domain.

### Task 3: Authenticated loopback API

Files:
- Modify Knobler/NotchAPIServer.swift
- Modify Knobler/KnoblerApp.swift
- Modify docs/local-api.md
- Modify tools/knobler
- Create tools/agentrequest-api-check.swift

Interfaces:
- POST /agent-requests publishes.
- GET /agent-requests/<id> reads state/result.
- POST /agent-requests/<id>/resolve resolves.
- POST /agent-requests/<id>/dismiss cancels.

- [ ] Step 1: Add API checks for valid create, 401 without token, 200 with token, read-once result, malformed JSON 400 and oversized body 413.
- [ ] Step 2: At launch generate 32 random bytes, write base64 to ~/Library/Application Support/Knobler/agent-request-token with POSIX mode 0600, and keep /ask unauthenticated for compatibility.
- [ ] Step 3: Extend the existing HTTP parser; validate id, agent, kind, source, action count and body size before enqueueing. Duplicate resolution returns a no-op.
- [ ] Step 4: Add tools/knobler agent-request publish|wait|resolve without printing the token.
- [ ] Step 5: Run swiftc tools/agentrequest-api-check.swift -o /tmp/agentrequest-api-check && /tmp/agentrequest-api-check, git diff --check, xcodebuild Debug, then commit feat(agent-requests): add authenticated loopback API.

### Task 4: NOB card UI and multi-monitor wiring

Files:
- Create Knobler/AgentRequestCard.swift
- Modify Knobler/NotchView.swift
- Modify Knobler/KnoblerApp.swift
- Modify tools/main.swift and tools/snapshot.sh

Interfaces:
- Consumes AgentRequestStore.state.active.
- Produces compact/expanded card and synchronized resolution.

- [ ] Step 1: Add deterministic scenarios agent-permission-compact, agent-permission-expanded, agent-question and agent-request-race.
- [ ] Step 2: Implement compact card with agent icon, kind badge, summary capped at 160 characters, source, expand control and contextual actions.
- [ ] Step 3: Implement expanded selectable monospaced command/path/diff details. No displayed content is executable.
- [ ] Step 4: Give AgentRequest the same presentation priority as Ask, while Ask remains higher priority when active; fan out one store to all notch windows.
- [ ] Step 5: Run `./tools/snapshot.sh` (the existing harness renders all scenarios), verify the four new PNGs, run `git diff --check`, and commit `feat(agent-requests): render mirrored cards in the notch`.

### Task 5: Claude adapters

Files:
- Modify tools/claude-hook/knobler-ask.sh, install.sh, docs/ask.md and docs/local-api.md
- Create tools/claude-hook/knobler-permission.sh, tools/claude-hook/test.sh and tools/claude-hook/fixtures/permission-request.json

Interfaces:
- Consumes authenticated agent-request API.
- Produces native-safe Claude hook output and exact allow/deny decisions.

- [ ] Step 1: Feed the permission fixture to a fake API and assert PermissionRequest allow/deny JSON output; assert API-down exits successfully with no output.
- [ ] Step 2: Share only token loading, request IDs, polling deadlines and first-response handling; preserve the existing /ask contract.
- [ ] Step 3: Map tool_name, tool_input, permission_suggestions and session_id to AgentRequest. Use allowForSession only for an explicit Allow for session action.
- [ ] Step 4: Make install.sh add an idempotent PermissionRequest matcher without changing unrelated user hooks.
- [ ] Step 5: Run bash tools/claude-hook/test.sh and commit feat(agent-requests): mirror Claude permissions.

### Task 6: Codex app-server bridge

Files:
- Create tools/codex-agent-bridge.mjs, tools/codex-agent-bridge-check.mjs and docs/agent-requests.md
- Modify tools/knobler and docs/local-api.md

Interfaces:
- Consumes app-server JSON-RPC and AgentRequest API.
- Produces schema-specific approval responses.

- [ ] Step 1: Add fixtures for command, file-change and permissions approval requests; assert accept, acceptForSession, decline and cancel responses.
- [ ] Step 2: Spawn codex app-server --listen stdio://, initialize, forward approval requests to POST /agent-requests, retain JSON-RPC request IDs, and map NOB actions back to each schema response.
- [ ] Step 3: Require the three approval methods in capability detection; if absent, print one diagnostic line and leave native approval untouched.
- [ ] Step 4: Expose tools/knobler codex bridge and codex check; checks never launch a real turn or command.
- [ ] Step 5: Run node tools/codex-agent-bridge-check.mjs and ./tools/knobler codex check, then commit feat(agent-requests): bridge Codex approvals.

### Task 7: Codex surface integration gate

Files:
- Create tools/codex-integration-check.mjs
- Modify docs/agent-requests.md and docs/troubleshooting.md

Interfaces:
- Consumes bridge capability report and Codex --remote/app-server behavior.
- Produces support matrix for CLI, desktop app and IDE extension.

- [ ] Step 1: Run a harmless read-only CLI turn with approval policy on-request and assert no false approval.
- [ ] Step 2: Start a controlled app-server, connect the bridge, and run only the fixture approval exchange; record whether a separately launched client can remain attached.
- [ ] Step 3: Inspect documented app/IDE remote controls without UI automation. If no supported connection exists, retain native approvals and document the limitation.
- [ ] Step 4: Document exact launch commands, supported versions and fallback text.
- [ ] Step 5: Run node tools/codex-integration-check.mjs and commit docs(agent-requests): record Codex surface support.

### Task 8: E2E race, security and regression validation

Files:
- Create tools/agent-requests-e2e.mjs
- Modify tools/askcheck.swift, docs/agent-requests.md and CHANGELOG.md

Interfaces:
- Consumes all previous tasks.
- Produces repeatable validation and final documentation.

- [ ] Step 1: Resolve one request through simulated terminal and NOB within 10 ms; assert one winner and one closed card.
- [ ] Step 2: Stop the API before resolution and assert Claude/Codex exit without output or unsafe approval; assert expired never maps to allow.
- [ ] Step 3: Assert 401 wrong token, 413 oversized body, 400 malformed JSON and inert shell metacharacters.
- [ ] Step 4: Run swiftc tools/agentrequestcheck.swift -o /tmp/agentrequestcheck && /tmp/agentrequestcheck; swiftc tools/askcheck.swift -o /tmp/askcheck && /tmp/askcheck; node tools/codex-agent-spike.mjs --fixture tools/fixtures/codex-command-approval.jsonl; node tools/codex-agent-bridge-check.mjs; node tools/agent-requests-e2e.mjs; xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug -derivedDataPath /tmp/knobler-agent-requests-final build CODE_SIGNING_ALLOWED=NO. Expect every check OK and BUILD SUCCEEDED.
- [ ] Step 5: Commit tools/agent-requests-e2e.mjs tools/askcheck.swift docs/agent-requests.md CHANGELOG.md as test(agent-requests): validate agent mirror flows.
