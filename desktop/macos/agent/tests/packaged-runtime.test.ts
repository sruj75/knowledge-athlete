import { existsSync, readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const packageJson = JSON.parse(readFileSync(new URL("../package.json", import.meta.url), "utf8")) as {
  dependencies?: Record<string, string>;
  scripts?: Record<string, string>;
};

describe("packaged managed Pi runtime", () => {
  it("contains no alternate adapter, MCP, browser, stdio, or ACP bridge assets", () => {
    expect(Object.keys(packageJson.dependencies ?? {})).toEqual([
      "@earendil-works/pi-coding-agent",
      "zod",
    ]);
    expect(packageJson.scripts?.build).toBe("rm -rf dist && tsc");

    for (const retiredPath of [
      "../src/adapters/acp.ts",
      "../src/adapters/hermes.ts",
      "../src/adapters/openclaw.ts",
      "../src/adapters/local-subprocess.ts",
      "../src/adapters/one-shot-cli.ts",
      "../src/omi-tools-http.ts",
      "../src/omi-tools-stdio.ts",
      "../src/patched-acp-entry.mjs",
      "../../acp-bridge",
    ]) {
      expect(existsSync(new URL(retiredPath, import.meta.url)), retiredPath).toBe(false);
    }

    const preparationScript = readFileSync(
      new URL("../../scripts/prepare-agent-runtime.sh", import.meta.url),
      "utf8",
    );
    expect(preparationScript).not.toMatch(
      /patched-acp-entry|claude-agent-acp|node-tools\.ts|sharp-darwin|libvips/,
    );

    const signedArtifactSmoke = readFileSync(
      new URL("../../scripts/smoke-signed-desktop-artifact.sh", import.meta.url),
      "utf8",
    );
    expect(signedArtifactSmoke).not.toMatch(/sharp-darwin|libvips/);

    const developmentBundler = readFileSync(
      new URL("../../run.sh", import.meta.url),
      "utf8",
    );
    expect(developmentBundler).not.toMatch(/node-tools\.ts|patched-acp-entry|acp-bridge/);
  });
});
