struct PrivacyManagedService: Equatable {
  let name: String
  let purpose: String
}

enum PrivacyTruthPresentation {
  static let dataLocationTitle = "Local data on this Mac"
  static let dataLocationDetail =
    "Conversation transcripts, memories, tasks, insights, focus history, and Rewind data are saved in local app storage on this Mac. Features that need AI or transcription may send the selected input to managed providers for processing."

  static let analyticsControlTitle = "Share product analytics"
  static let analyticsControlDetail =
    "Controls PostHog product analytics only. Sentry crash diagnostics and Enhanced Diagnostics are separate."

  static let trackingCategories = [
    "Onboarding progress and settings changes",
    "App lifecycle, release, update, and feature use",
    "Transcription and conversation-processing outcomes",
    "Chat and tool-use outcomes",
    "Memory, task, insight, and focus outcomes",
    "Notification, floating-bar, and feedback actions",
    "Bounded reliability, fallback, and error classifications",
  ]

  static let trackingBoundary =
    "Product analytics uses bounded counts, states, classifications, and identifiers. When signed in, identity can include your account ID, email address, and display name; some feature events include app names or record identifiers. It does not include transcript text, chat prompts or responses, audio, screen images, or file paths."

  static let managedServices = [
    PrivacyManagedService(name: "Firebase", purpose: "Sign-in and minimal account data"),
    PrivacyManagedService(name: "Google Gemini", purpose: "Managed AI, embeddings, and realtime voice"),
    PrivacyManagedService(name: "Modulate", purpose: "Live and overflow transcription"),
    PrivacyManagedService(name: "OpenAI", purpose: "Text-to-speech only"),
    PrivacyManagedService(name: "Langfuse", purpose: "Model tracing and prompt management"),
    PrivacyManagedService(name: "PostHog", purpose: "Optional product analytics"),
    PrivacyManagedService(name: "Sentry", purpose: "Crash, error, and submitted-report diagnostics"),
  ]

  static let billingStatus = "Billing is disabled. Dodo Payments is not called by the current product."

  static let allText =
    [
      dataLocationTitle,
      dataLocationDetail,
      analyticsControlTitle,
      analyticsControlDetail,
      trackingBoundary,
      billingStatus,
    ] + trackingCategories + managedServices.flatMap { [$0.name, $0.purpose] }
}
