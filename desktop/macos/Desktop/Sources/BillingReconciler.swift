import Foundation

enum BillingReconciliationOutcome<Value> {
  case matched(Value)
  case timedOut(Value?)
  case failed
}

enum BillingReconciler {
  static let maximumReads = 8

  @MainActor
  static func poll<Value>(
    read: () async throws -> Value,
    matches: (Value) -> Bool,
    sleep: () async -> Void
  ) async -> BillingReconciliationOutcome<Value> {
    var lastValue: Value?
    var sawResponse = false

    for attempt in 0..<maximumReads {
      do {
        let value = try await read()
        sawResponse = true
        lastValue = value
        if matches(value) {
          return .matched(value)
        }
      } catch {
        // A provider projection can briefly be unavailable after returning
        // from checkout. The bounded read budget still owns termination.
      }

      if attempt < maximumReads - 1 {
        await sleep()
      }
    }

    return sawResponse ? .timedOut(lastValue) : .failed
  }
}
