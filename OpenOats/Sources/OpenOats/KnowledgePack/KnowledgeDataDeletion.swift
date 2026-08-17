import Foundation

public enum KnowledgeDeletionArtifactKind: String, CaseIterable, Codable, Equatable, Sendable {
  case knowledgePack = "knowledge_pack"
  case transcript
  case audio
  case cache
}

public struct KnowledgeDeletionTarget: Equatable, Sendable {
  public let kind: KnowledgeDeletionArtifactKind
  public let url: URL
  public let allowedRoot: URL

  public init(kind: KnowledgeDeletionArtifactKind, url: URL, allowedRoot: URL) {
    self.kind = kind
    self.url = url
    self.allowedRoot = allowedRoot
  }
}

public struct KnowledgeDeletionResult: Equatable, Sendable {
  public let kind: KnowledgeDeletionArtifactKind
  public let url: URL
  public let existedBefore: Bool
  public let absentAfter: Bool

  public init(
    kind: KnowledgeDeletionArtifactKind,
    url: URL,
    existedBefore: Bool,
    absentAfter: Bool
  ) {
    self.kind = kind
    self.url = url
    self.existedBefore = existedBefore
    self.absentAfter = absentAfter
  }
}

public struct KnowledgeDeletionReceipt: Equatable, Sendable {
  public let results: [KnowledgeDeletionResult]

  public init(results: [KnowledgeDeletionResult]) {
    self.results = results
  }

  public var isComplete: Bool {
    !results.isEmpty && results.allSatisfy(\.absentAfter)
  }

  public var removedKinds: Set<KnowledgeDeletionArtifactKind> {
    Set(results.filter(\.existedBefore).map(\.kind))
  }
}

public enum KnowledgeDataDeletionError: Error, Equatable, CustomStringConvertible {
  case emptyRequest
  case targetIsAllowedRoot(KnowledgeDeletionArtifactKind)
  case targetOutsideAllowedRoot(KnowledgeDeletionArtifactKind)
  case deletionFailed(KnowledgeDeletionArtifactKind)

  public var description: String {
    switch self {
    case .emptyRequest:
      "Deletion requires at least one explicit target."
    case .targetIsAllowedRoot(let kind):
      "Refusing to delete the broad allowed root for \(kind.rawValue)."
    case .targetOutsideAllowedRoot(let kind):
      "Refusing to delete \(kind.rawValue) outside its explicit allowed root."
    case .deletionFailed(let kind):
      "Failed to prove deletion of \(kind.rawValue)."
    }
  }
}

/// Deletes only explicit, root-contained local artifacts and returns an auditable absence receipt.
public struct KnowledgeDataDeletionService: Sendable {
  public init() {}

  public func delete(_ targets: [KnowledgeDeletionTarget]) throws -> KnowledgeDeletionReceipt {
    guard !targets.isEmpty else { throw KnowledgeDataDeletionError.emptyRequest }
    let validated = try targets.map(validate)
      .sorted { $0.canonicalTarget.path.count > $1.canonicalTarget.path.count }
    var results: [KnowledgeDeletionResult] = []

    for item in validated {
      let existedBefore = FileManager.default.fileExists(atPath: item.canonicalTarget.path)
      if existedBefore {
        do {
          try FileManager.default.removeItem(at: item.canonicalTarget)
        } catch {
          throw KnowledgeDataDeletionError.deletionFailed(item.target.kind)
        }
      }
      let absentAfter = !FileManager.default.fileExists(atPath: item.canonicalTarget.path)
      guard absentAfter else {
        throw KnowledgeDataDeletionError.deletionFailed(item.target.kind)
      }
      results.append(
        KnowledgeDeletionResult(
          kind: item.target.kind,
          url: item.target.url,
          existedBefore: existedBefore,
          absentAfter: absentAfter
        )
      )
    }

    var order: [ResultKey: Int] = [:]
    for (offset, target) in targets.enumerated() {
      let key = ResultKey(kind: target.kind, url: target.url.standardizedFileURL)
      if order[key] == nil { order[key] = offset }
    }
    results.sort {
      order[ResultKey(kind: $0.kind, url: $0.url.standardizedFileURL), default: .max]
        < order[ResultKey(kind: $1.kind, url: $1.url.standardizedFileURL), default: .max]
    }
    return KnowledgeDeletionReceipt(results: results)
  }

  private struct ValidatedTarget {
    let target: KnowledgeDeletionTarget
    let canonicalTarget: URL
  }

  private struct ResultKey: Hashable {
    let kind: KnowledgeDeletionArtifactKind
    let url: URL
  }

  private func validate(_ target: KnowledgeDeletionTarget) throws -> ValidatedTarget {
    let root = target.allowedRoot.standardizedFileURL.resolvingSymlinksInPath()
    let candidate = target.url.standardizedFileURL.resolvingSymlinksInPath()
    guard candidate.path != root.path else {
      throw KnowledgeDataDeletionError.targetIsAllowedRoot(target.kind)
    }
    guard candidate.path.hasPrefix(root.path + "/") else {
      throw KnowledgeDataDeletionError.targetOutsideAllowedRoot(target.kind)
    }
    return ValidatedTarget(target: target, canonicalTarget: candidate)
  }
}
