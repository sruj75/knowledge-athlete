import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { createServer, type Server, type Socket } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  OMI_CHAT_CONTRACT_VERSION,
  OMI_LONG_CONTROL_TOOL_TIMEOUT_MS,
  OMI_MANAGED_PROVIDER_SENTINEL,
  OMI_TOOL_TIMEOUT_MS,
  OMI_TOOLS,
  __callSwiftToolForTest,
  __connectOmiPipeForTest,
  __omiPendingCallsForTest,
  __registerOmiToolsForTest,
  __resetOmiPipeForTest,
  applyOmiProviderHeaders,
  createManagedProviderFetch,
  default as managedPiExtension,
  omiReasoningEffortFromRelayContext,
  omiRequestIdFromRelayContext,
  omiSessionIdFromRelayContext,
  omiToolResultContent,
  omiToolsForExecutionRole,
} from "./index.ts";
import { agentControlCapabilityManifest } from "../agent/src/runtime/control-tool-manifest.ts";
import {
  buildToolAvailabilitySnapshot,
  toolNamesForAdapter,
  toolsForAdapter,
} from "../agent/src/runtime/omi-tool-manifest.ts";
import { convertMessages } from "@earendil-works/pi-ai/api/google-shared";

test("managed provider headers retain correlation and the bounded reasoning contract", () => {
  assert.equal(omiRequestIdFromRelayContext('{"requestId":"req_01AB-cd"}'), "req_01AB-cd");
  assert.equal(omiRequestIdFromRelayContext('{"requestId":"has space"}'), undefined);
  assert.equal(omiRequestIdFromRelayContext(JSON.stringify({ requestId: "x".repeat(129) })), undefined);
  assert.equal(omiSessionIdFromRelayContext('{"sessionId":"session_01AB-cd"}'), "session_01AB-cd");
  assert.equal(omiSessionIdFromRelayContext('{"sessionId":"has space"}'), undefined);
  assert.equal(omiSessionIdFromRelayContext(JSON.stringify({ sessionId: "x".repeat(129) })), undefined);
  assert.equal(omiReasoningEffortFromRelayContext('{"reasoningEffort":"adaptive"}'), "adaptive");
  assert.equal(omiReasoningEffortFromRelayContext('{"reasoningEffort":"fast"}'), "fast");
  assert.equal(omiReasoningEffortFromRelayContext('{"reasoningEffort":"max"}'), undefined);

  const headers: Record<string, string> = {
    Authorization: `Bearer ${OMI_MANAGED_PROVIDER_SENTINEL}`,
    "X-Goog-Api-Key": "must-not-leave-desktop",
  };
  applyOmiProviderHeaders(
    headers,
    JSON.stringify({ requestId: "req_1", sessionId: "session_1", reasoningEffort: "adaptive" }),
    "firebase-token",
  );
  assert.deepEqual(headers, {
    "Authorization": "Bearer firebase-token",
    "x-intentive-chat-contract-version": OMI_CHAT_CONTRACT_VERSION,
    "x-intentive-request-id": "req_1",
    "x-intentive-session-id": "session_1",
    "x-intentive-reasoning-effort": "adaptive",
  });
});

test("final managed dispatch removes the Google adapter key without touching Firebase auth", async () => {
  let dispatched: Request | undefined;
  const fetchBoundary = createManagedProviderFetch(
    async (input, init) => {
      dispatched = input instanceof Request ? input : new Request(input, init);
      return new Response(null, { status: 204 });
    },
    new Set(["https://managed.example/v2"]),
  );
  const request = new Request(
    "https://managed.example/v2/models/gemini-3.7-flash:streamGenerateContent?alt=sse",
    {
      method: "POST",
      headers: {
        authorization: "Bearer firebase-token",
        "x-goog-api-key": OMI_MANAGED_PROVIDER_SENTINEL,
      },
      body: "{}",
    },
  );

  await fetchBoundary(request);

  assert.equal(dispatched?.headers.get("authorization"), "Bearer firebase-token");
  assert.equal(dispatched?.headers.get("x-goog-api-key"), null);
});

test("the bundled Gemini adapter replays exact thought signatures and merges parallel tool results", () => {
  const signature = "ZXhhY3QtdGhvdWdodC1zaWduYXR1cmU=";
  const model = {
    id: "gemini-3.7-flash",
    provider: "intentive",
    api: "google-generative-ai",
    input: ["text", "image"],
  } as never;
  const contents = convertMessages(model, {
    systemPrompt: "",
    tools: [],
    messages: [
      { role: "user", content: "Use both tools", timestamp: 1 },
      {
        role: "assistant",
        provider: "intentive",
        model: "gemini-3.7-flash",
        api: "google-generative-ai",
        timestamp: 2,
        stopReason: "toolUse",
        usage: { input: 1, output: 1, cacheRead: 0, cacheWrite: 0, totalTokens: 2, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
        content: [
          { type: "toolCall", id: "call-one", name: "first_tool", arguments: {}, thoughtSignature: signature },
          { type: "toolCall", id: "call-two", name: "second_tool", arguments: {} },
        ],
      },
      { role: "toolResult", toolCallId: "call-one", toolName: "first_tool", content: [{ type: "text", text: "one" }], isError: false, timestamp: 3 },
      { role: "toolResult", toolCallId: "call-two", toolName: "second_tool", content: [{ type: "text", text: "two" }], isError: false, timestamp: 4 },
    ],
  } as never);

  assert.equal(contents[1]?.parts?.[0]?.thoughtSignature, signature);
  assert.deepEqual(contents[2], {
    role: "user",
    parts: [
      { functionResponse: { name: "first_tool", response: { output: "one" } } },
      { functionResponse: { name: "second_tool", response: { output: "two" } } },
    ],
  });
});

test("the extension registers only the native managed Gemini provider", () => {
  const providers: Array<{ name: string; config: Record<string, unknown> }> = [];
  const handlers: string[] = [];
  const priorBase = process.env.OMI_API_BASE_URL;
  process.env.OMI_API_BASE_URL = "https://managed.example/v2";
  try {
    managedPiExtension({
      registerProvider(name: string, config: Record<string, unknown>) {
        providers.push({ name, config });
      },
      on(name: string) {
        handlers.push(name);
      },
    } as never);
  } finally {
    if (priorBase === undefined) delete process.env.OMI_API_BASE_URL;
    else process.env.OMI_API_BASE_URL = priorBase;
  }

  assert.equal(providers.length, 1);
  assert.equal(providers[0]?.name, "intentive");
  assert.deepEqual(
    (providers[0]?.config.models as Array<Record<string, unknown>>).map((model) => model.id),
    ["gemini-3.7-flash"],
  );
  assert.equal(providers[0]?.config.api, "google-generative-ai");
  assert.equal(providers[0]?.config.apiKey, OMI_MANAGED_PROVIDER_SENTINEL);
  assert.equal(providers[0]?.config.authHeader, true);
  assert.deepEqual((providers[0]?.config.models as Array<Record<string, unknown>>)[0]?.thinkingLevelMap, {
    off: null,
    minimal: null,
    low: "low",
    medium: "medium",
    high: "high",
  });
  assert.deepEqual(handlers, ["before_provider_headers"]);
});

test("managed provider registration ignores inherited legacy customer keys", () => {
  const providers = ["OPENAI", "ANTHROPIC", "GEMINI", "DEEPGRAM"];
  const saved = new Map(providers.map((name) => [`OMI_BYOK_${name}`, process.env[`OMI_BYOK_${name}`]]));
  for (const name of providers) process.env[`OMI_BYOK_${name}`] = `legacy-${name.toLowerCase()}`;
  const priorBase = process.env.OMI_API_BASE_URL;
  const priorKey = process.env.OMI_API_KEY;
  process.env.OMI_API_BASE_URL = "https://managed.example/v2";
  process.env.OMI_API_KEY = "managed-registration-token";

  let registration: Record<string, unknown> | undefined;
  try {
    managedPiExtension({
      registerProvider(name: string, config: Record<string, unknown>) {
        assert.equal(name, "intentive");
        registration = config;
      },
      on() {},
    } as never);
  } finally {
    for (const [name, value] of saved) {
      if (value === undefined) delete process.env[name];
      else process.env[name] = value;
    }
    if (priorBase === undefined) delete process.env.OMI_API_BASE_URL;
    else process.env.OMI_API_BASE_URL = priorBase;
    if (priorKey === undefined) delete process.env.OMI_API_KEY;
    else process.env.OMI_API_KEY = priorKey;
  }

  assert.equal(registration?.baseUrl, "https://managed.example/v2");
  assert.equal(registration?.apiKey, OMI_MANAGED_PROVIDER_SENTINEL);
  assert.notEqual(registration?.apiKey, "managed-registration-token");
  assert.equal(registration?.api, "google-generative-ai");
  assert.equal(registration?.headers, undefined);
});

test("the Pi tool projection exactly matches the owned typed-tool manifest", () => {
  assert.deepEqual(OMI_TOOLS.map((tool) => tool.name), toolNamesForAdapter("pi-mono", { executionRole: "coordinator" }));
  assert.deepEqual(
    omiToolsForExecutionRole("leaf").map((tool) => tool.name),
    toolNamesForAdapter("pi-mono", { executionRole: "leaf" }),
  );
  assert.equal(new Set(OMI_TOOLS.map((tool) => tool.name)).size, OMI_TOOLS.length);
  assert.ok(!OMI_TOOLS.some((tool) => ["bash", "read", "write", "edit", "load_skill", "search_skills"].includes(tool.name)));

  const canonical = toolsForAdapter("pi-mono", { executionRole: "coordinator" });
  for (const [index, tool] of OMI_TOOLS.entries()) {
    assert.equal(tool.label, canonical[index]?.label);
    assert.equal(tool.description, canonical[index]?.description);
    assert.equal(tool.parameters.additionalProperties, false);
    assert.equal(typeof tool.execute, "function");
  }
});

test("capture_screen returns only scoped Swift-issued image paths as Pi image content", async () => {
  const root = await mkdtemp(join(tmpdir(), "omi-pi-capture-"));
  try {
    const full = join(root, "full.png");
    const tile = join(root, "tile.jpg");
    await writeFile(full, Buffer.from("full-image"));
    await writeFile(tile, Buffer.from("tile-image"));
    const result = `${full}\n\nDetail tiles:\n- top-left: ${tile}`;

    assert.deepEqual(await omiToolResultContent("capture_screen", result), [
      { type: "text", text: result },
      { type: "image", data: Buffer.from("full-image").toString("base64"), mimeType: "image/png" },
      { type: "image", data: Buffer.from("tile-image").toString("base64"), mimeType: "image/jpeg" },
    ]);
    assert.deepEqual(await omiToolResultContent("get_memories", full), [{ type: "text", text: full }]);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("agent control tools retain their canonical schemas and long timeout", () => {
  for (const manifestTool of agentControlCapabilityManifest) {
    const tool = OMI_TOOLS.find((candidate) => candidate.name === manifestTool.name);
    if (!tool) continue;
    assert.equal(
      (tool as unknown as { __omiTimeoutMsForTest: number }).__omiTimeoutMsForTest,
      manifestTool.timeoutClass === "long" ? OMI_LONG_CONTROL_TOOL_TIMEOUT_MS : OMI_TOOL_TIMEOUT_MS,
    );
    const schema = tool.parameters as unknown as { required?: string[]; properties: Record<string, unknown> };
    assert.deepEqual(schema.required ?? [], manifestTool.required ?? []);
    assert.deepEqual(Object.keys(schema.properties), Object.keys(manifestTool.properties));
  }
  assert.equal(OMI_TOOL_TIMEOUT_MS, 30_000);
  assert.equal(OMI_LONG_CONTROL_TOOL_TIMEOUT_MS, 10 * 60_000);
});

test("tool registration writes the canonical availability snapshot", async () => {
  const temp = await mkdtemp(join(tmpdir(), "omi-pi-extension-snapshot-"));
  const socketPath = join(temp, "bridge.sock");
  const snapshotPath = join(temp, "snapshot.json");
  const server = createServer();
  await listen(server, socketPath);
  const originalPipe = process.env.OMI_BRIDGE_PIPE;
  const originalSnapshot = process.env.OMI_TOOL_AVAILABILITY_SNAPSHOT_PATH;
  process.env.OMI_BRIDGE_PIPE = socketPath;
  process.env.OMI_TOOL_AVAILABILITY_SNAPSHOT_PATH = snapshotPath;
  const registered: string[] = [];
  try {
    await __registerOmiToolsForTest({ registerTool(tool: { name: string }) { registered.push(tool.name); } } as never);
    assert.deepEqual(registered, OMI_TOOLS.map((tool) => tool.name));
    assert.deepEqual(
      JSON.parse(await readFile(snapshotPath, "utf8")),
      buildToolAvailabilitySnapshot("pi-mono", { executionRole: "coordinator" }),
    );
  } finally {
    __resetOmiPipeForTest();
    restoreEnv("OMI_BRIDGE_PIPE", originalPipe);
    restoreEnv("OMI_TOOL_AVAILABILITY_SNAPSHOT_PATH", originalSnapshot);
    await close(server);
    await rm(temp, { recursive: true, force: true });
  }
});

test("tool relay requires a live private socket and a kernel-issued capability", async () => {
  __resetOmiPipeForTest();
  assert.equal(await __callSwiftToolForTest("execute_sql", { query: "select 1" }), "Error: not connected to Intentive bridge");

  const temp = await mkdtemp(join(tmpdir(), "omi-pi-extension-relay-"));
  const socketPath = join(temp, "bridge.sock");
  const contextPath = join(temp, "context.json");
  const server = createServer();
  let peer: Socket | undefined;
  let received = "";
  server.on("connection", (socket) => {
    peer = socket;
    socket.on("data", (data) => {
      received += data.toString();
      const newline = received.indexOf("\n");
      if (newline < 0) return;
      const request = JSON.parse(received.slice(0, newline)) as Record<string, unknown>;
      socket.write(`${JSON.stringify({ type: "tool_result", callId: request.callId, result: "ok" })}\n`);
    });
  });
  await listen(server, socketPath);
  const originalContext = process.env.OMI_CONTEXT_FILE;
  process.env.OMI_CONTEXT_FILE = contextPath;
  try {
    await __connectOmiPipeForTest(socketPath);
    await writeFile(contextPath, "{}", "utf8");
    assert.equal(await __callSwiftToolForTest("execute_sql", { query: "select 1" }), "Error: missing active Intentive run capability for tool relay");

    await writeFile(contextPath, JSON.stringify({ capabilityRef: "cap-issued", requestId: "forged" }), "utf8");
    assert.equal(await __callSwiftToolForTest("execute_sql", { query: "select 1" }), "ok");
    const request = JSON.parse(received.trim()) as Record<string, unknown>;
    assert.equal(request.capabilityRef, "cap-issued");
    assert.equal(request.protocolVersion, 2);
    assert.equal(request.name, "execute_sql");
    assert.ok(!("requestId" in request));
  } finally {
    peer?.destroy();
    __resetOmiPipeForTest();
    restoreEnv("OMI_CONTEXT_FILE", originalContext);
    await close(server);
    await rm(temp, { recursive: true, force: true });
  }
});

test("an aborted tool relay is settled and removed", async () => {
  const temp = await mkdtemp(join(tmpdir(), "omi-pi-extension-abort-"));
  const socketPath = join(temp, "bridge.sock");
  const contextPath = join(temp, "context.json");
  const server = createServer();
  server.on("connection", (socket) => socket.on("data", () => undefined));
  await listen(server, socketPath);
  const originalContext = process.env.OMI_CONTEXT_FILE;
  process.env.OMI_CONTEXT_FILE = contextPath;
  await writeFile(contextPath, JSON.stringify({ capabilityRef: "cap-issued" }), "utf8");
  try {
    await __connectOmiPipeForTest(socketPath);
    const controller = new AbortController();
    const pending = __callSwiftToolForTest("execute_sql", { query: "select 1" }, controller.signal);
    controller.abort();
    assert.equal(await pending, "Error: tool call aborted");
    assert.equal(__omiPendingCallsForTest.size, 0);
  } finally {
    __resetOmiPipeForTest();
    restoreEnv("OMI_CONTEXT_FILE", originalContext);
    await close(server);
    await rm(temp, { recursive: true, force: true });
  }
});

function listen(server: Server, path: string): Promise<void> {
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(path, () => {
      server.off("error", reject);
      resolve();
    });
  });
}

function close(server: Server): Promise<void> {
  return new Promise((resolve) => server.close(() => resolve()));
}

function restoreEnv(name: string, value: string | undefined): void {
  if (value === undefined) delete process.env[name];
  else process.env[name] = value;
}
