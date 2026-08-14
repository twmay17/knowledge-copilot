import Foundation
import Observation

struct KnowledgePackSummary: Equatable, Sendable {
  let packID: String
  let title: String
  let profileReferences: [DomainProfileReference]
  let sourceCount: Int
  let assertionCount: Int
  let responseCardCount: Int

  init(pack: KnowledgePack) {
    packID = pack.manifest.packID
    title = pack.manifest.title
    profileReferences = pack.manifest.domainProfiles
    sourceCount = pack.sources.count
    assertionCount = pack.assertions.count
    responseCardCount = pack.responseCards.count
  }
}

enum KnowledgePackLoadState: Equatable, Sendable {
  case idle
  case loading(path: String)
  case loaded(path: String, summary: KnowledgePackSummary)
  case failed(path: String, message: String)
}

@MainActor
@Observable
final class KnowledgePackStore {
  private let loader: KnowledgePackLoader
  private(set) var selectedPack: KnowledgePack?
  private(set) var state: KnowledgePackLoadState = .idle
  private var requestedPath = ""

  init(profileRegistry: KnowledgeDomainProfileRegistry) {
    loader = KnowledgePackLoader(profileRegistry: profileRegistry)
  }

  func load(fromPath path: String) async {
    let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedPath.isEmpty else {
      clear()
      return
    }
    if requestedPath == normalizedPath {
      switch state {
      case .loading, .loaded:
        return
      case .idle, .failed:
        break
      }
    }

    requestedPath = normalizedPath
    state = .loading(path: normalizedPath)
    let loader = loader
    let directory = URL(fileURLWithPath: normalizedPath, isDirectory: true).standardizedFileURL

    do {
      let pack = try await Task.detached(priority: .userInitiated) {
        try loader.load(from: directory)
      }.value
      guard requestedPath == normalizedPath, !Task.isCancelled else { return }
      selectedPack = pack
      state = .loaded(path: normalizedPath, summary: KnowledgePackSummary(pack: pack))
    } catch {
      guard requestedPath == normalizedPath, !Task.isCancelled else { return }
      selectedPack = nil
      state = .failed(path: normalizedPath, message: String(describing: error))
    }
  }

  func retry() async {
    let path = requestedPath
    requestedPath = ""
    await load(fromPath: path)
  }

  func clear() {
    requestedPath = ""
    selectedPack = nil
    state = .idle
  }
}
