#!/usr/bin/env node
// E2E dos adapters de solicitação de agente contra uma API que imita o
// contrato do app: primeira resposta vence, resultado de leitura única,
// 401/413/400. Nenhuma decisão pode ser inventada quando algo dá errado.

import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = dirname(fileURLToPath(import.meta.url));
const BRIDGE = join(ROOT, "codex-agent-bridge.mjs");
const HOOK = join(ROOT, "claude-hook", "knobler-permission.sh");
const TOKEN = "e2e-token";
const MAX_BODY = 32 * 1024;
const CANARIES = ["/tmp/knobler-e2e-semicolon", "/tmp/knobler-e2e-subshell", "/tmp/knobler-e2e-backtick"];
const HOSTILE = `printf hi; touch ${CANARIES[0]} && $(touch ${CANARIES[1]}) \`touch ${CANARIES[2]}\``;

const work = await mkdtemp(join(tmpdir(), "knobler-agent-e2e-"));
const tokenFile = join(work, "token");
await writeFile(tokenFile, TOKEN, { mode: 0o600 });
for (const canary of CANARIES) await rm(canary, { force: true });

// Estado por solicitação, como no app: pendente → resultado → consumido.
const requests = new Map();
const api = createServer((req, res) => {
  if (req.headers.authorization !== `Bearer ${TOKEN}`) return end(res, 401, { ok: false });
  const chunks = [];
  req.on("data", (chunk) => chunks.push(chunk));
  req.on("end", () => {
    const body = Buffer.concat(chunks);
    if (body.byteLength > MAX_BODY) return end(res, 413, { ok: false });
    const [, , id, verb] = req.url.split("/");

    if (req.method === "POST" && req.url === "/agent-requests") {
      let card;
      try {
        card = JSON.parse(body.toString("utf8"));
      } catch {
        return end(res, 400, { ok: false });
      }
      requests.set(card.id, { card, result: null, consumed: false });
      return end(res, 200, { ok: true });
    }
    const entry = requests.get(id);
    if (!entry) return end(res, 404, { ok: false });

    if (req.method === "POST" && verb === "resolve") {
      const action = JSON.parse(body.toString("utf8")).action;
      const responder = req.headers["x-e2e-responder"] ?? "nob";
      if (!entry.result) entry.result = { action, responder, state: "resolved" }; // primeira vence
      return end(res, 200, { ok: true });
    }
    if (req.method === "POST" && verb === "dismiss") {
      entry.result ??= { action: "cancel", responder: "nob", state: "dismissed" };
      return end(res, 200, { ok: true });
    }
    if (req.method === "GET" && !verb) {
      if (!entry.result) return end(res, 200, { id, state: "pending" });
      if (entry.consumed) return end(res, 404, { ok: false });
      entry.consumed = true;
      return end(res, 200, { id, state: entry.result.state, result: entry.result });
    }
    return end(res, 404, { ok: false });
  });
});
await new Promise((resolve) => api.listen(0, "127.0.0.1", resolve));
const PORT = api.address().port;

try {
  await testRace();
  await testApiDown();
  await testExpiryNeverAllows();
  await testHostileCommandIsInert();
  await testRejectedPayloads();
  console.log("agent-requests e2e: OK");
} catch (error) {
  console.error(`agent-requests e2e: ${error.message}`);
  process.exitCode = 1;
} finally {
  api.close();
  await rm(work, { recursive: true, force: true });
}

// Terminal e NOB respondendo na mesma janela: um vencedor, um card fechado.
async function testRace() {
  requests.set("race-warmup", { card: { id: "race-warmup" }, result: null, consumed: false });
  await resolve("race-warmup", "allow", "nob"); // primeira conexão paga o setup do socket

  requests.set("race-1", { card: { id: "race-1" }, result: null, consumed: false });
  const started = Date.now();
  await Promise.all([
    resolve("race-1", "deny", "terminal"),
    resolve("race-1", "allow", "nob"),
  ]);
  assert(Date.now() - started < 10, "as duas respostas precisam disputar na mesma janela de 10 ms");

  const entry = requests.get("race-1");
  assert(entry.result !== null, "corrida sem vencedor");
  assert(["terminal", "nob"].includes(entry.result.responder), "vencedor inesperado");

  const first = await read("race-1");
  assert(first.state === "resolved" && first.result.action === entry.result.action, "resultado divergente");
  const second = await read("race-1");
  assert(second === 404, "o resultado precisa ser consumido na primeira leitura");
}

// API fora: nenhum adapter pode devolver decisão.
async function testApiDown() {
  const hook = await runHook(claudePayload("hook-down"), 1);
  assert(hook.code === 0 && hook.stdout.trim() === "", "hook do Claude respondeu com a API fora");

  const bridge = await runBridge(codexFixture("codex-down"), 1);
  assert(bridge.code === 0 && bridge.stdout.trim() === "", "ponte do Codex respondeu com a API fora");
}

// Expirado/cancelado é decisão do sistema — nunca vira allow.
async function testExpiryNeverAllows() {
  const hookId = await publishThen("claude", (id) => {
    requests.get(id).result = { action: "cancel", responder: "system", state: "expired" };
  }, claudePayload("hook-expired"));
  assert(hookId.stdout.trim() === "", "expiração virou decisão no hook do Claude");

  const bridgeId = await publishThen("codex", (id) => {
    requests.get(id).result = { action: "cancel", responder: "system", state: "expired" };
  }, codexFixture("codex-expired"));
  const responses = bridgeId.stdout.trim();
  assert(responses === "" || !responses.includes("accept"), "expiração virou accept na ponte do Codex");
}

// O comando é dado: atravessa como texto e nada dele é executado.
async function testHostileCommandIsInert() {
  const fixture = codexFixture("codex-hostile", HOSTILE);
  const run = await publishThen("codex", (id) => {
    requests.get(id).result = { action: "deny", responder: "nob", state: "resolved" };
  }, fixture);
  assert(run.code === 0, `ponte falhou: ${run.stderr}`);

  const card = [...requests.values()].map((entry) => entry.card).find((entry) => entry.summary === HOSTILE);
  assert(card !== undefined, "o comando não chegou íntegro ao card");
  for (const canary of CANARIES) assert(!existsSync(canary), `metacaractere executado: ${canary}`);
}

// 413 e 400 do app precisam derrubar a decisão, não escorregar para allow.
async function testRejectedPayloads() {
  const huge = await runHook(claudePayload("hook-huge", "x".repeat(MAX_BODY)), PORT);
  assert(huge.code === 0 && huge.stdout.trim() === "", "payload de 413 virou decisão");

  const status = await post("/agent-requests", "{", TOKEN);
  assert(status === 400, `JSON malformado devolveu ${status}`);
  assert(await post("/agent-requests", "{}", "token-errado") === 401, "token errado precisa dar 401");
  assert(await post("/agent-requests", "x".repeat(MAX_BODY + 1), TOKEN) === 413, "corpo grande precisa dar 413");
}

// Roda um adapter e resolve a solicitação assim que ela é publicada.
async function publishThen(agent, decide, input) {
  const before = new Set(requests.keys());
  const run = agent === "claude" ? runHook(input, PORT) : runBridge(input, PORT);
  const deadline = Date.now() + 5_000;
  while (Date.now() < deadline) {
    const fresh = [...requests.keys()].find((id) => !before.has(id));
    if (fresh) {
      decide(fresh);
      break;
    }
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  return run;
}

function claudePayload(session, command = "npm test") {
  return JSON.stringify({
    session_id: session,
    tool_name: "Bash",
    tool_input: { command, description: "Rodar testes" },
    permission_suggestions: [],
  });
}

function codexFixture(item, command = "printf fixture") {
  return `${JSON.stringify({
    jsonrpc: "2.0",
    id: 21,
    method: "item/commandExecution/requestApproval",
    params: { threadId: "thread-e2e", turnId: "turn-e2e", itemId: item, startedAtMs: 0, command, cwd: "/tmp" },
  })}\n`;
}

function runHook(input, port) {
  return capture("/bin/bash", [HOOK], port, input);
}

function runBridge(fixture, port) {
  const path = join(work, `fixture-${requests.size}-${port}.jsonl`);
  return writeFile(path, fixture).then(() => capture(process.execPath, [BRIDGE, "--fixture", path], port));
}

function capture(command, args, port, input) {
  return new Promise((resolve) => {
    const child = spawn(command, args, {
      env: {
        ...process.env,
        KNOBLER_PORT: String(port),
        KNOBLER_AGENT_REQUEST_TOKEN: tokenFile,
        KNOBLER_AGENT_REQUEST_TIMEOUT_MS: "5000",
      },
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("close", (code) => resolve({ code, stdout, stderr }));
    if (input !== undefined) child.stdin.write(input);
    child.stdin.end();
  });
}

function resolve(id, action, responder) {
  return fetch(`http://127.0.0.1:${PORT}/agent-requests/${id}/resolve`, {
    method: "POST",
    headers: { Authorization: `Bearer ${TOKEN}`, "x-e2e-responder": responder },
    body: JSON.stringify({ action }),
  });
}

async function read(id) {
  const response = await fetch(`http://127.0.0.1:${PORT}/agent-requests/${id}`, {
    headers: { Authorization: `Bearer ${TOKEN}` },
  });
  return response.ok ? response.json() : response.status;
}

async function post(path, body, token) {
  const response = await fetch(`http://127.0.0.1:${PORT}${path}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
    body,
  });
  return response.status;
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function end(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(payload) });
  res.end(payload);
}
