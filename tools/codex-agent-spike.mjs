#!/usr/bin/env node

import { spawn } from "node:child_process";
import { readFile } from "node:fs/promises";
import { createInterface } from "node:readline";

const fixtureFlag = process.argv.indexOf("--fixture");
const fixturePath = fixtureFlag >= 0 ? process.argv[fixtureFlag + 1] : undefined;

if (!fixturePath || process.argv.length !== 4) {
  console.error("usage: node tools/codex-agent-spike.mjs --fixture <fixture.jsonl>");
  process.exit(2);
}

const fixture = await readFixture(fixturePath);
const server = spawn("codex", ["app-server", "--listen", "stdio://"], {
  stdio: ["pipe", "pipe", "pipe"],
});

let stderr = "";
server.stderr.setEncoding("utf8");
server.stderr.on("data", (chunk) => { stderr += chunk; });

try {
  const initialized = await initialize(server);
  validateCapability(initialized);
  console.log(`codex spike: capability ${JSON.stringify({
    platformOs: initialized.platformOs,
    platformFamily: initialized.platformFamily,
    userAgent: initialized.userAgent,
  })}`);
  console.log(JSON.stringify(fixture.response));
  console.log("codex spike: OK");
} catch (error) {
  console.error(`codex spike: ${error.message}`);
  if (stderr.trim()) console.error(stderr.trim());
  process.exitCode = 1;
} finally {
  server.kill();
}

async function readFixture(path) {
  const lines = (await readFile(path, "utf8")).trimEnd().split("\n");
  if (lines.length !== 2) throw new Error("fixture must contain exactly two JSON lines");

  let request;
  let response;
  try {
    request = JSON.parse(lines[0]);
    response = JSON.parse(lines[1]);
  } catch {
    throw new Error("fixture contains invalid JSON");
  }

  if (
    request.jsonrpc !== "2.0" ||
    request.id !== 7 ||
    request.method !== "item/commandExecution/requestApproval" ||
    request.params?.command !== "printf fixture" ||
    response.jsonrpc !== "2.0" ||
    response.id !== request.id ||
    response.result?.decision !== "accept"
  ) {
    throw new Error("fixture approval exchange is invalid");
  }

  return { request, response };
}

function initialize(server) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("initialize timed out")), 10_000);
    const lines = createInterface({ input: server.stdout });
    const fail = (error) => {
      clearTimeout(timeout);
      lines.close();
      reject(error);
    };

    server.once("error", fail);
    server.once("exit", (code) => fail(new Error(`app-server exited (${code ?? "signal"})`)));
    lines.on("line", (line) => {
      let message;
      try {
        message = JSON.parse(line);
      } catch {
        return;
      }
      if (message.id !== 1) return;
      clearTimeout(timeout);
      lines.close();
      if (message.error) reject(new Error(message.error.message ?? "initialize failed"));
      else resolve(message.result);
    });

    server.stdin.write(`${JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: {
        clientInfo: { name: "knobler-codex-agent-spike", version: "1.0.0" },
        experimentalApi: true,
      },
    })}\n`);
  });
}

function validateCapability(result) {
  if (
    typeof result?.platformOs !== "string" || !result.platformOs ||
    typeof result.platformFamily !== "string" || !result.platformFamily ||
    typeof result.userAgent !== "string" || !result.userAgent
  ) {
    throw new Error("initialize response is missing platform capability fields");
  }
}
