import HospitalityDomainProfile
import XCTest

@testable import OpenOatsKit

final class KnowledgeOllamaStudyProviderTests: XCTestCase {
  func testProviderBuildsLoopbackStructuredRequestAndReturnsValidatedAnalysis() async throws {
    let bundle = try loadBundle()
    let sourceAnalysis = try loadAnalysis()
    let transport = RecordingOllamaStudyTransport(
      response: try successfulResponse(analysis: sourceAnalysis, model: "qwen3:8b")
    )
    let provider = try KnowledgeOllamaStudyProvider(
      baseURL: URL(string: "http://localhost:11434/v1")!,
      model: "qwen3:8b",
      requestTimeout: 42,
      transport: transport
    )

    let analysis = try await provider.analyze(bundle: bundle)

    XCTAssertEqual(provider.endpoint.absoluteString, "http://127.0.0.1:11434/api/chat")
    XCTAssertEqual(analysis.schemaVersion, 1)
    XCTAssertEqual(analysis.bundleID, bundle.bundleID)
    XCTAssertEqual(analysis.packID, bundle.packID)
    XCTAssertEqual(analysis.packContentHash, bundle.packContentHash)
    XCTAssertEqual(analysis.generator, "ollama:qwen3:8b")
    XCTAssertTrue(analysis.analysisID.hasPrefix("analysis-ollama-"))
    XCTAssertEqual(analysis.questionFamilyProposals.count, 1)
    XCTAssertEqual(analysis.responseCardProposals.count, 1)

    let recordedRequest = await transport.lastRequest()
    let request = try XCTUnwrap(recordedRequest)
    XCTAssertEqual(request.url, provider.endpoint)
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.timeoutInterval, 42)
    XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    let body = try XCTUnwrap(
      JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
    )
    XCTAssertEqual(body["model"] as? String, "qwen3:8b")
    XCTAssertEqual(body["stream"] as? Bool, false)
    XCTAssertNotNil(body["format"] as? [String: Any])
    let options = try XCTUnwrap(body["options"] as? [String: Any])
    XCTAssertEqual(options["temperature"] as? Int, 0)
    let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
    XCTAssertEqual(messages.map { $0["role"] }, ["system", "user"])
    XCTAssertTrue(messages[0]["content"]?.contains("only factual authority") == true)
    XCTAssertTrue(messages[1]["content"]?.contains(bundle.bundleID) == true)
    XCTAssertTrue(messages[1]["content"]?.contains(bundle.packContentHash) == true)
  }

  func testProviderCreatesDeterministicIdentityFromCanonicalValidatedOutput() async throws {
    let bundle = try loadBundle()
    let response = try successfulResponse(analysis: loadAnalysis(), model: "qwen3:8b")
    let transport = RecordingOllamaStudyTransport(response: response)
    let provider = try makeProvider(transport: transport)

    let first = try await provider.analyze(bundle: bundle)
    let second = try await provider.analyze(bundle: bundle)

    XCTAssertEqual(first, second)
    XCTAssertEqual(first.analysisID, second.analysisID)
    let requestCount = await transport.requestCount()
    XCTAssertEqual(requestCount, 2)
  }

  func testProviderUsesActualOllamaResponseModelAsTrustedProvenance() async throws {
    let bundle = try loadBundle()
    let transport = RecordingOllamaStudyTransport(
      response: try successfulResponse(analysis: loadAnalysis(), model: "qwen3:8b-q4_K_M")
    )
    let provider = try makeProvider(transport: transport)

    let analysis = try await provider.analyze(bundle: bundle)

    XCTAssertEqual(analysis.generator, "ollama:qwen3:8b-q4_K_M")
  }

  func testProviderRejectsExternalAndEncryptedEndpointsBeforeTransport() async throws {
    let transport = RecordingOllamaStudyTransport(
      response: KnowledgeOllamaStudyTransportResponse(statusCode: 200, data: Data())
    )

    XCTAssertThrowsError(
      try KnowledgeOllamaStudyProvider(
        baseURL: URL(string: "http://ollama.example:11434")!,
        model: "qwen3:8b",
        requestTimeout: 30,
        transport: transport
      )
    ) { error in
      guard case KnowledgeOllamaStudyProviderError.nonLoopbackBaseURL = error else {
        return XCTFail("Unexpected error: \(error)")
      }
    }
    XCTAssertThrowsError(
      try KnowledgeOllamaStudyProvider(
        baseURL: URL(string: "https://localhost:11434")!,
        model: "qwen3:8b",
        requestTimeout: 30,
        transport: transport
      )
    ) { error in
      guard case KnowledgeOllamaStudyProviderError.invalidBaseURL = error else {
        return XCTFail("Unexpected error: \(error)")
      }
    }

    let requestCount = await transport.requestCount()
    XCTAssertEqual(requestCount, 0)
  }

  func testProviderRejectsUnsupportedEvidenceBeforeReturningAnalysis() async throws {
    let bundle = try loadBundle()
    let sourceAnalysis = try loadAnalysis()
    let card = try XCTUnwrap(sourceAnalysis.responseCardProposals.first)
    let invalidCard = KnowledgeStudyResponseCardProposal(
      id: card.id,
      title: card.title,
      answer: card.answer,
      evidenceState: card.evidenceState,
      questionFamilyIDs: card.questionFamilyIDs,
      assertionIDs: ["assertion-invented-by-model"],
      citationPassageIDs: card.citationPassageIDs,
      calculationIDs: card.calculationIDs,
      caveat: card.caveat
    )
    let invalidAnalysis = copy(sourceAnalysis, responseCardProposals: [invalidCard])
    let transport = RecordingOllamaStudyTransport(
      response: try successfulResponse(analysis: invalidAnalysis, model: "qwen3:8b")
    )
    let provider = try makeProvider(transport: transport)

    do {
      _ = try await provider.analyze(bundle: bundle)
      XCTFail("Expected the evidence validator to reject the model proposal")
    } catch KnowledgeStudyAnalysisError.unknownReference(_, let type, let id) {
      XCTAssertEqual(type, "assertion")
      XCTAssertEqual(id, "assertion-invented-by-model")
    }
  }

  func testProviderFailsClosedOnHTTPAndMalformedModelOutput() async throws {
    let bundle = try loadBundle()
    let failedTransport = RecordingOllamaStudyTransport(
      response: KnowledgeOllamaStudyTransportResponse(
        statusCode: 503,
        data: Data("model unavailable".utf8)
      )
    )
    let failedProvider = try makeProvider(transport: failedTransport)

    do {
      _ = try await failedProvider.analyze(bundle: bundle)
      XCTFail("Expected an HTTP error")
    } catch KnowledgeOllamaStudyProviderError.httpError(let statusCode, let detail) {
      XCTAssertEqual(statusCode, 503)
      XCTAssertEqual(detail, "model unavailable")
    }

    let malformedTransport = RecordingOllamaStudyTransport(
      response: try response(model: "qwen3:8b", content: "not-json", done: true)
    )
    let malformedProvider = try makeProvider(transport: malformedTransport)
    do {
      _ = try await malformedProvider.analyze(bundle: bundle)
      XCTFail("Expected malformed structured output to fail")
    } catch KnowledgeOllamaStudyProviderError.invalidResponse(let detail) {
      XCTAssertTrue(detail.contains("draft schema"))
    }
  }

  func testProviderRejectsIncompleteAndEmptyResponses() async throws {
    let bundle = try loadBundle()
    let incomplete = RecordingOllamaStudyTransport(
      response: try response(model: "qwen3:8b", content: "{}", done: false)
    )
    do {
      _ = try await makeProvider(transport: incomplete).analyze(bundle: bundle)
      XCTFail("Expected incomplete generation to fail")
    } catch KnowledgeOllamaStudyProviderError.incompleteResponse {
    }

    let empty = RecordingOllamaStudyTransport(
      response: try response(model: "qwen3:8b", content: "  ", done: true)
    )
    do {
      _ = try await makeProvider(transport: empty).analyze(bundle: bundle)
      XCTFail("Expected empty generation to fail")
    } catch KnowledgeOllamaStudyProviderError.emptyAnalysis {
    }
  }

  private func makeProvider(
    transport: RecordingOllamaStudyTransport
  ) throws -> KnowledgeOllamaStudyProvider {
    try KnowledgeOllamaStudyProvider(
      baseURL: URL(string: "http://127.0.0.1:11434")!,
      model: "qwen3:8b",
      requestTimeout: 30,
      transport: transport
    )
  }

  private func successfulResponse(
    analysis: KnowledgeStudyAnalysis,
    model: String
  ) throws -> KnowledgeOllamaStudyTransportResponse {
    let draft = TestStudyDraft(
      questionFamilyProposals: analysis.questionFamilyProposals,
      responseCardProposals: analysis.responseCardProposals,
      contradictions: analysis.contradictions,
      corpusGaps: analysis.corpusGaps
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let content = try XCTUnwrap(String(data: encoder.encode(draft), encoding: .utf8))
    return try response(model: model, content: content, done: true)
  }

  private func response(
    model: String,
    content: String,
    done: Bool
  ) throws -> KnowledgeOllamaStudyTransportResponse {
    let data = try JSONEncoder().encode(
      TestOllamaChatResponse(
        model: model,
        message: TestOllamaChatResponse.Message(role: "assistant", content: content),
        done: done
      )
    )
    return KnowledgeOllamaStudyTransportResponse(statusCode: 200, data: data)
  }

  private func copy(
    _ analysis: KnowledgeStudyAnalysis,
    responseCardProposals: [KnowledgeStudyResponseCardProposal]
  ) -> KnowledgeStudyAnalysis {
    KnowledgeStudyAnalysis(
      schemaVersion: analysis.schemaVersion,
      analysisID: analysis.analysisID,
      bundleID: analysis.bundleID,
      packID: analysis.packID,
      packContentHash: analysis.packContentHash,
      generator: analysis.generator,
      questionFamilyProposals: analysis.questionFamilyProposals,
      responseCardProposals: responseCardProposals,
      contradictions: analysis.contradictions,
      corpusGaps: analysis.corpusGaps
    )
  }

  private func loadBundle() throws -> KnowledgeStudyBundle {
    let pack = try KnowledgePackLoader(
      profileRegistry: KnowledgeDomainProfileRegistry(profiles: [HospitalityDomainProfile()])
    ).load(from: packURL())
    return try KnowledgeStudyBundleBuilder().build(from: pack)
  }

  private func loadAnalysis() throws -> KnowledgeStudyAnalysis {
    try JSONDecoder().decode(
      KnowledgeStudyAnalysis.self,
      from: Data(contentsOf: analysisURL())
    )
  }

  private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private func packURL() -> URL {
    repositoryRoot().appendingPathComponent(
      "fixtures/knowledge-packs/minimal-hospitality",
      isDirectory: true
    )
  }

  private func analysisURL() -> URL {
    repositoryRoot().appendingPathComponent(
      "fixtures/study-analysis/synthetic-hospitality-analysis.json"
    )
  }
}

private actor RecordingOllamaStudyTransport: KnowledgeOllamaStudyTransport {
  private let response: KnowledgeOllamaStudyTransportResponse
  private var requests: [URLRequest] = []

  init(response: KnowledgeOllamaStudyTransportResponse) {
    self.response = response
  }

  func execute(_ request: URLRequest) async throws -> KnowledgeOllamaStudyTransportResponse {
    requests.append(request)
    return response
  }

  func lastRequest() -> URLRequest? {
    requests.last
  }

  func requestCount() -> Int {
    requests.count
  }
}

private struct TestStudyDraft: Encodable {
  let questionFamilyProposals: [KnowledgeStudyQuestionFamilyProposal]
  let responseCardProposals: [KnowledgeStudyResponseCardProposal]
  let contradictions: [KnowledgeStudyContradictionProposal]
  let corpusGaps: [KnowledgeStudyCorpusGapProposal]
}

private struct TestOllamaChatResponse: Encodable {
  struct Message: Encodable {
    let role: String
    let content: String
  }

  let model: String
  let message: Message
  let done: Bool
}
