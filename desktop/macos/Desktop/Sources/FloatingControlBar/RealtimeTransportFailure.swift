import Foundation
import Network

enum RealtimeHubTransportFailureKind: String, Equatable, Sendable {
  case localAddressUnavailable = "local_address_unavailable"
  case providerClose = "provider_close"
  case providerError = "provider_error"
  case configuration
  case connect
  case handshake
  case receive
  case send
  case protocolViolation = "protocol_violation"
  case unknown
}

struct RealtimeHubTransportFailure: Equatable, Sendable {
  let kind: RealtimeHubTransportFailureKind
  let message: String
  let systemDomain: String?
  let systemCode: Int?

  static func rawWebSocket(_ failure: RealtimeRawWebSocketFailure) -> Self {
    if let underlyingError = failure.underlyingError,
      isLocalAddressUnavailable(underlyingError)
    {
      return Self(
        kind: .localAddressUnavailable,
        message: failure.message,
        systemDomain: "posix",
        systemCode: Int(POSIXErrorCode.EADDRNOTAVAIL.rawValue))
    }
    return Self(
      kind: kind(for: failure.phase),
      message: failure.message,
      systemDomain: boundedSystemDomain(failure.underlyingError),
      systemCode: failure.underlyingError.map { ($0 as NSError).code })
  }

  static func providerClose(code: Int, reason: String) -> Self {
    Self(
      kind: .providerClose,
      message: "WebSocket closed (\(code)) \(reason)",
      systemDomain: nil,
      systemCode: code)
  }

  static func providerError(_ message: String) -> Self {
    Self(kind: .providerError, message: message, systemDomain: nil, systemCode: nil)
  }

  static func system(_ error: Error, phase: RealtimeHubTransportFailureKind) -> Self {
    if isLocalAddressUnavailable(error) {
      return Self(
        kind: .localAddressUnavailable,
        message: error.localizedDescription,
        systemDomain: "posix",
        systemCode: Int(POSIXErrorCode.EADDRNOTAVAIL.rawValue))
    }
    return Self(
      kind: phase,
      message: error.localizedDescription,
      systemDomain: boundedSystemDomain(error),
      systemCode: (error as NSError).code)
  }

  private static func kind(
    for phase: RealtimeRawWebSocketFailurePhase
  ) -> RealtimeHubTransportFailureKind {
    switch phase {
    case .configuration: return .configuration
    case .connect: return .connect
    case .handshake: return .handshake
    case .receive: return .receive
    case .send: return .send
    case .protocolViolation: return .protocolViolation
    }
  }

  private static func isLocalAddressUnavailable(_ error: Error) -> Bool {
    if let networkError = error as? NWError,
      case .posix(let code) = networkError
    {
      return code == .EADDRNOTAVAIL
    }
    let nsError = error as NSError
    return nsError.domain == NSPOSIXErrorDomain
      && nsError.code == Int(POSIXErrorCode.EADDRNOTAVAIL.rawValue)
  }

  private static func boundedSystemDomain(_ error: Error?) -> String? {
    guard let error else { return nil }
    if let networkError = error as? NWError {
      if case .posix = networkError { return "posix" }
      return "network"
    }
    let domain = (error as NSError).domain
    if domain == NSPOSIXErrorDomain { return "posix" }
    if domain == NSURLErrorDomain { return "url" }
    return "other"
  }
}

enum RealtimeHubCloseCategory: String {
  case expectedIdleTeardown = "expected_idle_teardown"
  case localAddressUnavailable = "local_address_unavailable"
  case transportConfiguration = "transport_configuration"
  case transportConnect = "transport_connect"
  case transportHandshake = "transport_handshake"
  case transportReceive = "transport_receive"
  case transportSend = "transport_send"
  case transportProtocolViolation = "transport_protocol_violation"
  case providerError = "provider_error"
  case providerAuthFailed = "provider_auth_failed"
  case providerQuotaExceeded = "provider_quota_exceeded"
  case providerPolicyCloseFast = "provider_policy_close_fast"
  case providerTransient = "provider_transient"
}
