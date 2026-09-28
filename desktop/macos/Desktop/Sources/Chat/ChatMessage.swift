import Foundation

struct ChatMessage: Identifiable {
  var id: String  // Mutable while a provisional UI turn becomes a durable journal turn.
  let clientTurnId: String?
  var text: String
  let createdAt: Date
  let sender: ChatSender
  var isStreaming: Bool
  /// Whether the message has been accepted by the local journal authority.
  var isSynced: Bool
  /// Citations extracted from the AI response
  var citations: [Citation]
  /// Structured content blocks for AI messages (text interspersed with tool calls)
  var contentBlocks: [ChatContentBlock]
  /// Metadata about context used to generate this response (AI messages only)
  var metadata: MessageMetadata?
  /// Context text for proactive notification messages (not shown to user, sent to Gemini)
  var notificationContext: String?
  /// Screenshot JPEG data captured when a proactive notification was generated
  var notificationScreenshot: Data?
  /// User-attached files (screenshots, images, documents) — populated for user messages.
  var attachments: [ChatAttachment]
  /// Surface-neutral resources associated with this message. Assistant messages
  /// use this for generated artifacts; user messages derive resources from
  /// `attachments` for backwards compatibility.
  var resources: [ChatResource]

  /// Which surface produced this turn. This is only an ownership label for
  /// interruption/cancellation policy; chat history is canonical and renders
  /// every Intentive turn in every full chat timeline.
  var turnOwner: ChatTurnOwner?

  /// Kernel journal lifecycle when this message was projected from a journal
  /// row. Failed turns get a light visual treatment so they don't look completed.
  var journalStatus: KernelJournalTurnStatus?
  /// Delivery is independent of accepting the generated text into the journal.
  var voiceDeliveryOutcome: AIVoiceTurnOutcome?
  /// Retain canonical metadata when a terminal update replaces its JSON object.
  var journalMetadataJSON: String?

  init(
    id: String = UUID().uuidString, clientTurnId: String? = nil, text: String, createdAt: Date = Date(),
    sender: ChatSender, isStreaming: Bool = false, isSynced: Bool = false,
    citations: [Citation] = [], contentBlocks: [ChatContentBlock] = [], metadata: MessageMetadata? = nil,
    notificationContext: String? = nil, notificationScreenshot: Data? = nil, attachments: [ChatAttachment] = [],
    resources: [ChatResource] = [], turnOwner: ChatTurnOwner? = nil, journalStatus: KernelJournalTurnStatus? = nil,
    voiceDeliveryOutcome: AIVoiceTurnOutcome? = nil, journalMetadataJSON: String? = nil
  ) {
    self.id = id
    self.turnOwner = turnOwner
    self.clientTurnId = clientTurnId
    self.text = text
    self.createdAt = createdAt
    self.sender = sender
    self.isStreaming = isStreaming
    self.isSynced = isSynced
    self.citations = citations
    self.contentBlocks = contentBlocks
    self.metadata = metadata
    self.notificationContext = notificationContext
    self.notificationScreenshot = notificationScreenshot
    self.attachments = attachments
    self.resources = resources
    self.journalStatus = journalStatus
    self.voiceDeliveryOutcome = voiceDeliveryOutcome
    self.journalMetadataJSON = journalMetadataJSON
  }
}

extension ChatMessage {
  var journalDeliveryStatusLabel: String? {
    guard sender == .ai, !isStreaming else { return nil }
    if journalStatus == .failed { return "Couldn't save this reply" }
    switch voiceDeliveryOutcome {
    case .cancelled: return "Interrupted"
    case .failed: return "Voice reply incomplete"
    case .suppressed: return "Not spoken"
    case .completed, nil: return nil
    }
  }

  var copyableText: String {
    // A completed assistant turn can contain internal reasoning and transient
    // tool/lifecycle blocks alongside its user-visible answer. The message
    // copy affordance promises the answer, so retain only final text blocks.
    let finalOutput =
      contentBlocks
      .compactMap { block -> String? in
        guard case .text(_, let text) = block else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
      }
      .joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if !finalOutput.isEmpty {
      return finalOutput
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var displayResources: [ChatResource] {
    if !resources.isEmpty {
      return resources
    }
    return attachments.map(ChatResource.attachment)
  }
}
