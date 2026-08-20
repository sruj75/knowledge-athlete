import Foundation
@preconcurrency import GRDB

enum MemoryCategory: String, Codable, CaseIterable, Sendable {
  case system
  case interesting
  case manual

  var displayName: String {
    switch self {
    case .system: return "About You"
    case .interesting: return "Insights"
    case .manual: return "Manual"
    }
  }

  var icon: String {
    switch self {
    case .system: return "person"
    case .interesting: return "lightbulb"
    case .manual: return "square.and.pencil"
    }
  }
}

enum MemoryLayer: String, Codable, CaseIterable, Identifiable, Sendable {
  case shortTerm = "short_term"
  case longTerm = "long_term"
  case archive

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .shortTerm: return "Short-term"
    case .longTerm: return "Long-term"
    case .archive: return "Archive"
    }
  }

  var icon: String {
    switch self {
    case .shortTerm: return "clock"
    case .longTerm: return "brain.head.profile"
    case .archive: return "archivebox"
    }
  }

  var isDefaultAccessible: Bool { self != .archive }

  var layerInfoText: String {
    switch self {
    case .shortTerm:
      return "Recent observations from your activity. May decay or promote to Long-term when corroborated."
    case .longTerm:
      return "Durable facts saved on this Mac - stable details about you, your preferences, and your life."
    case .archive:
      return "Aged-out long-term memories. Hidden by default; search Archive to find them."
    }
  }
}

struct MemoryLayerScope: Equatable, Sendable {
  let layers: [MemoryLayer]
  let requiresArchiveAcknowledgement: Bool

  static let defaultAccess = MemoryLayerScope(
    layers: [.shortTerm, .longTerm],
    requiresArchiveAcknowledgement: false
  )
  static let archiveOnly = MemoryLayerScope(
    layers: [.archive],
    requiresArchiveAcknowledgement: true
  )
  static let allIncludingArchive = MemoryLayerScope(
    layers: [.shortTerm, .longTerm, .archive],
    requiresArchiveAcknowledgement: true
  )

  var includesArchive: Bool { layers.contains(.archive) }
  var sqlLayerRawValues: [String] { layers.map(\.rawValue) }
}

enum MemorySource: String, Codable, Sendable {
  case desktop
  case screenshot
  case conversation
  case manual
  case focus
  case insight
}

struct MemoryAssertion: Sendable {
  let content: String
  let category: MemoryCategory
  let layer: MemoryLayer
  let expiresAt: Date?
  let tags: [String]
  let manuallyAdded: Bool
  let source: MemorySource
  let conversationId: String?
  let sourceSegmentId: String?
  let screenshotId: Int64?
  let confidence: Double?
  let reasoning: String?
  let sourceApp: String?
  let windowTitle: String?
  let contextSummary: String?
  let currentActivity: String?
  let inputDeviceName: String?

  init(
    content: String,
    category: MemoryCategory = .system,
    layer: MemoryLayer = .shortTerm,
    expiresAt: Date? = nil,
    tags: [String] = [],
    manuallyAdded: Bool = false,
    source: MemorySource = .desktop,
    conversationId: String? = nil,
    sourceSegmentId: String? = nil,
    screenshotId: Int64? = nil,
    confidence: Double? = nil,
    reasoning: String? = nil,
    sourceApp: String? = nil,
    windowTitle: String? = nil,
    contextSummary: String? = nil,
    currentActivity: String? = nil,
    inputDeviceName: String? = nil
  ) {
    self.content = content
    self.category = category
    self.layer = layer
    self.expiresAt = expiresAt
    self.tags = tags
    self.manuallyAdded = manuallyAdded
    self.source = source
    self.conversationId = conversationId
    self.sourceSegmentId = sourceSegmentId
    self.screenshotId = screenshotId
    self.confidence = confidence
    self.reasoning = reasoning
    self.sourceApp = sourceApp
    self.windowTitle = windowTitle
    self.contextSummary = contextSummary
    self.currentActivity = currentActivity
    self.inputDeviceName = inputDeviceName
  }
}

struct MemoryRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
  var id: Int64?
  var content: String
  var category: String
  var layer: String
  var expiresAt: Date?
  var revision: Int
  var tagsJson: String?
  var manuallyAdded: Bool
  var source: String?
  var conversationId: String?
  var sourceSegmentId: String?
  var screenshotId: Int64?
  var confidence: Double?
  var reasoning: String?
  var sourceApp: String?
  var windowTitle: String?
  var contextSummary: String?
  var currentActivity: String?
  var inputDeviceName: String?
  var isRead: Bool
  var isDismissed: Bool
  var pendingDeleteDeadline: Date?
  var createdAt: Date
  var updatedAt: Date
  var correctedAt: Date?

  static let databaseTableName = "memories"

  init(
    id: Int64? = nil,
    content: String,
    category: String = MemoryCategory.system.rawValue,
    layer: String = MemoryLayer.shortTerm.rawValue,
    expiresAt: Date? = nil,
    revision: Int = 1,
    tagsJson: String? = nil,
    manuallyAdded: Bool = false,
    source: String? = MemorySource.desktop.rawValue,
    conversationId: String? = nil,
    sourceSegmentId: String? = nil,
    screenshotId: Int64? = nil,
    confidence: Double? = nil,
    reasoning: String? = nil,
    sourceApp: String? = nil,
    windowTitle: String? = nil,
    contextSummary: String? = nil,
    currentActivity: String? = nil,
    inputDeviceName: String? = nil,
    isRead: Bool = false,
    isDismissed: Bool = false,
    pendingDeleteDeadline: Date? = nil,
    createdAt: Date = Date(),
    updatedAt: Date = Date(),
    correctedAt: Date? = nil
  ) {
    self.id = id
    self.content = content
    self.category = category
    self.layer = layer
    self.expiresAt = expiresAt
    self.revision = revision
    self.tagsJson = tagsJson
    self.manuallyAdded = manuallyAdded
    self.source = source
    self.conversationId = conversationId
    self.sourceSegmentId = sourceSegmentId
    self.screenshotId = screenshotId
    self.confidence = confidence
    self.reasoning = reasoning
    self.sourceApp = sourceApp
    self.windowTitle = windowTitle
    self.contextSummary = contextSummary
    self.currentActivity = currentActivity
    self.inputDeviceName = inputDeviceName
    self.isRead = isRead
    self.isDismissed = isDismissed
    self.pendingDeleteDeadline = pendingDeleteDeadline
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.correctedAt = correctedAt
  }

  mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

  var tags: [String] { Self.decodeTags(tagsJson) }

  mutating func setTags(_ tags: [String]) { tagsJson = Self.encodeTags(tags) }

  func hasTag(_ tag: String) -> Bool { tags.contains(tag) }
  var isTips: Bool { hasTag("tips") }
  var isFocus: Bool { hasTag("focus") }
  var isRegularMemory: Bool { !isTips && !isFocus }

  static let screenshot = belongsTo(Screenshot.self)
  var screenshot: QueryInterfaceRequest<Screenshot> { request(for: MemoryRecord.screenshot) }

  func toMemoryItem() -> MemoryItem? {
    guard let id,
      !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let category = MemoryCategory(rawValue: category),
      let layer = MemoryLayer(rawValue: layer)
    else { return nil }

    return MemoryItem(
      id: String(id),
      content: content,
      category: category,
      layer: layer,
      expiresAt: expiresAt,
      revision: revision,
      createdAt: createdAt,
      updatedAt: updatedAt,
      correctedAt: correctedAt,
      conversationId: conversationId,
      sourceSegmentId: sourceSegmentId,
      manuallyAdded: manuallyAdded,
      source: source.flatMap(MemorySource.init(rawValue:)),
      confidence: confidence,
      sourceApp: sourceApp,
      contextSummary: contextSummary,
      isRead: isRead,
      isDismissed: isDismissed,
      tags: tags,
      reasoning: reasoning,
      currentActivity: currentActivity,
      inputDeviceName: inputDeviceName,
      windowTitle: windowTitle,
      screenshotId: screenshotId
    )
  }

  static func from(assertion: MemoryAssertion, now: Date) -> MemoryRecord {
    MemoryRecord(
      content: assertion.content,
      category: assertion.category.rawValue,
      layer: assertion.layer.rawValue,
      expiresAt: assertion.expiresAt,
      tagsJson: encodeTags(assertion.tags),
      manuallyAdded: assertion.manuallyAdded,
      source: assertion.source.rawValue,
      conversationId: assertion.conversationId,
      sourceSegmentId: assertion.sourceSegmentId,
      screenshotId: assertion.screenshotId,
      confidence: assertion.confidence,
      reasoning: assertion.tags.contains("tips") ? assertion.reasoning : nil,
      sourceApp: assertion.sourceApp,
      windowTitle: assertion.windowTitle,
      contextSummary: assertion.contextSummary,
      currentActivity: assertion.currentActivity,
      inputDeviceName: assertion.inputDeviceName,
      createdAt: now,
      updatedAt: now
    )
  }

  private static func encodeTags(_ tags: [String]) -> String? {
    guard !tags.isEmpty,
      let data = try? JSONEncoder().encode(tags),
      let value = String(data: data, encoding: .utf8)
    else { return nil }
    return value
  }

  private static func decodeTags(_ value: String?) -> [String] {
    guard let value, let data = value.data(using: .utf8) else { return [] }
    return (try? JSONDecoder().decode([String].self, from: data)) ?? []
  }
}

struct MemoryItem: Identifiable, Equatable, Sendable {
  let id: String
  let content: String
  let category: MemoryCategory
  let layer: MemoryLayer
  let expiresAt: Date?
  let revision: Int
  let createdAt: Date
  let updatedAt: Date
  let correctedAt: Date?
  let conversationId: String?
  let sourceSegmentId: String?
  let manuallyAdded: Bool
  let source: MemorySource?
  let confidence: Double?
  let sourceApp: String?
  let contextSummary: String?
  let isRead: Bool
  let isDismissed: Bool
  let tags: [String]
  let reasoning: String?
  let currentActivity: String?
  let inputDeviceName: String?
  let windowTitle: String?
  let screenshotId: Int64?

  var confidenceString: String? {
    confidence.map { "\(Int($0 * 100))%" }
  }

  var sourceName: String? {
    switch source {
    case .desktop: return "Desktop"
    case .screenshot: return "Screenshot"
    case .manual: return manuallyAdded ? nil : "Desktop"
    case .conversation: return "Conversation"
    case .focus: return "Desktop"
    case .insight: return "Desktop"
    case .none: return nil
    }
  }

  var sourceIcon: String {
    switch source {
    case .screenshot: return "camera.viewfinder"
    case .conversation: return "waveform"
    default: return "desktopcomputer"
    }
  }

  var isTip: Bool { tags.contains("tips") }
  var tipCategory: String? {
    guard isTip else { return nil }
    return tags.first { ["productivity", "health", "communication", "learning", "other"].contains($0) }
  }

  var tipCategoryIcon: String {
    switch tipCategory {
    case "productivity": return "chart.line.uptrend.xyaxis"
    case "health": return "heart.fill"
    case "communication": return "bubble.left.and.bubble.right.fill"
    case "learning": return "book.fill"
    default: return "lightbulb.fill"
    }
  }
}

struct MemorySemanticMatch: Equatable, Sendable {
  let memory: MemoryItem
  let score: Double
}

struct MemoryExtractionAdmission: Equatable, Sendable {
  let content: String
  let category: MemoryCategory
  let quote: String
  let segmentId: String
  let confidence: Double
}

enum MemoryConsolidationAction: String, Equatable, Sendable {
  case promote
  case archive
  case review
  case reject
}

enum MemoryReconciliation: String, Equatable, Sendable {
  case create
  case duplicate
  case replace
  case merge
  case keepBoth = "keep_both"
}

struct MemoryConsolidationTarget: Equatable, Sendable {
  let memoryId: String
  let expectedRevision: Int
}

struct MemoryConsolidationApplication: Equatable, Sendable {
  let workId: String
  let memoryId: String
  let expectedRevision: Int
  let action: MemoryConsolidationAction
  let reconciliation: MemoryReconciliation
  let targets: [MemoryConsolidationTarget]
  let memoryText: String?
  let rationale: String
}

enum MemoryProcessingKind: String, Codable, Sendable {
  case normalize
  case extract
  case consolidate
  case embed
}

enum MemoryProcessingState: String, Codable, Sendable {
  case pending
  case leased
  case retry
  case completed
  case terminal
}

struct MemoryProcessingWorkRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
  var id: String
  var memoryId: Int64?
  var conversationId: String?
  var kind: String
  var inputRevision: Int
  var inputGeneration: Int
  var ownerGeneration: Int
  var state: String
  var attemptCount: Int
  var nextAttemptAt: Date
  var leaseExpiresAt: Date?
  var lastErrorCode: String?
  var createdAt: Date
  var updatedAt: Date

  static let databaseTableName = "memory_processing_work"
}

struct MemoryTransitionRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
  var id: String
  var memoryId: Int64
  var idempotencyKey: String
  var fromLayer: String?
  var toLayer: String?
  var inputRevision: Int
  var outputRevision: Int
  var outcome: String
  var receiptId: String?
  var createdAt: Date

  static let databaseTableName = "memory_transitions"
}

struct MemoryEmbeddingRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
  var memoryId: Int64
  var revision: Int
  var model: String
  var vectorJson: String
  var updatedAt: Date

  static let databaseTableName = "memory_embeddings"
}

extension MemoryRecord: TableDocumented {
  static var tableDescription: String { ChatPrompts.tableAnnotations["memories"]! }
  static var columnDescriptions: [String: String] { ChatPrompts.columnAnnotations["memories"] ?? [:] }
}

enum MemoryStorageError: LocalizedError, Equatable {
  case databaseNotInitialized
  case recordNotFound
  case emptyContent
  case staleRevision
  case invalidIdentity
  case invalidEmbedding
  case invalidTransition(String)

  var errorDescription: String? {
    switch self {
    case .databaseNotInitialized: return "Memory storage database is not initialized"
    case .recordNotFound: return "Memory record not found"
    case .emptyContent: return "Memory content cannot be empty"
    case .staleRevision: return "Memory changed before this result could be applied"
    case .invalidIdentity: return "Memory identity is not a local row ID"
    case .invalidEmbedding: return "Memory embedding is invalid"
    case .invalidTransition(let message): return "Invalid memory transition: \(message)"
    }
  }
}
