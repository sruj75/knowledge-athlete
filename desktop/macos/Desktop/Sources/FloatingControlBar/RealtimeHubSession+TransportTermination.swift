import Foundation

extension RealtimeHubSession {
  func stopAndWait() async {
    let transport: RealtimeRawWebSocketTransport? = await withCheckedContinuation { continuation in
      q.async { [weak self] in
        guard let self else {
          continuation.resume(returning: nil)
          return
        }
        let transport = self.rawWS
        self.beginStopOnQueue()
        continuation.resume(returning: transport)
      }
    }
    await waitForRawTransportTerminal(transport)
    let transportBox = SessionCallbackBox(transport)
    await withCheckedContinuation { continuation in
      q.async { [weak self] in
        if let rawTransport = transportBox.value, self?.rawWS === rawTransport {
          self?.rawWS = nil
        }
        continuation.resume()
      }
    }
  }

  private func waitForRawTransportTerminal(_ transport: RealtimeRawWebSocketTransport?) async {
    guard let transport else { return }
    await transport.closeAndWait()
  }
}
