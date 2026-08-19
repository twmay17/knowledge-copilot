import XCTest
@testable import OpenOatsKit

/// WB-2b: the structured-output path (requests carrying a `jsonSchema`) gets exactly
/// one quiet retry on HTTP 429 before surfacing an error — shared-quota models 429
/// transiently in live use, and failing the whole turn over a momentary blip is worse
/// than a short, bounded wait. Plain (non-schema) calls — SuggestionEngine,
/// NotesEngine, etc. — keep today's exact behavior: no retry.
///
/// There is no HTTP-mocking layer in this test target (confirmed absent at WB-0; see
/// `.superpowers/sdd/wb0-report.md`), so — matching this file's existing convention of
/// testing the extracted decision logic directly rather than the network glue around
/// it — these tests drive `OpenRouterClient.sendRetryingRateLimit` directly with an
/// injected `send` closure that counts invocations, and an injected/shortened delay so
/// no real 2.5s sleep runs in the suite.
final class StructuredOutputRetryTests: XCTestCase {

    private func response(_ statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!,
                         statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }

    func testStructuredCallRetriesOnceAfter429ThenSucceeds() async throws {
        var callCount = 0
        let send: () async throws -> (Data, HTTPURLResponse) = { [self] in
            callCount += 1
            return callCount == 1 ? (Data(), response(429)) : (Data("ok".utf8), response(200))
        }

        let start = Date()
        let (data, httpResponse) = try await OpenRouterClient.sendRetryingRateLimit(
            hasSchema: true,
            delay: 0.05,
            send: send
        )
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(callCount, 2, "expected exactly one retry (two requests total)")
        XCTAssertEqual(httpResponse.statusCode, 200)
        XCTAssertEqual(data, Data("ok".utf8))
        XCTAssertGreaterThanOrEqual(elapsed, 0.04, "the injected delay should actually be awaited before the retry")
    }

    func testStructuredCallRetriesOnceThenSurfacesErrorIfStillRateLimited() async throws {
        var callCount = 0
        let send: () async throws -> (Data, HTTPURLResponse) = { [self] in
            callCount += 1
            return (Data(), response(429))
        }

        let (_, httpResponse) = try await OpenRouterClient.sendRetryingRateLimit(
            hasSchema: true,
            delay: 0.01,
            send: send
        )

        // Exactly one retry — no infinite loop. A still-429 response is handed back
        // unchanged so the caller's existing status-code guard in `complete()` throws
        // `OpenRouterError.httpError` exactly as it always has for a non-2xx result.
        XCTAssertEqual(callCount, 2, "no infinite loop — must not retry more than once")
        XCTAssertEqual(httpResponse.statusCode, 429)
    }

    func testPlainCallDoesNotRetryOn429() async throws {
        var callCount = 0
        let send: () async throws -> (Data, HTTPURLResponse) = { [self] in
            callCount += 1
            return (Data(), response(429))
        }

        let (_, httpResponse) = try await OpenRouterClient.sendRetryingRateLimit(
            hasSchema: false,
            delay: 0.05,
            send: send
        )

        // Pins the scope decision: plain (non-schema) calls keep today's exact
        // behavior. SuggestionEngine, NotesEngine, BatchTextCleaner,
        // LiveTranscriptCleaner, etc. are untouched by WB-2b.
        XCTAssertEqual(callCount, 1, "plain calls must not retry on 429")
        XCTAssertEqual(httpResponse.statusCode, 429)
    }
}
