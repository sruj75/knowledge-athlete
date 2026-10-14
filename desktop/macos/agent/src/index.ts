/** Local journal process. It never calls a model or executes tools. */
import { ConversationStorage } from "./conversation-storage.js";
import { dispatchConversationRequest } from "./conversation-protocol.js";
import { createStdoutLineSender } from "./stdout-line-sender.js";

const ownerId = process.env.INTENTIVE_STORAGE_OWNER_ID?.trim();
const stateDir = process.env.HEYINTENTIVE_AGENT_STATE_DIR?.trim();
if (!ownerId || !stateDir) throw new Error("conversation_storage_requires_owner_and_state_directory");
const storage = new ConversationStorage({ stateDir, ownerId });
const writeLine = createStdoutLineSender(
  (line) => process.stdout.write(line),
  (listener) => process.stdout.once("drain", listener),
  () => process.exit(1),
);
const send = (value: unknown) => writeLine(JSON.stringify(value) + "\n");
send({ type: "init", protocolVersion: 2, runtimeVersion: "conversation-1", runtimeCapabilities: ["chat_catalog", "conversation_journal"], ownerId });
let pending = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk: string) => {
  pending += chunk;
  if (Buffer.byteLength(pending) > 4_000_000) { storage.close(); process.exit(1); }
  let newline: number;
  while ((newline = pending.indexOf("\n")) >= 0) {
    const line = pending.slice(0, newline); pending = pending.slice(newline + 1);
    if (!line.trim()) continue;
    let input: unknown;
    try {
      input = JSON.parse(line) as unknown;
      const { wakes, ...response } = dispatchConversationRequest(storage, input);
      send(response);
      for (const wake of wakes ?? []) send({ type: "journal_turn_changed", protocolVersion: 2, ...wake });
    } catch (error) {
      const record = input && typeof input === "object" ? input as Record<string, unknown> : {};
      const known = error instanceof Error && ["journal_generation_stale", "conversation_owner_mismatch", "chat_catalog_not_found"].includes(error.message);
      send({ type: "error", protocolVersion: 2, ownerId, requestId: record.requestId, clientId: record.clientId, errorCode: known && error instanceof Error ? error.message : "invalid_conversation_request", message: "Conversation storage request failed" });
    }
  }
});
process.stdin.on("end", () => storage.close());
process.on("SIGTERM", () => { storage.close(); process.exit(0); });
