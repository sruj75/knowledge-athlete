import Foundation

extension DesktopAutomationActionRegistry {
  func registerSupervisorDiagnosticActions() {
    register(
      name: "supervisor_diagnostics_snapshot",
      summary: "Read content-free Supervisor counters, input age and scheduler status. Non-production only."
    ) { _ in
      guard AppBuild.isNonProduction else {
        return ["error": "Supervisor diagnostics are disabled on production bundles"]
      }
      let snapshot = SupervisorService.shared.diagnosticSnapshot()
      let data = try JSONEncoder().encode(snapshot)
      return ["snapshot_json": String(decoding: data, as: UTF8.self), "scope": "supervisor_observation"]
    }
  }
}
