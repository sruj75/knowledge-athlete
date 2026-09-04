/// Unauthenticated loopback health payload used to bind harness evidence to
/// the exact running bundle without exposing user or provider data.
struct DesktopAutomationHealth: Codable {
  let ok: Bool
  let name: String
  let bundleIdentifier: String
  let processID: Int32
  let logFilePath: String
  let logLaunchID: String
  let bridgePort: UInt16
  let requiresAuth: Bool
  let backendEnvironment: String
  let backendURL: String
  let sourceGitSHA: String?
  let sourceTreeDirty: Bool?
  let agentRuntimeRunning: Bool
  let agentRuntimeExpectedProtocolVersion: Int
  let agentRuntimeProtocolVersion: Int?
  let agentRuntimeVersion: String?
}
