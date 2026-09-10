import Foundation

struct WhiteboardSessionArchive: Codable, Sendable {
  let schemaVersion: Int
  let sessionID: String
  let startedAt: Date
  var notes: [SidecastWhiteboardModel.DisplayNote]
}

enum WhiteboardArchiveError: Error {
  case invalidSession
  case invalidArchive
}
