import CryptoKit
import Foundation
import PDFKit

public struct KnowledgeDocumentIngestionWarning: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let flag: KnowledgeExtractionQualityFlag
  public let locator: KnowledgeSourceLocator
  public let message: String

  public init(
    id: String,
    flag: KnowledgeExtractionQualityFlag,
    locator: KnowledgeSourceLocator,
    message: String
  ) {
    self.id = id
    self.flag = flag
    self.locator = locator
    self.message = message
  }
}

public struct KnowledgeDocumentIngestionResult: Codable, Equatable, Sendable {
  public let source: KnowledgeSource
  public let passages: [KnowledgePassage]
  public let warnings: [KnowledgeDocumentIngestionWarning]

  public init(
    source: KnowledgeSource,
    passages: [KnowledgePassage],
    warnings: [KnowledgeDocumentIngestionWarning]
  ) {
    self.source = source
    self.passages = passages
    self.warnings = warnings
  }

  public func source(for passage: KnowledgePassage) -> KnowledgeSource? {
    passages.contains(passage) && passage.sourceID == source.id ? source : nil
  }

  public func resolvesToSource(_ passage: KnowledgePassage) -> Bool {
    guard source(for: passage) != nil,
      passage.locator.contentSHA256 == Self.sha256(Data(passage.text.utf8))
    else {
      return false
    }
    return true
  }

  public var allPassagesResolveToSource: Bool {
    !passages.isEmpty && passages.allSatisfy(resolvesToSource)
  }

  public func resolvedSourceURL(
    for passage: KnowledgePassage,
    relativeTo rootDirectory: URL
  ) -> URL? {
    guard resolvesToSource(passage) else { return nil }
    let root = rootDirectory.standardizedFileURL.resolvingSymlinksInPath()
    let candidate =
      root
      .appendingPathComponent(source.relativePath)
      .standardizedFileURL
      .resolvingSymlinksInPath()
    guard candidate.path.hasPrefix(root.path + "/"),
      let data = try? Data(contentsOf: candidate, options: [.mappedIfSafe]),
      Self.sha256(data) == source.sha256
    else {
      return nil
    }
    return candidate
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

public enum KnowledgeDocumentIngestionError: Error, CustomStringConvertible {
  case unsupportedFormat(String)
  case unsafeRelativePath(String)
  case unreadableDocument(String, Error)
  case invalidPDF(String)
  case invalidDOCX(String)
  case archiveExtractionFailed(String)

  public var description: String {
    switch self {
    case .unsupportedFormat(let path):
      return "Unsupported document format for '\(path)'; expected a PDF or DOCX file."
    case .unsafeRelativePath(let path):
      return "Document relative path '\(path)' is unsafe."
    case .unreadableDocument(let path, let error):
      return "Document '\(path)' could not be read: \(error.localizedDescription)"
    case .invalidPDF(let path):
      return "Document '\(path)' is not a readable PDF."
    case .invalidDOCX(let detail):
      return "DOCX could not be parsed: \(detail)"
    case .archiveExtractionFailed(let detail):
      return "DOCX archive extraction failed: \(detail)"
    }
  }
}

public struct KnowledgeDocumentIngestor: Sendable {
  public init() {}

  public func ingest(
    fileAt fileURL: URL,
    relativePath: String,
    title: String? = nil,
    importedAt: Date = Date()
  ) throws -> KnowledgeDocumentIngestionResult {
    guard Self.isSafeRelativePath(relativePath) else {
      throw KnowledgeDocumentIngestionError.unsafeRelativePath(relativePath)
    }

    let sourceData: Data
    do {
      sourceData = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
    } catch {
      throw KnowledgeDocumentIngestionError.unreadableDocument(fileURL.path, error)
    }

    let sourceHash = Self.sha256(sourceData)
    let source = KnowledgeSource(
      id: "source-\(sourceHash.prefix(24))",
      kind: .document,
      title: title ?? fileURL.deletingPathExtension().lastPathComponent,
      relativePath: relativePath,
      sha256: sourceHash,
      importedAt: importedAt
    )

    let extraction: ExtractionResult
    switch fileURL.pathExtension.lowercased() {
    case "pdf":
      extraction = try extractPDF(fileURL)
    case "docx":
      extraction = try extractDOCX(fileURL)
    default:
      throw KnowledgeDocumentIngestionError.unsupportedFormat(fileURL.path)
    }

    var warnings = extraction.warnings
    let passages = extraction.blocks.enumerated().map { offset, block in
      let contentHash = Self.sha256(Data(block.text.utf8))
      let locator = KnowledgeSourceLocator(
        page: block.page,
        table: block.table,
        block: block.block,
        sectionPath: block.sectionPath,
        contentSHA256: contentHash
      )
      let identity = [
        sourceHash,
        block.page.map(String.init) ?? "",
        block.table.map(String.init) ?? "",
        block.block.map(String.init) ?? String(offset + 1),
        block.sectionPath.joined(separator: "/"),
        contentHash,
      ].joined(separator: "|")
      return KnowledgePassage(
        id: "passage-\(Self.sha256(Data(identity.utf8)).prefix(24))",
        sourceID: source.id,
        text: block.text,
        locator: locator,
        extraction: KnowledgePassageExtraction(
          method: block.method,
          quality: block.quality,
          flags: block.flags
        )
      )
    }

    let passageLocators = Dictionary(
      uniqueKeysWithValues: passages.compactMap { passage in
        passage.locator.block.map { ($0, passage) }
      })
    warnings = warnings.map { warning in
      guard let block = warning.locator.block, let passage = passageLocators[block] else {
        return warning
      }
      return KnowledgeDocumentIngestionWarning(
        id: warning.id,
        flag: warning.flag,
        locator: passage.locator,
        message: warning.message
      )
    }

    return KnowledgeDocumentIngestionResult(
      source: source,
      passages: passages,
      warnings: warnings
    )
  }

  private func extractPDF(_ fileURL: URL) throws -> ExtractionResult {
    guard let document = PDFDocument(url: fileURL) else {
      throw KnowledgeDocumentIngestionError.invalidPDF(fileURL.path)
    }

    var blocks: [ExtractedBlock] = []
    var warnings: [KnowledgeDocumentIngestionWarning] = []
    var blockNumber = 0

    for pageOffset in 0..<document.pageCount {
      let pageNumber = pageOffset + 1
      let text = Self.normalizedNarrativeText(document.page(at: pageOffset)?.string ?? "")
      guard !text.isEmpty else {
        let locator = KnowledgeSourceLocator(page: pageNumber)
        warnings.append(
          KnowledgeDocumentIngestionWarning(
            id: "pdf-page-\(pageNumber)-no-text",
            flag: .noExtractableText,
            locator: locator,
            message: "PDF page \(pageNumber) has no extractable text and requires OCR or review."
          ))
        continue
      }

      blockNumber += 1
      let isLowQuality = Self.looksLikeLowQualityOCR(text)
      let flags: [KnowledgeExtractionQualityFlag] = isLowQuality ? [.lowQualityOCR] : []
      let locator = KnowledgeSourceLocator(page: pageNumber, block: blockNumber)
      blocks.append(
        ExtractedBlock(
          text: text,
          page: pageNumber,
          table: nil,
          block: blockNumber,
          sectionPath: [],
          method: .pdfTextLayer,
          quality: isLowQuality ? .low : .high,
          flags: flags
        ))
      if isLowQuality {
        warnings.append(
          KnowledgeDocumentIngestionWarning(
            id: "pdf-page-\(pageNumber)-low-quality-ocr",
            flag: .lowQualityOCR,
            locator: locator,
            message: "PDF page \(pageNumber) has suspicious OCR-like text and must be reviewed."
          ))
      }
    }

    return ExtractionResult(blocks: blocks, warnings: warnings)
  }

  private func extractDOCX(_ fileURL: URL) throws -> ExtractionResult {
    let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "knowledge-docx-\(UUID().uuidString)", isDirectory: true)
    do {
      try FileManager.default.createDirectory(
        at: temporaryDirectory,
        withIntermediateDirectories: true
      )
    } catch {
      throw KnowledgeDocumentIngestionError.archiveExtractionFailed(error.localizedDescription)
    }
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    try Self.extractArchive(fileURL, to: temporaryDirectory)
    let documentXML = temporaryDirectory.appendingPathComponent("word/document.xml")
    guard FileManager.default.fileExists(atPath: documentXML.path) else {
      throw KnowledgeDocumentIngestionError.invalidDOCX("word/document.xml is missing")
    }

    let parser = XMLParser(contentsOf: documentXML)
    let delegate = DOCXDocumentParserDelegate()
    parser?.delegate = delegate
    parser?.shouldResolveExternalEntities = false
    guard parser?.parse() == true else {
      throw KnowledgeDocumentIngestionError.invalidDOCX(
        parser?.parserError?.localizedDescription ?? "document XML is invalid")
    }

    let blocks = delegate.blocks.map { block in
      ExtractedBlock(
        text: block.text,
        page: nil,
        table: block.table,
        block: block.block,
        sectionPath: block.sectionPath,
        method: .docxXML,
        quality: .high,
        flags: []
      )
    }
    guard !blocks.isEmpty else {
      throw KnowledgeDocumentIngestionError.invalidDOCX(
        "word/document.xml contains no narrative paragraphs or tables")
    }
    return ExtractionResult(blocks: blocks, warnings: [])
  }

  private static func extractArchive(_ archiveURL: URL, to destinationURL: URL) throws {
    let process = Process()
    let standardError = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = ["-x", "-k", archiveURL.path, destinationURL.path]
    process.standardError = standardError
    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      throw KnowledgeDocumentIngestionError.archiveExtractionFailed(error.localizedDescription)
    }
    guard process.terminationStatus == 0 else {
      let data = standardError.fileHandleForReading.readDataToEndOfFile()
      let detail = String(data: data, encoding: .utf8)?.trimmingCharacters(
        in: .whitespacesAndNewlines)
      throw KnowledgeDocumentIngestionError.archiveExtractionFailed(
        detail?.isEmpty == false ? detail! : "ditto exited with \(process.terminationStatus)")
    }
  }

  private static func looksLikeLowQualityOCR(_ text: String) -> Bool {
    let suspectGlyphs = CharacterSet(charactersIn: "�□■")
    let scalars = text.unicodeScalars
    if scalars.contains(where: { suspectGlyphs.contains($0) }) {
      return true
    }

    let visible = scalars.filter { !$0.properties.isWhitespace }
    guard visible.count >= 12 else { return true }
    let allowedPunctuation = CharacterSet(charactersIn: ".,;:!?$%&'\"()-/–—")
    let suspiciousToken = text.split(whereSeparator: \.isWhitespace).contains { token in
      let tokenScalars = token.unicodeScalars.filter { !$0.properties.isWhitespace }
      guard tokenScalars.count >= 5 else { return false }
      let suspectCount = tokenScalars.filter {
        !CharacterSet.alphanumerics.contains($0) && !allowedPunctuation.contains($0)
      }.count
      return suspectCount >= 2 && Double(suspectCount) / Double(tokenScalars.count) >= 0.2
    }
    if suspiciousToken {
      return true
    }
    let suspicious = visible.filter {
      !CharacterSet.alphanumerics.contains($0) && !allowedPunctuation.contains($0)
    }
    return Double(suspicious.count) / Double(visible.count) >= 0.12
  }

  private static func normalizedNarrativeText(_ value: String) -> String {
    value
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }

  private static func isSafeRelativePath(_ path: String) -> Bool {
    guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else { return false }
    return !path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private struct ExtractionResult {
    let blocks: [ExtractedBlock]
    let warnings: [KnowledgeDocumentIngestionWarning]
  }

  private struct ExtractedBlock {
    let text: String
    let page: Int?
    let table: Int?
    let block: Int?
    let sectionPath: [String]
    let method: KnowledgeExtractionMethod
    let quality: KnowledgeExtractionQuality
    let flags: [KnowledgeExtractionQualityFlag]
  }
}

private final class DOCXDocumentParserDelegate: NSObject, XMLParserDelegate {
  struct Block {
    let text: String
    let table: Int?
    let block: Int
    let sectionPath: [String]
  }

  private(set) var blocks: [Block] = []
  private var sectionPath: [String] = []
  private var blockNumber = 0
  private var tableNumber = 0
  private var tableDepth = 0
  private var currentTableRows: [[String]] = []
  private var currentRow: [String] = []
  private var currentCellParagraphs: [String] = []
  private var currentParagraph = ""
  private var currentParagraphStyle: String?
  private var isInsideParagraph = false
  private var isInsideText = false

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    switch localName(qName ?? elementName) {
    case "tbl":
      tableDepth += 1
      if tableDepth == 1 {
        tableNumber += 1
        currentTableRows = []
      }
    case "tr" where tableDepth == 1:
      currentRow = []
    case "tc" where tableDepth == 1:
      currentCellParagraphs = []
    case "p":
      currentParagraph = ""
      currentParagraphStyle = nil
      isInsideParagraph = true
    case "pStyle" where isInsideParagraph:
      currentParagraphStyle = attributeValue(named: "val", in: attributeDict)
    case "t" where isInsideParagraph:
      isInsideText = true
    case "tab" where isInsideParagraph:
      currentParagraph.append("\t")
    case "br" where isInsideParagraph:
      currentParagraph.append("\n")
    default:
      break
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    if isInsideText {
      currentParagraph.append(string)
    }
  }

  func parser(
    _ parser: XMLParser,
    didEndElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    switch localName(qName ?? elementName) {
    case "t":
      isInsideText = false
    case "p":
      finishParagraph()
    case "tc" where tableDepth == 1:
      currentRow.append(currentCellParagraphs.joined(separator: " "))
      currentCellParagraphs = []
    case "tr" where tableDepth == 1:
      if currentRow.contains(where: { !$0.isEmpty }) {
        currentTableRows.append(currentRow)
      }
      currentRow = []
    case "tbl":
      if tableDepth == 1 {
        finishTable()
      }
      tableDepth -= 1
    default:
      break
    }
  }

  private func finishParagraph() {
    let text = normalizedCellOrParagraph(currentParagraph)
    defer {
      currentParagraph = ""
      currentParagraphStyle = nil
      isInsideParagraph = false
      isInsideText = false
    }
    guard !text.isEmpty else { return }

    if tableDepth > 0 {
      currentCellParagraphs.append(text)
      return
    }
    if let headingLevel = headingLevel(for: currentParagraphStyle) {
      sectionPath = Array(sectionPath.prefix(headingLevel - 1))
      sectionPath.append(text)
      return
    }

    blockNumber += 1
    blocks.append(
      Block(text: text, table: nil, block: blockNumber, sectionPath: sectionPath))
  }

  private func finishTable() {
    let text = currentTableRows.map { $0.joined(separator: "\t") }.joined(separator: "\n")
    guard !text.isEmpty else { return }
    blockNumber += 1
    blocks.append(
      Block(text: text, table: tableNumber, block: blockNumber, sectionPath: sectionPath))
    currentTableRows = []
  }

  private func headingLevel(for style: String?) -> Int? {
    guard let style else { return nil }
    let normalized = style.lowercased().replacingOccurrences(of: " ", with: "")
    guard normalized.hasPrefix("heading") else { return nil }
    let suffix = normalized.dropFirst("heading".count)
    return Int(suffix).map { min(max($0, 1), 9) }
  }

  private func normalizedCellOrParagraph(_ value: String) -> String {
    value
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }

  private func localName(_ qualifiedName: String) -> String {
    qualifiedName.split(separator: ":").last.map(String.init) ?? qualifiedName
  }

  private func attributeValue(named name: String, in attributes: [String: String]) -> String? {
    attributes.first { localName($0.key) == name }?.value
  }
}
