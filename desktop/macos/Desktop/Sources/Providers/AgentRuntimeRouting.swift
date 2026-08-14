import Foundation

enum AgentHarnessMode: String {
  case piMono = "piMono"
}

enum AgentAdapterId: String {
  case piMono = "pi-mono"
}

enum AgentRuntimeRouting {
  static func harnessMode(from rawValue: String) -> AgentHarnessMode? {
    switch rawValue {
    case AgentHarnessMode.piMono.rawValue, AgentAdapterId.piMono.rawValue:
      return .piMono
    default:
      return nil
    }
  }

  static func adapterId(for _: AgentHarnessMode) -> AgentAdapterId {
    .piMono
  }
}
