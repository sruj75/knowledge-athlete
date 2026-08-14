import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  adapterIdForHarnessMode,
  managedPiActivationError,
  managedPiIsActivated,
  MANAGED_PI_AUTH_ENV,
} from "../src/runtime/adapter-selection.js";

describe("managed Pi selection and activation", () => {
  it("accepts only the managed Pi runtime", () => {
    expect(adapterIdForHarnessMode(undefined)).toBe("pi-mono");
    expect(adapterIdForHarnessMode("piMono")).toBe("pi-mono");
    expect(adapterIdForHarnessMode("pi-mono")).toBe("pi-mono");
    for (const retired of ["acp", "hermes", "openclaw", "openClaw"]) {
      expect(() => adapterIdForHarnessMode(retired)).toThrow(`Unknown harness mode: ${retired}`);
    }
    expect(() => adapterIdForHarnessMode("unknown")).toThrow("Unknown harness mode: unknown");
  });

  it("fails explicitly when managed authentication is missing", () => {
    expect(MANAGED_PI_AUTH_ENV).toBe("OMI_AUTH_TOKEN");
    expect(managedPiIsActivated("")).toBe(false);
    expect(managedPiIsActivated("  ")).toBe(false);
    expect(managedPiIsActivated("managed-token")).toBe(true);
    expect(managedPiActivationError()).toBe(
      "Managed Omi authentication is unavailable. Sign in and try again."
    );
  });

  it("source: daemon has no alternate adapter registration or fallback", () => {
    const indexSource = readFileSync(new URL("../src/index.ts", import.meta.url), "utf8");

    expect(indexSource).toContain("adapterIdForHarnessMode(defaultHarnessMode)");
    expect(indexSource).not.toMatch(/register\(["'](?:acp|hermes|openclaw)["']/);
    expect(indexSource).not.toContain("ensureHermesAdapter");
    expect(indexSource).not.toContain("ensureOpenClawAdapter");
  });
});
