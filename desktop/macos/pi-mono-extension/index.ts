// Managed Pi provider and the private typed-tool relay owned by the desktop app.

import { defineTool, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "@earendil-works/pi-ai";
import { readFile, writeFile } from "node:fs/promises";
import { createConnection, type Socket } from "node:net";
import {
  buildToolAvailabilitySnapshot,
  toolsForAdapter,
  type OmiToolInputSchema,
  type OmiToolManifestEntry,
} from "../agent/src/runtime/omi-tool-manifest.ts";

const OMI_REQUEST_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/;

function omiBoundedIdFromRelayContext(raw: string, key: "requestId" | "sessionId"): string | undefined {
  try {
    const parsed = JSON.parse(raw) as Record<string, unknown>;
    const value = parsed[key];
    return typeof value === "string" && OMI_REQUEST_ID_PATTERN.test(value) ? value : undefined;
  } catch {
    return undefined;
  }
}

export function omiRequestIdFromRelayContext(raw: string): string | undefined {
  return omiBoundedIdFromRelayContext(raw, "requestId");
}

export function omiSessionIdFromRelayContext(raw: string): string | undefined {
  return omiBoundedIdFromRelayContext(raw, "sessionId");
}

export function omiReasoningEffortFromRelayContext(raw: string): string | undefined {
  try {
    const parsed = JSON.parse(raw) as { reasoningEffort?: unknown };
    return parsed.reasoningEffort === "adaptive" || parsed.reasoningEffort === "fast"
      ? parsed.reasoningEffort
      : undefined;
  } catch {
    return undefined;
  }
}

async function omiRelayContextRaw(): Promise<string | undefined> {
  const contextFile = process.env.OMI_CONTEXT_FILE;
  if (!contextFile) return undefined;
  try {
    return await readFile(contextFile, "utf8");
  } catch {
    return undefined;
  }
}

let omiPipeConnection: Socket | null = null;
let omiPipeBuffer = "";
let omiCallIdCounter = 0;
const omiPendingCalls = new Map<string, { connection: Socket; resolve: (result: string) => void }>();

function connectOmiPipe(pipePath: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const connection = createConnection(pipePath, () => {
      process.stderr.write("[intentive-tools] Connected to bridge pipe\n");
      resolve();
    });
    omiPipeConnection = connection;
    connection.on("data", (data: Buffer) => {
      omiPipeBuffer += data.toString();
      let newlineIndex;
      while ((newlineIndex = omiPipeBuffer.indexOf("\n")) >= 0) {
        const line = omiPipeBuffer.slice(0, newlineIndex);
        omiPipeBuffer = omiPipeBuffer.slice(newlineIndex + 1);
        if (!line.trim()) continue;
        try {
          const message = JSON.parse(line) as { type?: unknown; callId?: unknown; result?: unknown };
          if (message.type !== "tool_result" || typeof message.callId !== "string") continue;
          const pending = omiPendingCalls.get(message.callId);
          if (!pending) continue;
          pending.resolve(String(message.result ?? ""));
          omiPendingCalls.delete(message.callId);
        } catch {
          // The bridge owns validation; malformed responses cannot settle a call.
        }
      }
    });
    connection.on("error", (error) => {
      process.stderr.write(`[intentive-tools] Pipe error: ${error.message}\n`);
      reject(error);
    });
    connection.on("close", () => {
      process.stderr.write("[intentive-tools] Pipe disconnected\n");
      if (omiPipeConnection !== connection) return;
      omiPipeConnection = null;
      for (const [callId, pending] of omiPendingCalls) {
        if (pending.connection !== connection) continue;
        pending.resolve("Error: Intentive bridge disconnected");
        omiPendingCalls.delete(callId);
      }
    });
  });
}

export const OMI_TOOL_TIMEOUT_MS = 30_000;
export const OMI_LONG_CONTROL_TOOL_TIMEOUT_MS = 10 * 60_000;
export const OMI_CHAT_CONTRACT_VERSION = "2";
export const OMI_MANAGED_PROVIDER_SENTINEL = "intentive-managed-proxy";

const omiManagedProviderBaseUrls = new Set<string>();
let omiManagedProviderFetchInstalled = false;

function normalizedManagedProviderBaseUrl(value: string): string {
  const url = new URL(value);
  return `${url.origin}${url.pathname.replace(/\/+$/, "")}`;
}

function requestTargetsManagedProvider(input: RequestInfo | URL, managedBaseUrls: ReadonlySet<string>): boolean {
  const rawUrl = input instanceof Request ? input.url : String(input);
  const url = new URL(rawUrl);
  const target = `${url.origin}${url.pathname}`;
  return [...managedBaseUrls].some((baseUrl) => target === baseUrl || target.startsWith(`${baseUrl}/`));
}

/**
 * Removes the Google adapter's placeholder key at the final fetch boundary.
 * The provider hook runs before @google/genai's NodeAuth layer, which appends
 * x-goog-api-key afterwards; this wrapper is therefore the last credential
 * boundary before the request leaves the desktop process.
 */
export function createManagedProviderFetch(
  fetchImpl: typeof globalThis.fetch,
  managedBaseUrls: ReadonlySet<string>,
): typeof globalThis.fetch {
  return (async (input: RequestInfo | URL, init?: RequestInit) => {
    if (!requestTargetsManagedProvider(input, managedBaseUrls)) return fetchImpl(input, init);
    const inputHeaders = input instanceof Request ? input.headers : undefined;
    const headers = new Headers(init?.headers ?? inputHeaders);
    headers.delete("x-goog-api-key");
    if (input instanceof Request) {
      return fetchImpl(new Request(input, { ...init, headers }));
    }
    return fetchImpl(input, { ...init, headers });
  }) as typeof globalThis.fetch;
}

function installManagedProviderFetchBoundary(baseUrl: string): void {
  omiManagedProviderBaseUrls.add(normalizedManagedProviderBaseUrl(baseUrl));
  if (omiManagedProviderFetchInstalled) return;
  const originalFetch = globalThis.fetch.bind(globalThis);
  globalThis.fetch = createManagedProviderFetch(originalFetch, omiManagedProviderBaseUrls);
  omiManagedProviderFetchInstalled = true;
}

async function omiRelayCapabilityRef(): Promise<string | undefined> {
  const contextFile = process.env.OMI_CONTEXT_FILE;
  if (!contextFile) return undefined;
  try {
    const parsed = JSON.parse(await readFile(contextFile, "utf8")) as Record<string, unknown>;
    return typeof parsed.capabilityRef === "string" && parsed.capabilityRef.length > 0
      ? parsed.capabilityRef
      : undefined;
  } catch {
    return undefined;
  }
}

async function callSwiftTool(
  name: string,
  input: Record<string, unknown>,
  signal?: AbortSignal,
  timeoutMs = OMI_TOOL_TIMEOUT_MS,
): Promise<string> {
  const connection = omiPipeConnection;
  if (!connection) return "Error: not connected to Intentive bridge";
  if (signal?.aborted) return "Error: tool call aborted";
  const capabilityRef = await omiRelayCapabilityRef();
  if (!capabilityRef) return "Error: missing active Intentive run capability for tool relay";
  if (signal?.aborted) return "Error: tool call aborted";
  if (omiPipeConnection !== connection) return "Error: Intentive bridge disconnected";

  const callId = `intentive-ext-${++omiCallIdCounter}-${Date.now()}`;
  return new Promise<string>((resolve) => {
    const timer = setTimeout(() => {
      omiPendingCalls.delete(callId);
      resolve(`Error: tool '${name}' timed out after ${timeoutMs / 1000}s`);
    }, timeoutMs);
    const abort = () => {
      clearTimeout(timer);
      omiPendingCalls.delete(callId);
      resolve("Error: tool call aborted");
    };
    signal?.addEventListener("abort", abort, { once: true });
    omiPendingCalls.set(callId, {
      connection,
      resolve: (result) => {
        clearTimeout(timer);
        signal?.removeEventListener("abort", abort);
        resolve(result);
      },
    });
    connection.write(`${JSON.stringify({
      type: "tool_use",
      callId,
      invocationId: callId,
      name,
      input,
      protocolVersion: 2,
      capabilityRef,
    })}\n`);
  });
}

export function applyOmiProviderHeaders(
  headers: Record<string, string>,
  relayContextRaw: string | undefined,
  firebaseToken = process.env.OMI_API_KEY,
): void {
  // The bundled Google adapter requires an auth value while assembling its
  // request and adds it as x-goog-api-key. Intentive authenticates the desktop
  // with Firebase instead, so remove that SDK header before any bytes leave the
  // process; the backend owns the real Gemini key.
  for (const name of Object.keys(headers)) {
    const lowerName = name.toLowerCase();
    if (lowerName === "authorization" || lowerName === "x-goog-api-key") delete headers[name];
  }
  if (firebaseToken) headers.Authorization = `Bearer ${firebaseToken}`;
  headers["x-intentive-chat-contract-version"] = OMI_CHAT_CONTRACT_VERSION;
  if (relayContextRaw === undefined) return;
  const requestId = omiRequestIdFromRelayContext(relayContextRaw);
  if (requestId) headers["x-intentive-request-id"] = requestId;
  const sessionId = omiSessionIdFromRelayContext(relayContextRaw);
  if (sessionId) headers["x-intentive-session-id"] = sessionId;
  const reasoningEffort = omiReasoningEffortFromRelayContext(relayContextRaw);
  if (reasoningEffort) headers["x-intentive-reasoning-effort"] = reasoningEffort;
}

function typeBoxSchemaForJsonSchema(schema: Record<string, unknown>): unknown {
  const options: Record<string, unknown> = {};
  if (typeof schema.description === "string") options.description = schema.description;
  if (Array.isArray(schema.enum)) options.enum = schema.enum;
  switch (schema.type) {
    case "string":
      return Type.String(options);
    case "number":
    case "integer":
      return Type.Number(options);
    case "boolean":
      return Type.Boolean(options);
    case "array": {
      const itemSchema = schema.items && typeof schema.items === "object"
        ? typeBoxSchemaForJsonSchema(schema.items as Record<string, unknown>)
        : Type.Unknown();
      return Type.Array(itemSchema as never, options);
    }
    case "object": {
      const properties = typeof schema.properties === "object" && schema.properties
        ? typeBoxPropertiesForInputSchema({
            type: "object",
            properties: schema.properties as Record<string, unknown>,
            required: Array.isArray(schema.required) ? schema.required as string[] : [],
            additionalProperties: schema.additionalProperties === true,
          })
        : {};
      return Type.Object(properties, { ...options, additionalProperties: schema.additionalProperties === true });
    }
    default:
      return Type.Unknown(options);
  }
}

function typeBoxPropertiesForInputSchema(tool: OmiToolInputSchema): Parameters<typeof Type.Object>[0] {
  const required = new Set(tool.required ?? []);
  return Object.fromEntries(
    Object.entries(tool.properties).map(([name, property]) => {
      const schema = typeBoxSchemaForJsonSchema(property as Record<string, unknown>);
      return [name, required.has(name) ? schema : Type.Optional(schema as never)];
    }),
  ) as Parameters<typeof Type.Object>[0];
}

type OmiToolResultContent =
  | { type: "text"; text: string }
  | { type: "image"; data: string; mimeType: string };

function screenshotPaths(result: string): string[] {
  const paths: string[] = [];
  for (const line of result.split("\n")) {
    const trimmed = line.trim();
    const match = trimmed.match(/(?:^|: )(\/[^\n]+\.(?:png|jpe?g))$/i);
    if (match?.[1] && !paths.includes(match[1])) paths.push(match[1]);
    if (paths.length === 5) break;
  }
  return paths;
}

/** Attach only the image paths issued by the scoped Swift capture tool. */
export async function omiToolResultContent(name: string, result: string): Promise<OmiToolResultContent[]> {
  const content: OmiToolResultContent[] = [{ type: "text", text: result }];
  if (name !== "capture_screen") return content;
  for (const path of screenshotPaths(result)) {
    try {
      const data = await readFile(path);
      if (data.byteLength > 10 * 1024 * 1024) continue;
      content.push({
        type: "image",
        data: data.toString("base64"),
        mimeType: path.toLowerCase().endsWith(".png") ? "image/png" : "image/jpeg",
      });
    } catch {
      // Preserve the authoritative text result if an ephemeral capture vanished.
    }
  }
  return content;
}

function omiManifestTool(tool: OmiToolManifestEntry) {
  const timeoutMs = tool.timeoutClass === "long" ? OMI_LONG_CONTROL_TOOL_TIMEOUT_MS : OMI_TOOL_TIMEOUT_MS;
  const registered = defineTool({
    name: tool.name,
    label: tool.label,
    description: tool.description,
    promptSnippet: tool.promptSnippet,
    promptGuidelines: tool.promptGuidelines,
    parameters: Type.Object(typeBoxPropertiesForInputSchema(tool.inputSchema), { additionalProperties: false }),
    async execute(_toolCallId, params, signal) {
      const result = await callSwiftTool(tool.name, params as Record<string, unknown>, signal, timeoutMs);
      return { content: await omiToolResultContent(tool.name, result), details: undefined };
    },
  });
  Object.defineProperty(registered, "__omiTimeoutMsForTest", { value: timeoutMs, enumerable: false });
  return registered;
}

const executionRole = process.env.OMI_EXECUTION_ROLE === "leaf" ? "leaf" : "coordinator";
const projectionContext = { executionRole } as const;

export function omiToolsForExecutionRole(role: "coordinator" | "leaf") {
  return toolsForAdapter("pi-mono", { executionRole: role }).map(omiManifestTool);
}

export const OMI_TOOLS = omiToolsForExecutionRole(executionRole);

async function registerOmiTools(pi: ExtensionAPI): Promise<void> {
  const pipePath = process.env.OMI_BRIDGE_PIPE;
  if (!pipePath) {
    process.stderr.write("[intentive-tools] OMI_BRIDGE_PIPE not set - typed tools unavailable\n");
    return;
  }
  try {
    await connectOmiPipe(pipePath);
  } catch (error) {
    process.stderr.write(`[intentive-tools] Failed to connect: ${error instanceof Error ? error.message : error}\n`);
    return;
  }
  for (const tool of OMI_TOOLS) pi.registerTool(tool);
  const snapshot = buildToolAvailabilitySnapshot("pi-mono", projectionContext);
  if (process.env.OMI_TOOL_AVAILABILITY_SNAPSHOT_PATH) {
    try {
      await writeFile(
        process.env.OMI_TOOL_AVAILABILITY_SNAPSHOT_PATH,
        `${JSON.stringify(snapshot, null, 2)}\n`,
      );
    } catch (error) {
      process.stderr.write(`[intentive-tools] Failed to write tool snapshot: ${error instanceof Error ? error.message : error}\n`);
    }
  }
  process.stderr.write(
    `[intentive-tools] adapter=pi-mono advertisedToolCount=${snapshot.advertisedToolCount} advertisedTools=${snapshot.advertisedToolNames.join(",")}\n`,
  );
}

export default function managedPiExtension(pi: ExtensionAPI): void {
  const baseUrl = process.env.OMI_API_BASE_URL?.trim();
  if (!baseUrl) throw new Error("Intentive managed provider requires a configured backend URL");
  installManagedProviderFetchBoundary(baseUrl);
  pi.registerProvider("intentive", {
    api: "google-generative-ai",
    baseUrl,
    apiKey: OMI_MANAGED_PROVIDER_SENTINEL,
    authHeader: true,
    models: [{
      id: "gemini-3.7-flash",
      name: "Intentive Gemini Flash",
      reasoning: true,
      thinkingLevelMap: {
        off: null,
        minimal: null,
        low: "low",
        medium: "medium",
        high: "high",
      },
      input: ["text", "image"],
      contextWindow: 200_000,
      maxTokens: 16_384,
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
    }],
  });
  pi.on("before_provider_headers", async (event) => {
    applyOmiProviderHeaders(event.headers, await omiRelayContextRaw());
  });
  void registerOmiTools(pi);
}

export async function __registerOmiToolsForTest(pi: ExtensionAPI): Promise<void> {
  await registerOmiTools(pi);
}

export const __connectOmiPipeForTest = connectOmiPipe;
export const __callSwiftToolForTest = callSwiftTool;
export const __omiRelayCapabilityRefForTest = omiRelayCapabilityRef;
export const __omiPendingCallsForTest = omiPendingCalls;

export function __resetOmiPipeForTest(): void {
  if (omiPipeConnection) {
    omiPipeConnection.destroy();
    omiPipeConnection = null;
  }
  omiPipeBuffer = "";
  omiCallIdCounter = 0;
  omiPendingCalls.clear();
}
