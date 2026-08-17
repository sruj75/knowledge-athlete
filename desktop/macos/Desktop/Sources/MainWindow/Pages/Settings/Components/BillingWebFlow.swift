import OmiTheme
import SwiftUI
import WebKit

struct BillingWebFlow: Identifiable {
  let id = UUID()
  let title: String
  let url: URL
  let successURL: URL
  let cancelURL: URL
}

enum BillingWebFlowOutcome {
  case completed
  case cancelled
  case dismissed
}

struct BillingWebFlowSheet: View {
  let flow: BillingWebFlow
  let onComplete: (BillingWebFlowOutcome) -> Void

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: OmiSpacing.md) {
        Text(flow.title)
          .scaledFont(size: OmiType.heading, weight: .semibold)
          .foregroundColor(OmiColors.textPrimary)

        Spacer()

        Button("Close") {
          onComplete(.dismissed)
        }
        .buttonStyle(OmiButtonStyle(.primary, size: .compact))
      }
      .padding(.horizontal, OmiSpacing.xl)
      .padding(.vertical, OmiSpacing.lg)
      .background(OmiColors.backgroundTertiary)

      Divider()

      BillingWebView(flow: flow, onComplete: onComplete)
        .frame(minWidth: 860, minHeight: 680)
    }
    .background(OmiColors.backgroundPrimary)
  }
}

struct BillingWebView: NSViewRepresentable {
  let flow: BillingWebFlow
  let onComplete: (BillingWebFlowOutcome) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(flow: flow, onComplete: onComplete)
  }

  func makeNSView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true

    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = context.coordinator
    webView.uiDelegate = context.coordinator
    webView.setValue(false, forKey: "drawsBackground")
    webView.load(URLRequest(url: flow.url))
    return webView
  }

  func updateNSView(_ nsView: WKWebView, context: Context) {}

  final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    let flow: BillingWebFlow
    let onComplete: (BillingWebFlowOutcome) -> Void
    var completionHandled = false

    init(flow: BillingWebFlow, onComplete: @escaping (BillingWebFlowOutcome) -> Void) {
      self.flow = flow
      self.onComplete = onComplete
    }

    @MainActor
    func webView(
      _ webView: WKWebView,
      decidePolicyFor navigationAction: WKNavigationAction,
      decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
      guard let url = navigationAction.request.url else {
        decisionHandler(.allow)
        return
      }

      if Self.urlsMatchCompletion(url, completionURL: flow.successURL) {
        finish(.completed)
        decisionHandler(.cancel)
        return
      }
      if Self.urlsMatchCompletion(url, completionURL: flow.cancelURL) {
        finish(.cancelled)
        decisionHandler(.cancel)
        return
      }

      decisionHandler(.allow)
    }

    static func urlsMatchCompletion(_ url: URL, completionURL: URL) -> Bool {
      guard url.scheme == completionURL.scheme,
        url.host == completionURL.host,
        url.path == completionURL.path
      else {
        return false
      }
      return url.port == completionURL.port
        && url.query == completionURL.query
        && url.fragment == completionURL.fragment
    }

    func webView(
      _ webView: WKWebView,
      createWebViewWith configuration: WKWebViewConfiguration,
      for navigationAction: WKNavigationAction,
      windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
      if navigationAction.targetFrame == nil, let requestURL = navigationAction.request.url {
        webView.load(URLRequest(url: requestURL))
      }
      return nil
    }

    func finish(_ outcome: BillingWebFlowOutcome) {
      guard !completionHandled else { return }
      completionHandled = true
      DispatchQueue.main.async {
        self.onComplete(outcome)
      }
    }
  }
}
