import { describe, expect, it } from "vitest";
import {
  executionRoleAllowsTool,
  providerBoundaryForAdapter,
  resolveAdapterWithinBoundary,
} from "../src/runtime/execution-policy.js";

describe("agent execution policy", () => {
  it("derives the declared production credential boundary", () => {
    expect(providerBoundaryForAdapter("pi-mono")).toBe("managed_cloud");
  });

  it("keeps behavioral fakes inside their exact test-only boundary", () => {
    expect(resolveAdapterWithinBoundary({
      providerBoundary: "local_user:fake",
      defaultAdapterId: "fake",
      requestedAdapterId: "fake",
    })).toBe("fake");
    expect(() => resolveAdapterWithinBoundary({
      providerBoundary: "local_user:fake",
      defaultAdapterId: "fake",
      requestedAdapterId: "other-fake",
    })).toThrow("outside the owning execution boundary");
  });

  it("pins managed execution to Pi and fails closed for every override", () => {
    expect(resolveAdapterWithinBoundary({
      providerBoundary: "managed_cloud",
      defaultAdapterId: "pi-mono",
    })).toBe("pi-mono");
    for (const adapterId of ["acp", "hermes", "openclaw", "unknown-adapter"]) {
      expect(() => resolveAdapterWithinBoundary({
        providerBoundary: "managed_cloud",
        defaultAdapterId: "pi-mono",
        requestedAdapterId: adapterId,
      })).toThrow();
    }
  });

  it("denies every leaf-restricted control tool for leaf roles", () => {
    for (const toolName of [
      "send_agent_message",
      "spawn_background_agent",
      "spawn_agent",
      "run_agent_and_wait",
    ]) {
      expect(executionRoleAllowsTool("leaf", toolName)).toBe(false);
      expect(executionRoleAllowsTool("coordinator", toolName)).toBe(true);
    }
  });
});
