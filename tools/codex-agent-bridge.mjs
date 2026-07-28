#!/usr/bin/env node
// Ponte entre o app-server do Codex e a API de solicitações do Knobler.
//
//   node tools/codex-agent-bridge.mjs                  proxy stdio ↔ app-server
//   node tools/codex-agent-bridge.mjs --check          só detecta capacidade
//   node tools/codex-agent-bridge.mjs --fixture <file> roteia pedidos gravados
//
// Só espelha pedidos de aprovação: nunca executa comando, nem aplica diff, nem
// concede permissão sozinha. Sem decisão do NOB (API fora, timeout, payload
// estranho) o pedido volta pro fluxo nativo do Codex.

import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";

const APPROVAL_METHODS = [
  "item/commandExecution/requestApproval",
  "item/fileChange/requestApproval",
  "item/permissions/requestApproval",
];
const PORT = process.env.KNOBLER_PORT ?? "4477";
const TOKEN_FILE = process.env.KNOBLER_AGENT_REQUEST_TOKEN
  ?? join(homedir(), "Library/Application Support/Knobler/agent-request-token");
const TIMEOUT_MS = Number(process.env.KNOBLER_AGENT_REQUEST_TIMEOUT_MS ?? 570_000);
const POLL_MS = 300;

const fixtureFlag = process.argv.indexOf("--fixture");
if (process.argv.includes("--check")) await runCheck();
else if (fixtureFlag >= 0) await runFixture(process.argv[fixtureFlag + 1]);
else await runProxy();

async function runCheck() {
  const missing = await missingApprovalMethods();
  if (missing === null) {
    console.error("codex bridge: não consegui gerar o schema do app-server");
    process.exitCode = 1;
    return;
  }
  if (missing.length > 0) {
    console.error(`codex bridge: app-server sem ${missing.join(", ")} — aprovação nativa mantida`);
    process.exitCode = 1;
    return;
  }
  console.log("codex bridge: capability OK");
}

// Modo fixture: um pedido por linha, uma resposta JSON-RPC por linha. Não sobe
// app-server, então serve de checagem determinística do mapeamento.
async function runFixture(path) {
  if (!path) {
    console.error("codex bridge: uso --fixture <arquivo.jsonl>");
    process.exitCode = 2;
    return;
  }
  const lines = (await readFile(path, "utf8")).trimEnd().split("\n").filter(Boolean);
  for (const line of lines) {
    const message = JSON.parse(line);
    const result = await mirror(message);
    if (result) process.stdout.write(`${JSON.stringify({ jsonrpc: "2.0", id: message.id, result })}\n`);
  }
}

// Modo proxy: fala JSON-RPC por linhas com um cliente no stdio e repassa tudo
// pro app-server. Só os pedidos de aprovação saem do fluxo e viram card.
async function runProxy() {
  const missing = await missingApprovalMethods();
  const intercept = missing !== null && missing.length === 0;
  if (!intercept) console.error("codex bridge: aprovações não espelhadas — fluxo nativo do Codex mantido");

  const server = spawn("codex", ["app-server", "--listen", "stdio://"], { stdio: ["pipe", "pipe", "inherit"] });
  server.on("exit", (code) => process.exit(code ?? 0));
  createInterface({ input: process.stdin }).on("line", (line) => server.stdin.write(`${line}\n`));

  createInterface({ input: server.stdout }).on("line", async (line) => {
    let message;
    try {
      message = JSON.parse(line);
    } catch {
      process.stdout.write(`${line}\n`);
      return;
    }
    if (!intercept || !APPROVAL_METHODS.includes(message.method)) {
      process.stdout.write(`${line}\n`);
      return;
    }
    const result = await mirror(message);
    if (result) server.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id: message.id, result })}\n`);
    else process.stdout.write(`${line}\n`); // sem decisão: o cliente decide como sempre
  });
}

// Publica o pedido, espera a decisão e devolve o `result` do JSON-RPC — ou null
// pra deixar a aprovação nativa acontecer.
async function mirror(message) {
  const card = toCard(message);
  if (!card) return null;

  const token = await loadToken();
  if (!token) {
    console.error("codex bridge: token de solicitações indisponível");
    return null;
  }
  if (!await api("POST", "/agent-requests", token, card)) {
    console.error("codex bridge: API local indisponível");
    return null;
  }

  const deadline = Date.now() + TIMEOUT_MS;
  while (Date.now() < deadline) {
    const state = await api("GET", `/agent-requests/${card.id}`, token);
    if (!state) {
      console.error("codex bridge: API local caiu no meio");
      return null;
    }
    if ((state.state ?? "pending") !== "pending") return toResult(message, state.result?.action);
    await new Promise((resolve) => setTimeout(resolve, POLL_MS));
  }
  await api("POST", `/agent-requests/${card.id}/dismiss`, token);
  console.error("codex bridge: sem resposta no NOB");
  return null;
}

function toCard(message) {
  const params = message?.params;
  if (typeof message?.id !== "number" || !params?.itemId || !params?.threadId) return null;
  const id = requestID(message);

  switch (message.method) {
    case "item/commandExecution/requestApproval": {
      const command = typeof params.command === "string" ? params.command : "";
      if (!command) return null;
      return {
        id, agent: "codex", kind: "permission", source: "cli",
        title: "Codex · Comando",
        summary: command,
        details: JSON.stringify(params),
        actions: decisionActions(params.availableDecisions),
      };
    }
    case "item/fileChange/requestApproval":
      return {
        id, agent: "codex", kind: "permission", source: "cli",
        title: "Codex · Alteração de arquivo",
        summary: params.reason || `Aplicar alterações do item ${params.itemId}`,
        details: JSON.stringify(params),
        actions: decisionActions(params.availableDecisions),
      };
    case "item/permissions/requestApproval":
      if (typeof params.permissions !== "object" || params.permissions === null) return null;
      return {
        id, agent: "codex", kind: "permission", source: "cli",
        title: "Codex · Permissões",
        summary: params.reason || `Conceder permissões em ${params.cwd ?? "?"}`,
        details: JSON.stringify(params),
        actions: decisionActions(null),
      };
    default:
      return null;
  }
}

// A decisão vira o `result` de cada schema. Ação desconhecida ou ausente =
// nenhuma resposta, e o Codex segue com a aprovação nativa.
function toResult(message, action) {
  if (message.method === "item/permissions/requestApproval") {
    switch (action) {
      case "allow": return { permissions: message.params.permissions, scope: "turn" };
      case "allowForSession": return { permissions: message.params.permissions, scope: "session" };
      case "deny": case "cancel": return { permissions: {}, scope: "turn" };
      default: return null;
    }
  }
  const decision = { allow: "accept", allowForSession: "acceptForSession", deny: "decline", cancel: "cancel" }[action];
  return decision ? { decision } : null;
}

// Só as decisões simples viram botão. Emendas de execpolicy e de política de
// rede ficam de fora: são regras persistentes, não uma aprovação pontual.
function decisionActions(available) {
  const supported = { accept: "allow", acceptForSession: "allowForSession", decline: "deny", cancel: "cancel" };
  const decisions = Array.isArray(available)
    ? available.filter((entry) => typeof entry === "string" && entry in supported)
    : Object.keys(supported);
  const actions = (decisions.length > 0 ? decisions : Object.keys(supported)).map((entry) => ({ action: supported[entry] }));
  return actions.some((entry) => entry.action === "deny") ? actions : [...actions, { action: "deny" }];
}

function requestID(message) {
  const slug = `${message.params.threadId}-${message.params.approvalId ?? message.params.itemId}-${message.id}`;
  return `codex-${slug}`.replace(/[^A-Za-z0-9._-]/g, "-").slice(0, 128);
}

async function loadToken() {
  try {
    const token = (await readFile(TOKEN_FILE, "utf8")).trim();
    return token || null;
  } catch {
    return null;
  }
}

async function api(method, path, token, body) {
  try {
    const response = await fetch(`http://127.0.0.1:${PORT}${path}`, {
      method,
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: body ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(2000),
    });
    if (!response.ok) return null;
    return await response.json();
  } catch {
    return null;
  }
}

// Capacidade = os três pedidos de aprovação existirem no schema da versão
// instalada. É evidência da build local, não promessa de estabilidade.
async function missingApprovalMethods() {
  const out = await mkdtemp(join(tmpdir(), "knobler-codex-schema-"));
  try {
    const generated = await new Promise((resolve) => {
      const child = spawn("codex", ["app-server", "generate-json-schema", "--experimental", "--out", out], {
        stdio: ["ignore", "ignore", "ignore"],
      });
      child.on("error", () => resolve(false));
      child.on("exit", (code) => resolve(code === 0));
    });
    if (!generated) return null;
    const schema = JSON.parse(await readFile(join(out, "ServerRequest.json"), "utf8"));
    const methods = (schema.oneOf ?? []).flatMap((entry) => entry.properties?.method?.enum ?? []);
    return APPROVAL_METHODS.filter((method) => !methods.includes(method));
  } catch {
    return null;
  } finally {
    await rm(out, { recursive: true, force: true });
  }
}
