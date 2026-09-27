import Foundation

/// Accepted runtime output and its managed-provider request correlation.
extension AgentBridge {
  struct QueryResult {
    var managedRequestID: String?
    let text: String
    let costUsd: Double
    let omiSessionId: String
    let runId: String
    let attemptId: String
    let adapterSessionId: String?
    let terminalStatus: AgentQueryTerminalStatus
    let failure: AgentRuntimeFailure?
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    let artifacts: [AgentArtifactProjection]
    let completionDeltaArtifacts: [AgentArtifactProjection]

    init(
      text: String,
      costUsd: Double,
      omiSessionId: String,
      runId: String,
      attemptId: String,
      adapterSessionId: String?,
      terminalStatus: String?,
      failure: AgentRuntimeFailure? = nil,
      inputTokens: Int,
      outputTokens: Int,
      cacheReadTokens: Int,
      cacheWriteTokens: Int,
      artifacts: [AgentArtifactProjection] = [],
      completionDeltaArtifacts: [AgentArtifactProjection] = []
    ) {
      self.text = text
      self.costUsd = costUsd
      self.omiSessionId = omiSessionId
      self.runId = runId
      self.attemptId = attemptId
      self.adapterSessionId = adapterSessionId
      self.terminalStatus = AgentQueryTerminalStatus(wireValue: terminalStatus)
      self.failure = failure
      self.inputTokens = inputTokens
      self.outputTokens = outputTokens
      self.cacheReadTokens = cacheReadTokens
      self.cacheWriteTokens = cacheWriteTokens
      self.artifacts = artifacts
      self.completionDeltaArtifacts = completionDeltaArtifacts
    }

    @discardableResult
    func requireSucceeded() throws -> QueryResult {
      switch terminalStatus {
      case .succeeded:
        return self
      case .cancelled:
        throw BridgeError.stopped
      case .failed, .timedOut, .orphaned:
        let raw = failure?.displayMessage ?? (text.isEmpty ? "Agent failed" : text)
        throw failure.map(BridgeError.agentRuntimeFailure) ?? BridgeError.agentError(raw)
      case .invalid:
        throw BridgeError.agentError("Agent returned an invalid terminal status")
      }
    }
  }
}
