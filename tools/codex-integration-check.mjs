#!/usr/bin/env node
// Gate das superfícies do Codex: o que a instalação local realmente suporta.
// Não inicia turno, não instala nada e não executa comando do agente.

import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { createServer } from "node:http";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = dirname(fileURLToPath(import.meta.url));
const BRIDGE = join(ROOT, "codex-agent-bridge.mjs");
const TOKEN = "integration-test-token";

const work = await mkdtemp(join(tmpdir(), "knobler-codex-integration-"));
const tokenFile = join(work, "token");
await writeFile(tokenFile, TOKEN, { mode: 0o600 });

try {
  const version = (await run("codex", ["--version"])).stdout.trim();
  assert(version.length > 0, "codex --version não respondeu");
  console.log(`codex integration: ${version}`);

  const capability = await run("node", [BRIDGE, "--check"]);
  assert(capability.code === 0, `capability: ${capability.stderr.trim()}`);
  console.log("codex integration: capability OK");

  const publishes = await proxyHandshake();
  assert(publishes === 0, `handshake publicou ${publishes} solicitações — aprovação falsa`);
  console.log("codex integration: proxy handshake OK, sem aprovação falsa");

  const fixtures = await run("node", [join(ROOT, "codex-agent-bridge-check.mjs")]);
  assert(fixtures.code === 0, `fixtures: ${fixtures.stdout.trim()}${fixtures.stderr.trim()}`);
  console.log("codex integration: troca de aprovação por fixture OK");

  console.log(`codex integration: daemon ${await daemonSupport()}`);
  console.log("codex integration: OK");
} catch (error) {
  console.error(`codex integration: ${error.message}`);
  process.exitCode = 1;
} finally {
  await rm(work, { recursive: true, force: true });
}

// Sobe a ponte como app-server, faz um initialize e confere que a resposta
// atravessa o proxy sem que nada seja publicado no NOB: sem pedido de
// aprovação, sem card.
async function proxyHandshake() {
  const published = [];
  const api = createServer((req, res) => {
    published.push(req.url);
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end('{"ok":true}');
  });
  await new Promise((resolve) => api.listen(0, "127.0.0.1", resolve));

  const bridge = spawn(process.execPath, [BRIDGE], {
    env: {
      ...process.env,
      KNOBLER_PORT: String(api.address().port),
      KNOBLER_AGENT_REQUEST_TOKEN: tokenFile,
    },
    stdio: ["pipe", "pipe", "pipe"],
  });

  try {
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error("initialize não voltou pelo proxy")), 20_000);
      createInterface({ input: bridge.stdout }).on("line", (line) => {
        let message;
        try {
          message = JSON.parse(line);
        } catch {
          return;
        }
        if (message.id !== 1) return;
        clearTimeout(timer);
        if (message.error) reject(new Error(message.error.message ?? "initialize falhou"));
        else resolve();
      });
      bridge.stdin.write(`${JSON.stringify({
        jsonrpc: "2.0",
        id: 1,
        method: "initialize",
        params: { clientInfo: { name: "knobler-codex-integration-check", version: "1.0.0" }, experimentalApi: true },
      })}\n`);
    });
    return published.length;
  } finally {
    bridge.kill();
    api.close();
  }
}

// App e extensão de IDE conversam com o daemon, não com o stdio da ponte. O
// daemon exige a instalação standalone do instalador oficial; num Codex de
// Homebrew ele nem sobe, então essas superfícies ficam com aprovação nativa.
async function daemonSupport() {
  const status = await run("codex", ["app-server", "daemon", "version"]);
  if (status.code === 0) return "ativo — sessões do app/IDE podem estar anexadas";
  if (!existsSync(join(homedir(), ".codex/packages/standalone/current/codex"))) {
    return "indisponível (instalação não-standalone) — app/IDE seguem com aprovação nativa";
  }
  return "parado — app/IDE seguem com aprovação nativa; a ponte cobre a CLI";
}

function run(command, args) {
  return new Promise((resolve) => {
    const child = spawn(command, args, { stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("error", (error) => resolve({ code: 1, stdout, stderr: error.message }));
    child.on("close", (code) => resolve({ code, stdout, stderr }));
  });
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}
