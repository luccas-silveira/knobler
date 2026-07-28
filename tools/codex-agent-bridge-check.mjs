#!/usr/bin/env node
// Valida a ponte do Codex contra uma API de solicitações falsa: mapeamento de
// decisões, payload publicado, fallback com API fora e não-execução do comando.

import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = dirname(fileURLToPath(import.meta.url));
const BRIDGE = join(ROOT, "codex-agent-bridge.mjs");
const FIXTURE = join(ROOT, "fixtures", "codex-approval-requests.jsonl");
const CANARY = "/tmp/knobler-codex-bridge-should-not-run";
const TOKEN = "bridge-test-token";

const work = await mkdtemp(join(tmpdir(), "knobler-codex-bridge-"));
const tokenFile = join(work, "token");
await writeFile(tokenFile, TOKEN, { mode: 0o600 });
await rm(CANARY, { force: true });

const published = [];
let decision = "allow";
const api = createServer((req, res) => {
  if (req.headers.authorization !== `Bearer ${TOKEN}`) return end(res, 401, { ok: false });
  const chunks = [];
  req.on("data", (chunk) => chunks.push(chunk));
  req.on("end", () => {
    const body = Buffer.concat(chunks).toString("utf8");
    if (req.method === "POST" && req.url === "/agent-requests") {
      published.push(JSON.parse(body));
      return end(res, 200, { ok: true });
    }
    if (req.method === "GET" && req.url.startsWith("/agent-requests/")) {
      const id = req.url.slice("/agent-requests/".length);
      return end(res, 200, {
        id,
        state: "resolved",
        result: { action: decision, responder: "nob", state: "resolved" },
      });
    }
    return end(res, 404, { ok: false });
  });
});
await new Promise((resolve) => api.listen(0, "127.0.0.1", resolve));
const port = api.address().port;

const permissions = { network: { enabled: true } };
const cases = [
  ["allow", [{ decision: "accept" }, { decision: "accept" }, { permissions, scope: "turn" }]],
  ["allowForSession", [
    { decision: "acceptForSession" },
    { decision: "acceptForSession" },
    { permissions, scope: "session" },
  ]],
  ["deny", [{ decision: "decline" }, { decision: "decline" }, { permissions: {}, scope: "turn" }]],
  ["cancel", [{ decision: "cancel" }, { decision: "cancel" }, { permissions: {}, scope: "turn" }]],
];

try {
  for (const [action, expected] of cases) {
    decision = action;
    published.length = 0;
    const run = await runBridge(port);
    assert(run.code === 0, `${action}: saída ${run.code}\n${run.stderr}`);
    const responses = parseLines(run.stdout);
    assert(responses.length === 3, `${action}: esperava 3 respostas, veio ${responses.length}`);
    responses.forEach((response, index) => {
      assert(response.jsonrpc === "2.0", `${action}: resposta sem jsonrpc`);
      assert(response.id === 11 + index, `${action}: id ${response.id} fora de ordem`);
      same(response.result, expected[index], `${action}: resposta ${index}`);
    });
    assertPublished(published, action);
  }

  // API fora: nenhuma decisão, aprovação nativa do Codex intacta.
  const down = await runBridge(1);
  assert(down.code === 0, `API fora: saída ${down.code}`);
  assert(down.stdout.trim() === "", "API fora: não pode devolver decisão");
  assert(/codex bridge:/.test(down.stderr), "API fora: falta linha de diagnóstico");

  assert(!existsSync(CANARY), "a ponte executou o comando da fixture");
  console.log("codex bridge: OK");
} catch (error) {
  console.error(`codex bridge: ${error.message}`);
  process.exitCode = 1;
} finally {
  api.close();
  await rm(work, { recursive: true, force: true });
}

function runBridge(apiPort) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [BRIDGE, "--fixture", FIXTURE], {
      env: {
        ...process.env,
        KNOBLER_PORT: String(apiPort),
        KNOBLER_AGENT_REQUEST_TOKEN: tokenFile,
        KNOBLER_AGENT_REQUEST_TIMEOUT_MS: "3000",
      },
    });
    let stdout = "";
    let stderr = "";
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("close", (code) => resolve({ code, stdout, stderr }));
  });
}

function assertPublished(cards, action) {
  assert(cards.length === 3, `${action}: publicou ${cards.length} cards`);
  const ids = new Set(cards.map((card) => card.id));
  assert(ids.size === 3, `${action}: ids repetidos`);
  for (const card of cards) {
    assert(card.agent === "codex", `${action}: agent ${card.agent}`);
    assert(card.kind === "permission", `${action}: kind ${card.kind}`);
    assert(card.source === "cli", `${action}: source ${card.source}`);
    assert(/^[A-Za-z0-9._-]{1,128}$/.test(card.id), `${action}: id inválido ${card.id}`);
    assert(card.summary.length <= 4096 && card.summary.trim() !== "", `${action}: summary inválido`);
    assert(card.actions.length >= 2 && card.actions.length <= 8, `${action}: ações fora do limite`);
    assert(
      card.actions.some((entry) => entry.action === action),
      `${action}: ação resolvida não estava disponível`,
    );
  }
  const command = cards.find((card) => card.title.includes("Comando"));
  assert(command !== undefined, `${action}: falta o card do comando`);
  assert(command.summary.includes(CANARY), `${action}: comando não aparece no resumo`);
  assert(JSON.parse(command.details).cwd === "/tmp", `${action}: detalhes sem cwd`);
}

function parseLines(text) {
  return text.trimEnd().split("\n").filter(Boolean).map((line) => JSON.parse(line));
}

function same(actual, expected, label) {
  const [a, b] = [JSON.stringify(actual), JSON.stringify(expected)];
  assert(a === b, `${label}: ${a} != ${b}`);
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function end(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(payload) });
  res.end(payload);
}
