import Foundation

enum DesktopSentryConfiguration {
  static let organizationSlug = "heyintentive"
  static let projectSlug = "desktop-macos"

  // Sentry DSNs identify an ingestion destination and are intentionally public.
  // Authentication for symbol uploads remains in SENTRY_AUTH_TOKEN.
  static let dsn =
    "https://72ab6592781b225a42ecf704e6c6fc12@o4511576350326784.ingest.us.sentry.io/4511981568458752"
}
