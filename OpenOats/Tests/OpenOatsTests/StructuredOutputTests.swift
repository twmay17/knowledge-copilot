import XCTest
@testable import OpenOatsKit

/// The OpenAI-compatible and Anthropic transports spell structured output
/// differently, and sending one shape to the other provider is rejected. These
/// pin the wire format for both.
final class StructuredOutputTests: XCTestCase {

    private func encode(_ value: some Encodable) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private var spec: OpenRouterClient.JSONSchemaSpec {
        OpenRouterClient.JSONSchemaSpec(
            name: "sidecast_response",
            schema: .object([
                "type": .string("object"),
                "properties": .object([
                    "priority": .nullable("number"),
                ]),
                "required": .array([.string("priority")]),
                "additionalProperties": .bool(false),
            ])
        )
    }

    // MARK: - OpenAI-compatible shape

    func testChatCompletionsUsesResponseFormatWithNameAndStrict() throws {
        let request = OpenRouterClient.ChatRequest(
            model: "google/gemini-3.7-flash",
            messages: [],
            stream: false,
            max_tokens: nil,
            max_completion_tokens: 700,
            temperature: 0.7,
            plugins: nil,
            response_format: .init(
                type: "json_schema",
                json_schema: .init(name: spec.name, strict: true, schema: spec.schema)
            )
        )

        let json = try encode(request)
        let format = try XCTUnwrap(json["response_format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")

        let payload = try XCTUnwrap(format["json_schema"] as? [String: Any])
        XCTAssertEqual(payload["name"] as? String, "sidecast_response")
        XCTAssertEqual(payload["strict"] as? Bool, true)
        XCTAssertNotNil(payload["schema"])

        // The Anthropic key must never appear on this transport.
        XCTAssertNil(json["output_config"])
    }

    // MARK: - Anthropic shape

    func testAnthropicUsesOutputConfigWithoutNameOrStrict() throws {
        let config = OpenRouterClient.OutputConfig(
            format: .init(type: "json_schema", schema: spec.schema)
        )

        let json = try encode(config)
        let format = try XCTUnwrap(json["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertNotNil(format["schema"])

        // `name` and `strict` are the OpenAI spelling — Anthropic rejects them.
        XCTAssertNil(format["name"])
        XCTAssertNil(format["strict"])
    }

    // MARK: - Cross-provider schema encoding

    func testNullableUsesAnyOfNotTypeArray() throws {
        // Anthropic's schema subset accepts `anyOf` but not `["number","null"]`
        // type unions; OpenAI-compatible providers accept both. `anyOf` is the
        // only encoding that works on every transport this client speaks.
        let json = try encode(OpenRouterClient.JSONValue.object(["v": .nullable("number")]))
        let field = try XCTUnwrap(json["v"] as? [String: Any])

        XCTAssertNil(field["type"], "a type union would break the Anthropic transport")

        let anyOf = try XCTUnwrap(field["anyOf"] as? [[String: Any]])
        XCTAssertEqual(anyOf.compactMap { $0["type"] as? String }, ["number", "null"])
    }

    func testEncodingIsStableAcrossRuns() throws {
        // Swift dictionaries iterate in nondeterministic order; .sortedKeys makes
        // the same schema serialize to the same bytes every time.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let first = try encoder.encode(spec.schema)
        let second = try encoder.encode(spec.schema)
        XCTAssertEqual(first, second)
    }

    // MARK: - Degradation

    func testSchemaRejectionDetection() {
        // Rejections that name the schema field degrade to prompt-only JSON.
        XCTAssertTrue(OpenRouterClient.isSchemaRejection(
            400, body: #"{"error":{"message":"response_format is not supported"}}"#))
        XCTAssertTrue(OpenRouterClient.isSchemaRejection(
            400, body: #"{"error":{"message":"output_config.format unsupported on this model"}}"#))

        // Unrelated failures must still surface as errors.
        XCTAssertFalse(OpenRouterClient.isSchemaRejection(
            401, body: #"{"error":{"message":"invalid api key"}}"#))
        XCTAssertFalse(OpenRouterClient.isSchemaRejection(
            402, body: #"{"error":{"message":"insufficient credits"}}"#))
        XCTAssertFalse(OpenRouterClient.isSchemaRejection(
            400, body: #"{"error":{"message":"max_tokens must be positive"}}"#))
    }
}
