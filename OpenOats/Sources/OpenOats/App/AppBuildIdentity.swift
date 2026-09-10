import Foundation

enum AppBuildIdentity {
    static let displayName = "Knowledge Copilot Dev"
    static var detail: String {
        detail(info: Bundle.main.infoDictionary ?? [:])
    }

    static func detail(info: [String: Any]) -> String {
        let revision = info["KnowledgeCopilotBuildRevision"] as? String ?? "unpackaged"
        let builtAt = info["KnowledgeCopilotBuildDate"] as? String ?? "build date unavailable"
        return "\(revision) · \(builtAt)"
    }

    static var location: String { Bundle.main.bundleURL.path }
}
