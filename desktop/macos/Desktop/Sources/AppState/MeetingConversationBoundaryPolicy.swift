import Foundation

enum MeetingConversationBoundaryPolicy {
  static func shouldFinishConversation(
    mode: AssistantSettings.SystemAudioCaptureMode,
    meetingStateReady: Bool,
    shouldCapture: Bool,
    hadActiveMeeting: Bool
  ) -> Bool {
    mode == .onlyDuringMeetings
      && meetingStateReady
      && !shouldCapture
      && hadActiveMeeting
  }
}
