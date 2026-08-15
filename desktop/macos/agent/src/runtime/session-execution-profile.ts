import { adapterCredentialScopeFor, isProductionAdapterId } from "../adapters/interface.js";
import { providerBoundaryForAdapter } from "./execution-policy.js";
import type { AgentSession, AgentStore, SessionCredentialScope, SessionExecutionProfile, SessionExecutionProfileSource } from "./types.js";

function nullableText(value: unknown): string | null {
  return value === null || value === undefined ? null : String(value);
}

export function credentialScopeForAdapter(adapterId: string): SessionCredentialScope {
  return isProductionAdapterId(adapterId) ? adapterCredentialScopeFor(adapterId) : "local_user";
}

export function sessionExecutionProfileFromRow(row: Record<string, unknown>): SessionExecutionProfile {
  return {
    sessionId: String(row.session_id),
    generation: Number(row.generation),
    adapterId: String(row.adapter_id),
    credentialScope: String(row.credential_scope) as SessionCredentialScope,
    modelProfile: nullableText(row.model_profile),
    workingDirectory: String(row.working_directory ?? ""),
    executionRole: String(row.execution_role) === "leaf" ? "leaf" : "coordinator",
    source: String(row.source) as SessionExecutionProfileSource,
    auditJson: String(row.audit_json ?? "{}"),
    createdAtMs: Number(row.created_at_ms),
  };
}

export function readSessionExecutionProfile(
  store: AgentStore,
  sessionId: string,
  generation?: number,
): SessionExecutionProfile {
  const row = generation === undefined
    ? store.getRow(
        `SELECT p.*
         FROM sessions s
         JOIN session_execution_profiles p
           ON p.session_id = s.session_id AND p.generation = s.current_profile_generation
         WHERE s.session_id = ?`,
        [sessionId],
      )
    : store.getRow(
        "SELECT * FROM session_execution_profiles WHERE session_id = ? AND generation = ?",
        [sessionId, generation],
      );
  return sessionExecutionProfileFromRow(row);
}

export function applyExecutionProfileToSession(
  session: AgentSession,
  profile: SessionExecutionProfile,
): AgentSession {
  if (session.sessionId !== profile.sessionId) {
    throw new Error("Execution profile does not belong to the session");
  }
  return {
    ...session,
    executionProfileGeneration: profile.generation,
    defaultAdapterId: profile.adapterId,
    defaultCwd: profile.workingDirectory || session.defaultCwd,
    modelProfile: profile.modelProfile,
    executionRole: profile.executionRole,
    providerBoundary: providerBoundaryForAdapter(profile.adapterId),
  };
}
