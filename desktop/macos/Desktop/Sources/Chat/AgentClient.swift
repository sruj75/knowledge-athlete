import Foundation

/// One local catalog/journal API shared by typed, spoken, export and history surfaces.
enum AgentClient {
  typealias Session = AgentBridge
  static func makeSession() -> Session { AgentBridge() }
  static func makeBridge() -> AgentBridge { AgentBridge() }
}
