import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";

import {
  applyExecutionProfileToSession,
  readSessionExecutionProfile,
} from "../src/runtime/session-execution-profile.js";
import { SqliteAgentStore } from "../src/runtime/sqlite-store.js";

const roots: string[] = [];
afterEach(() => {
  while (roots.length) rmSync(roots.pop()!, { recursive: true, force: true });
});

function harness() {
  const root = mkdtempSync(join(tmpdir(), "omi-profile-"));
  roots.push(root);
  return new SqliteAgentStore({ databasePath: join(root, "agent.sqlite"), reconcileOnOpen: false });
}

describe("SessionExecutionProfile", () => {
  it("creates and reads one immutable managed Pi profile", () => {
    const store = harness();
    const session = store.insertSession({
      ownerId: "owner",
      surfaceKind: "main_chat",
      defaultAdapterId: "pi-mono",
      providerBoundary: "managed_cloud",
      modelProfile: "gemini-3.7-flash",
      defaultCwd: "/tmp/omi-artifacts",
    });

    expect(readSessionExecutionProfile(store, session.sessionId)).toMatchObject({
      generation: 1,
      adapterId: "pi-mono",
      credentialScope: "managed_cloud",
      modelProfile: "gemini-3.7-flash",
      workingDirectory: "/tmp/omi-artifacts",
      executionRole: "coordinator",
      source: "creation",
    });
    expect(() => store.execute(
      "UPDATE session_execution_profiles SET adapter_id = 'test-adapter' WHERE session_id = ?",
      [session.sessionId],
    )).toThrow(/immutable/);
    store.close();
  });

  it("applies the authoritative profile projection without introducing selection", () => {
    const store = harness();
    const session = store.insertSession({
      ownerId: "owner",
      surfaceKind: "floating_bar",
      defaultAdapterId: "pi-mono",
      providerBoundary: "managed_cloud",
      modelProfile: "gemini-3.7-flash",
      defaultCwd: "/tmp/omi-artifacts",
    });
    const projected = applyExecutionProfileToSession(
      { ...session, defaultAdapterId: "stale", providerBoundary: "local_user:stale" },
      readSessionExecutionProfile(store, session.sessionId),
    );
    expect(projected).toMatchObject({
      defaultAdapterId: "pi-mono",
      providerBoundary: "managed_cloud",
      modelProfile: "gemini-3.7-flash",
      defaultCwd: "/tmp/omi-artifacts",
    });
    store.close();
  });
});
