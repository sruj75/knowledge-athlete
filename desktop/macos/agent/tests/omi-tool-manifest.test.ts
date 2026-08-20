import { describe, expect, it } from "vitest";
import {
  buildToolAvailabilitySnapshot,
  normalizeOmiToolName,
  omiToolManifest,
  toolNamesForAdapter,
  toolsForAdapter,
} from "../src/runtime/omi-tool-manifest.js";

const expectedPiTools = [
  "execute_sql",
  "semantic_search",
  "get_daily_recap",
  "complete_task",
  "list_agent_sessions",
  "get_agent_run",
  "build_desktop_awareness_snapshot",
  "list_desktop_action_queue",
  "build_desktop_context_packet",
  "route_desktop_intent",
  "evaluate_desktop_tool_policy",
  "create_desktop_dispatch",
  "cancel_agent_run",
  "inspect_agent_artifacts",
  "read_tool_output",
  "search_tool_output",
  "update_agent_artifact_lifecycle",
  "send_agent_message",
  "spawn_agent",
  "run_agent_and_wait",
  "set_desktop_attention_override",
  "delete_task",
  "get_conversations",
  "search_conversations",
  "get_memories",
  "search_memories",
  "get_action_items",
  "create_action_item",
  "update_action_item",
  "capture_screen",
  "check_permission_status",
  "request_permission",
  "screenshot",
  "get_work_context",
];

describe("omi tool manifest", () => {
  it("projects the exact owned Pi typed-tool surface", () => {
    expect(toolNamesForAdapter("pi-mono")).toEqual(expectedPiTools);
    expect(toolNamesForAdapter("pi-mono")).not.toEqual(expect.arrayContaining([
      "bash", "read", "write", "edit", "load_skill", "search_skills",
      "scan_files", "set_user_preferences", "ask_followup", "complete_onboarding",
      "get_email_insights", "get_local_status", "get_screenshot",
    ]));
    expect(new Set(omiToolManifest.map((tool) => tool.name)).size).toBe(omiToolManifest.length);
  });

  it("projects agent-management tools out of leaf worker contexts", () => {
    const names = toolNamesForAdapter("pi-mono", { executionRole: "leaf" });
    expect(names).not.toContain("spawn_agent");
    expect(names).not.toContain("spawn_background_agent");
    expect(names).not.toContain("run_agent_and_wait");
    expect(names).not.toContain("send_agent_message");
  });

  it("keeps spawn provider, adapter, model, and working directory unrepresentable", () => {
    const spawn = toolsForAdapter("pi-mono").find((tool) => tool.name === "spawn_agent");
    expect(spawn?.inputSchema.required).toEqual(["objective"]);
    expect(spawn?.inputSchema.properties).not.toHaveProperty("provider");
    expect(spawn?.inputSchema.properties).not.toHaveProperty("adapterId");
    expect(spawn?.inputSchema.properties).not.toHaveProperty("model");
    expect(spawn?.inputSchema.properties).not.toHaveProperty("cwd");
    expect(toolNamesForAdapter("pi-mono")).not.toContain("spawn_background_agent");
  });

  it("does not advertise retired external product surfaces", () => {
    const retired = [
      "fill_cloud_connector_form",
      "save_knowledge_graph",
      "scan_files",
      "start_file_scan",
      "get_file_scan_results",
      "create_calendar_event",
      "set_user_preferences",
      "ask_followup",
      "complete_onboarding",
    ];

    const manifestNames = omiToolManifest.map((tool) => tool.name);
    for (const tool of retired) {
      expect(manifestNames).not.toContain(tool);
    }
  });

  it("keeps current-screen evidence separate from historical work context", () => {
    const workContext = toolsForAdapter("pi-mono").find((tool) => tool.name === "get_work_context");
    const captureScreen = toolsForAdapter("pi-mono").find((tool) => tool.name === "capture_screen");
    const screenshot = toolsForAdapter("pi-mono").find((tool) => tool.name === "screenshot");
    expect(workContext?.promptGuidelines?.join("\n")).toContain("not for direct current-screen questions");
    expect(captureScreen?.promptGuidelines?.join("\n")).toContain("requires explicit approval");
    expect(screenshot?.surfaces).toEqual(["realtime_voice"]);
    expect(screenshot?.executor).toEqual({ kind: "swiftTool", executorName: "realtimeHub" });
  });

  it("normalizes only declared typed-tool aliases", () => {
    expect(normalizeOmiToolName("pi-mono", "search_screen_history")).toEqual({
      canonicalName: "semantic_search",
      wasAlias: true,
    });
    expect(normalizeOmiToolName("pi-mono", "mcp__omi-tools__execute_sql")).toEqual({
      canonicalName: "mcp__omi-tools__execute_sql",
      wasAlias: false,
    });
  });

  it("builds a Pi-only debuggable availability snapshot", () => {
    const snapshot = buildToolAvailabilitySnapshot("pi-mono");
    expect(snapshot.adapterId).toBe("pi-mono");
    expect(snapshot.advertisedToolNames).toEqual(expectedPiTools);
    expect(snapshot.aliases["search_screen_history"]).toBe("semantic_search");
    expect(snapshot.aliases).not.toHaveProperty("mcp__omi-tools__execute_sql");
    expect(snapshot.disabled.some((tool) => tool.name === "get_tasks")).toBe(true);
  });

  it("keeps every manifest entry documented and provider schemas flat", () => {
    const internalOnly = new Set(["spawn_background_agent"]);
    for (const tool of omiToolManifest) {
      if (!internalOnly.has(tool.name)) expect(tool.surfaces.length, tool.name).toBeGreaterThan(0);
      expect(tool.capabilityDoc.title, tool.name).toBeTruthy();
      expect(tool.capabilityDoc.summary, tool.name).toBeTruthy();
      expect(tool.capabilityDoc.bullets.length, tool.name).toBeGreaterThan(0);
      expect(tool.inputSchema).toMatchObject({ type: "object", properties: expect.any(Object) });
      expect(tool.inputSchema).not.toHaveProperty("anyOf");
      expect(tool.inputSchema).not.toHaveProperty("oneOf");
      expect(tool.inputSchema).not.toHaveProperty("allOf");
    }
  });
});
