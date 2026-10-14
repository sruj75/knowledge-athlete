import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { expect, it } from "vitest";
import { ConversationStorage } from "../src/conversation-storage.js";
import { dispatchConversationRequest } from "../src/conversation-protocol.js";

it("exposes only owned catalog and generation-fenced journal operations", () => {
  const stateDir = mkdtempSync(join(tmpdir(), "intentive-journal-wire-"));
  const storage = new ConversationStorage({ stateDir, ownerId: "owner" });
  const base = { protocolVersion: 2, requestId: "r", clientId: "c", ownerId: "owner" };
  const surface = { surfaceKind: "main_chat", externalRefKind: "chat", externalRefId: "default" };
  try {
    expect(dispatchConversationRequest(storage, { ...base, ...surface, type: "journal_list_turns" })).toMatchObject({
      type: "journal_operation_result", operation: "list", conversationGeneration: 1, turns: [],
    });
    expect(() => dispatchConversationRequest(storage, { ...base, type: "query", prompt: "execute arbitrary code" })).toThrow();
    expect(() => dispatchConversationRequest(storage, { ...base, type: "chat_catalog_list", ownerId: "another-owner" })).toThrow("owner");
    expect(() => dispatchConversationRequest(storage, { ...base, ...surface, type: "journal_record_exchange", turns: [] })).toThrow();
  } finally { storage.close(); rmSync(stateDir, { recursive: true, force: true }); }
});
