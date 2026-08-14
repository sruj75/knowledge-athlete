import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { describe, expect, it, vi } from "vitest";

import { adapterCapabilitiesFor, isProductionAdapterId, type AdapterAttemptContext, type RuntimeAdapter } from "../src/adapters/interface.js";
import { PiMonoAdapter, PiMonoRuntimeAdapter } from "../src/adapters/pi-mono.js";
import { validateRuntimeContractFixture } from "../src/runtime/contract-schema.js";
import type { AgentRuntimeKernel } from "../src/runtime/kernel.js";
import { finalizeRelayToolResult, MAX_RELAY_TOOL_RESULT_BYTES } from "../src/runtime/relay-tool-result.js";
import { assertToolResultEnvelope } from "../src/runtime/tool-result-envelope.js";

const contractDirectory = join(process.cwd(), "contracts", "v1");
const contract = JSON.parse(readFileSync(join(contractDirectory, "agent-runtime-contract.fixture.json"), "utf8"));
const schema = JSON.parse(readFileSync(join(contractDirectory, "agent-runtime-contract.schema.json"), "utf8"));

type ConformanceScenario = {
  name: "lifecycle_failure" | "oversized_tool_result";
  runState: "failed";
  attemptState: "failed";
  turnState: "failed";
  failureCode: string;
  consumesToolInvocation: true;
  expectsTruncatedToolEnvelope: true;
};

type AdapterContract = {
  adapterId: string;
  surface: "desktop_chat" | "realtime_voice";
  transport: "node_runtime" | "swift_realtime";
  expectsToolEnvelope: true;
  scenarios: ConformanceScenario[];
};

function attemptContext(adapterId: string, binding: Awaited<ReturnType<RuntimeAdapter["openBinding"]>>): AdapterAttemptContext {
  return {
    sessionId: "ses-conformance",
    ownerId: "owner-conformance",
    requestId: "request-conformance",
    clientId: "client-conformance",
    runId: "run-conformance",
    attemptId: "attempt-conformance",
    binding,
    prompt: [{ type: "text", text: "conformance" }],
    mode: "ask",
    tools: [],
    metadata: { adapterId },
  };
}

async function executeNodeAdapterBoundary(adapterId: string, failExecution: boolean): Promise<void> {
  expect(adapterId).toBe("pi-mono");
  const harness = new PiMonoAdapter({ authToken: "fixture-token" });
  vi.spyOn(harness, "start").mockResolvedValue();
  vi.spyOn(harness, "stop").mockResolvedValue();
  vi.spyOn(harness, "createSession").mockResolvedValue("pi-conformance-native");
  vi.spyOn(harness, "sendPrompt").mockImplementation(async () => {
    if (failExecution) throw new Error("deterministic conformance failure");
    return { text: "conformance", sessionId: "pi-conformance-native", inputTokens: 1, outputTokens: 1 };
  });
  const adapter: RuntimeAdapter = new PiMonoRuntimeAdapter(harness);

  await adapter.start();
  const binding = await adapter.openBinding({
    sessionId: "ses-conformance",
    cwd: "/tmp",
    model: "fixture-model",
  });
  const execution = adapter.executeAttempt(attemptContext(adapterId, binding), () => {}, new AbortController().signal);
  if (failExecution) {
    await expect(execution).rejects.toThrow("deterministic conformance failure");
  } else {
    await expect(execution).resolves.toMatchObject({ terminalStatus: "succeeded" });
  }
  await adapter.stop();
}

/** A deterministic in-memory sink substitutes for the model-facing relay. */
function deliverOversizedFixture(adapterId: string): void {
  const frames: string[] = [];
  const transport = { sendToolResult: (frame: string) => frames.push(frame) };
  const artifactRoot = mkdtempSync(join(tmpdir(), "omi-contract-relay-"));
  const identity = {
    invocationId: `invocation-${adapterId}-oversized`,
    ownerId: "owner-conformance",
    sessionId: "ses-conformance",
    runId: "run-conformance",
    attemptId: "attempt-conformance",
    toolName: contract.toolInvocation.toolName,
  };
  const source = JSON.stringify({
    ok: true,
    adapterId,
    // Exercise the actual 620 KiB session-listing regression size, rather
    // than a fixture-only envelope assertion or a raw local-array delivery.
    sessions: "x".repeat(contract.toolResultEnvelope.originalBytes),
  });
  let persistedContents = "";
  const persistArtifact = vi.fn((input: { uri: string; sizeBytes: number }) => {
    persistedContents = readFileSync(fileURLToPath(input.uri), "utf8");
    expect(input.sizeBytes).toBe(Buffer.byteLength(source, "utf8"));
    return { artifactId: `artifact-${adapterId}-oversized` };
  });
  try {
    const frame = finalizeRelayToolResult({
      identity,
      result: source,
      outcome: "succeeded",
      kernel: { persistArtifact } as unknown as AgentRuntimeKernel,
      artifactRoot,
    });
    transport.sendToolResult(frame);

    expect(Buffer.byteLength(source, "utf8")).toBeGreaterThan(contract.toolResultEnvelope.originalBytes);
    expect(persistArtifact).toHaveBeenCalledTimes(1);
    expect(persistedContents).toBe(`${source}\n`);
    expect(Buffer.byteLength(frames[0]!, "utf8")).toBeLessThanOrEqual(MAX_RELAY_TOOL_RESULT_BYTES);
    const delivered = JSON.parse(frames[0]!);
    assertToolResultEnvelope(delivered.toolResultEnvelope);
    expect(delivered.toolResultEnvelope).toMatchObject({
      status: "failed",
      truncated: true,
      fullOutputRef: `artifact:artifact-${adapterId}-oversized`,
      provenance: {
        invocationId: identity.invocationId,
        runId: identity.runId,
        attemptId: identity.attemptId,
        toolName: identity.toolName,
      },
    });
  } finally {
    rmSync(artifactRoot, { recursive: true, force: true });
  }
}

/** The shared fixture is executed once per adapter, not merely enumerated. */
async function executeSharedScenario(adapter: AdapterContract, scenario: ConformanceScenario): Promise<void> {
  expect(contract.lifecycle.run).toContain(scenario.runState);
  expect(contract.lifecycle.attempt).toContain(scenario.attemptState);
  expect(contract.lifecycle.turn).toContain(scenario.turnState);
  expect(contract.failureTaxonomy).toContain(scenario.failureCode);
  expect(scenario.consumesToolInvocation).toBe(true);
  expect(contract.permissionDecision.invocationId).toBe(contract.toolInvocation.invocationId);
  expect(contract.toolInvocation).toMatchObject(contract.toolResultEnvelope.provenance);
  if (scenario.expectsTruncatedToolEnvelope) {
    assertToolResultEnvelope(contract.toolResultEnvelope);
    expect(contract.toolResultEnvelope.truncated).toBe(true);
    expect(contract.toolResultEnvelope.fullOutputRef).toMatch(/^artifact:/);
  }
  expect(adapter.expectsToolEnvelope).toBe(true);
  if (adapter.transport === "node_runtime") {
    // A fake test adapter/Pi transport executes the actual binding and attempt methods;
    // it deterministically turns the lifecycle-failure fixture into a real
    // adapter rejection instead of just comparing fixture strings.
    await executeNodeAdapterBoundary(adapter.adapterId, scenario.name === "lifecycle_failure");
    if (scenario.name === "oversized_tool_result") {
      deliverOversizedFixture(adapter.adapterId);
    }
  } else {
    // The paired XCTest executes Gemini and OpenAI through the exact provider
    // result policy that sendToolResultIfCurrent invokes in production.
    expect(adapter.surface).toBe("realtime_voice");
  }
}

describe("runtime adapter contract conformance", () => {
  it("validates the full shared fixture and every identity relationship", () => {
    expect(validateRuntimeContractFixture(contract, schema)).toEqual([]);
  });

  it.each(contract.adapterConformance as AdapterContract[])(
    "$adapterId executes the lifecycle-failure and oversized-tool-result contract",
    async (adapter) => {
      if (adapter.transport === "node_runtime") {
        expect(isProductionAdapterId(adapter.adapterId)).toBe(true);
        expect(adapterCapabilitiesFor(adapter.adapterId)).toBeDefined();
      }
      for (const scenario of adapter.scenarios) await executeSharedScenario(adapter, scenario);
    },
  );
});
