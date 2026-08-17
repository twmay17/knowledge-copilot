import CryptoKit
import Foundation

public struct KnowledgeSpreadsheetIngestionWarning: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let code: String
  public let locator: KnowledgeSourceLocator
  public let message: String

  public init(id: String, code: String, locator: KnowledgeSourceLocator, message: String) {
    self.id = id
    self.code = code
    self.locator = locator
    self.message = message
  }
}

public struct KnowledgeSpreadsheetIngestionResult: Codable, Equatable, Sendable {
  public let source: KnowledgeSource
  public let passages: [KnowledgePassage]
  public let warnings: [KnowledgeSpreadsheetIngestionWarning]

  public init(
    source: KnowledgeSource,
    passages: [KnowledgePassage],
    warnings: [KnowledgeSpreadsheetIngestionWarning]
  ) {
    self.source = source
    self.passages = passages
    self.warnings = warnings
  }

  public func resolvesToSource(_ passage: KnowledgePassage) -> Bool {
    passages.contains(passage) && passage.sourceID == source.id
      && passage.locator.contentSHA256 == Self.sha256(Data(passage.text.utf8))
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

public enum KnowledgeSpreadsheetIngestionError: Error, CustomStringConvertible {
  case unsupportedFormat(String)
  case unsafeRelativePath(String)
  case unreadableSpreadsheet(String, Error)
  case invalidCSV(String)
  case invalidXLSX(String)
  case archiveExtractionFailed(String)

  public var description: String {
    switch self {
    case .unsupportedFormat(let path):
      return "Unsupported spreadsheet format for '\(path)'; expected an XLSX or CSV file."
    case .unsafeRelativePath(let path):
      return "Spreadsheet relative path '\(path)' is unsafe."
    case .unreadableSpreadsheet(let path, let error):
      return "Spreadsheet '\(path)' could not be read: \(error.localizedDescription)"
    case .invalidCSV(let detail):
      return "CSV could not be parsed: \(detail)"
    case .invalidXLSX(let detail):
      return "XLSX could not be parsed: \(detail)"
    case .archiveExtractionFailed(let detail):
      return "XLSX archive extraction failed: \(detail)"
    }
  }
}

public struct KnowledgeSpreadsheetIngestor: Sendable {
  public init() {}

  public func ingest(
    fileAt fileURL: URL,
    relativePath: String,
    title: String? = nil,
    importedAt: Date = Date()
  ) throws -> KnowledgeSpreadsheetIngestionResult {
    guard Self.isSafeRelativePath(relativePath) else {
      throw KnowledgeSpreadsheetIngestionError.unsafeRelativePath(relativePath)
    }
    let sourceData: Data
    do {
      sourceData = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
    } catch {
      throw KnowledgeSpreadsheetIngestionError.unreadableSpreadsheet(fileURL.path, error)
    }

    let sourceHash = Self.sha256(sourceData)
    let source = KnowledgeSource(
      id: "source-\(sourceHash.prefix(24))",
      kind: .spreadsheet,
      title: title ?? fileURL.deletingPathExtension().lastPathComponent,
      relativePath: relativePath,
      sha256: sourceHash,
      importedAt: importedAt
    )

    let extracted: ExtractedSpreadsheet
    switch fileURL.pathExtension.lowercased() {
    case "csv":
      extracted = try extractCSV(sourceData)
    case "xlsx":
      extracted = try extractXLSX(fileURL)
    default:
      throw KnowledgeSpreadsheetIngestionError.unsupportedFormat(fileURL.path)
    }

    var warnings = extracted.warnings
    let passages = extracted.rows.map { row in
      let text = Self.canonicalText(for: row)
      let contentHash = Self.sha256(Data(text.utf8))
      let locator = KnowledgeSourceLocator(
        sheet: row.sheet,
        cellRange: Self.cellRange(for: row.cells),
        rowStart: row.rowNumber,
        rowEnd: row.rowNumber,
        contentSHA256: contentHash
      )
      let identity = [
        sourceHash,
        row.sheet ?? "csv",
        String(row.rowNumber),
        locator.cellRange ?? "",
        contentHash,
      ].joined(separator: "|")
      return KnowledgePassage(
        id: "passage-\(Self.sha256(Data(identity.utf8)).prefix(24))",
        sourceID: source.id,
        text: text,
        locator: locator,
        spreadsheet: KnowledgeSpreadsheetPassage(
          cells: row.cells,
          period: row.period,
          unit: row.unit,
          isHeaderRow: row.isHeaderRow
        )
      )
    }

    let locatorsByKey = Dictionary(
      uniqueKeysWithValues: passages.map {
        (Self.locatorKey(sheet: $0.locator.sheet, row: $0.locator.rowStart), $0.locator)
      })
    warnings = warnings.map { warning in
      let key = Self.locatorKey(sheet: warning.locator.sheet, row: warning.locator.rowStart)
      guard let locator = locatorsByKey[key] else { return warning }
      return KnowledgeSpreadsheetIngestionWarning(
        id: warning.id,
        code: warning.code,
        locator: locator,
        message: warning.message
      )
    }

    return KnowledgeSpreadsheetIngestionResult(
      source: source,
      passages: passages,
      warnings: warnings
    )
  }

  private func extractCSV(_ data: Data) throws -> ExtractedSpreadsheet {
    guard var text = String(data: data, encoding: .utf8) else {
      throw KnowledgeSpreadsheetIngestionError.invalidCSV("file is not valid UTF-8")
    }
    if text.first == "\u{FEFF}" {
      text.removeFirst()
    }
    let records = try CSVRecordParser.parse(text)
    guard
      let headerOffset = records.firstIndex(where: {
        !$0.allSatisfy({ $0.isEmpty }) && !Self.isCSVCommentRecord($0)
      })
    else {
      throw KnowledgeSpreadsheetIngestionError.invalidCSV("header row is missing")
    }
    let headerRecord = records[headerOffset]

    let headers = headerRecord.enumerated().reduce(into: [Int: String]()) { result, item in
      let header = item.element.trimmingCharacters(in: .whitespacesAndNewlines)
      if !header.isEmpty { result[item.offset + 1] = header }
    }
    let expectedColumnCount = headerRecord.count
    var rows: [ExtractedRow] = []
    var warnings: [KnowledgeSpreadsheetIngestionWarning] = []

    for (offset, record) in records.enumerated() where !record.allSatisfy({ $0.isEmpty }) {
      let rowNumber = offset + 1
      let isComment = Self.isCSVCommentRecord(record)
      if !isComment, record.count != expectedColumnCount {
        let locator = KnowledgeSourceLocator(rowStart: rowNumber, rowEnd: rowNumber)
        warnings.append(
          KnowledgeSpreadsheetIngestionWarning(
            id: "csv-row-\(rowNumber)-column-count",
            code: "csv_inconsistent_columns",
            locator: locator,
            message:
              "CSV row \(rowNumber) has \(record.count) columns; the header has \(expectedColumnCount)."
          ))
      }

      let cells = record.enumerated().map { columnOffset, value in
        let reference = Self.columnName(columnOffset + 1) + String(rowNumber)
        return KnowledgeSpreadsheetCell(
          reference: reference,
          header: offset == headerOffset || isComment ? nil : headers[columnOffset + 1],
          value: value.isEmpty ? nil : value,
          valueType: Self.csvValueType(value)
        )
      }
      rows.append(
        Self.makeExtractedRow(
          sheet: nil,
          rowNumber: rowNumber,
          cells: cells,
          headers: isComment ? [:] : headers,
          isHeaderRow: offset == headerOffset
        ))
    }
    return ExtractedSpreadsheet(rows: rows, warnings: warnings)
  }

  private func extractXLSX(_ fileURL: URL) throws -> ExtractedSpreadsheet {
    let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "knowledge-xlsx-\(UUID().uuidString)", isDirectory: true)
    do {
      try FileManager.default.createDirectory(
        at: temporaryDirectory,
        withIntermediateDirectories: true
      )
    } catch {
      throw KnowledgeSpreadsheetIngestionError.archiveExtractionFailed(error.localizedDescription)
    }
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    try Self.extractArchive(fileURL, to: temporaryDirectory)
    let xlDirectory = temporaryDirectory.appendingPathComponent("xl", isDirectory: true)
    let workbookURL = xlDirectory.appendingPathComponent("workbook.xml")
    let relationshipsURL = xlDirectory.appendingPathComponent("_rels/workbook.xml.rels")
    guard FileManager.default.fileExists(atPath: workbookURL.path),
      FileManager.default.fileExists(atPath: relationshipsURL.path)
    else {
      throw KnowledgeSpreadsheetIngestionError.invalidXLSX(
        "xl/workbook.xml or its relationships file is missing")
    }

    let sheets = try Self.parseXML(workbookURL, delegate: WorkbookSheetParser())
    let relationships = try Self.parseXML(relationshipsURL, delegate: RelationshipParser())
    let sharedStringsURL = xlDirectory.appendingPathComponent("sharedStrings.xml")
    let sharedStrings =
      FileManager.default.fileExists(atPath: sharedStringsURL.path)
      ? try Self.parseXML(sharedStringsURL, delegate: SharedStringsParser()) : []
    let stylesURL = xlDirectory.appendingPathComponent("styles.xml")
    let numberFormats =
      FileManager.default.fileExists(atPath: stylesURL.path)
      ? try Self.parseXML(stylesURL, delegate: StylesParser()) : []

    var rows: [ExtractedRow] = []
    var warnings: [KnowledgeSpreadsheetIngestionWarning] = []
    for sheet in sheets {
      guard let target = relationships[sheet.relationshipID] else {
        throw KnowledgeSpreadsheetIngestionError.invalidXLSX(
          "sheet '\(sheet.name)' has no workbook relationship")
      }
      guard let sheetURL = Self.relationshipTargetURL(target, under: xlDirectory) else {
        throw KnowledgeSpreadsheetIngestionError.invalidXLSX(
          "worksheet relationship for '\(sheet.name)' escapes the extracted archive")
      }
      guard FileManager.default.fileExists(atPath: sheetURL.path) else {
        throw KnowledgeSpreadsheetIngestionError.invalidXLSX(
          "worksheet for '\(sheet.name)' is missing")
      }
      let parsedRows = try Self.parseXML(
        sheetURL,
        delegate: WorksheetParser(
          sharedStrings: sharedStrings,
          numberFormats: numberFormats
        ))
      guard let firstRow = parsedRows.first else { continue }
      let headers = firstRow.cells.reduce(into: [Int: String]()) { result, cell in
        if let value = cell.value, !value.isEmpty {
          result[Self.columnIndex(from: cell.reference)] = value
        }
      }
      for parsed in parsedRows {
        let cells = parsed.cells.map { cell in
          KnowledgeSpreadsheetCell(
            reference: cell.reference,
            header: parsed.rowNumber == firstRow.rowNumber
              ? nil : headers[Self.columnIndex(from: cell.reference)],
            value: cell.value,
            valueType: cell.valueType,
            formula: cell.formula,
            numberFormat: cell.numberFormat
          )
        }
        rows.append(
          Self.makeExtractedRow(
            sheet: sheet.name,
            rowNumber: parsed.rowNumber,
            cells: cells,
            headers: headers,
            isHeaderRow: parsed.rowNumber == firstRow.rowNumber
          ))
        for cell in cells where cell.formula != nil && cell.value == nil {
          let locator = KnowledgeSourceLocator(
            sheet: sheet.name,
            cellRange: cell.reference,
            rowStart: parsed.rowNumber,
            rowEnd: parsed.rowNumber
          )
          warnings.append(
            KnowledgeSpreadsheetIngestionWarning(
              id: "xlsx-\(sheet.name)-\(cell.reference)-missing-value",
              code: "xlsx_formula_missing_cached_value",
              locator: locator,
              message:
                "Formula cell \(sheet.name)!\(cell.reference) has no cached value and requires recalculation."
            ))
        }
      }
    }
    guard !rows.isEmpty else {
      throw KnowledgeSpreadsheetIngestionError.invalidXLSX(
        "workbook contains no extractable rows")
    }
    return ExtractedSpreadsheet(rows: rows, warnings: warnings)
  }

  private static func makeExtractedRow(
    sheet: String?,
    rowNumber: Int,
    cells: [KnowledgeSpreadsheetCell],
    headers: [Int: String],
    isHeaderRow: Bool
  ) -> ExtractedRow {
    let period = contextualValue(
      in: cells,
      headers: headers,
      matching: ["period", "year", "date", "as of", "as_of"]
    )
    let unit = contextualValue(
      in: cells,
      headers: headers,
      matching: ["unit", "units", "currency"]
    )
    return ExtractedRow(
      sheet: sheet,
      rowNumber: rowNumber,
      cells: cells,
      period: isHeaderRow ? nil : period,
      unit: isHeaderRow ? nil : unit,
      isHeaderRow: isHeaderRow
    )
  }

  private static func contextualValue(
    in cells: [KnowledgeSpreadsheetCell],
    headers: [Int: String],
    matching candidates: Set<String>
  ) -> String? {
    for cell in cells {
      let column = columnIndex(from: cell.reference)
      guard
        let header = headers[column]?.lowercased().trimmingCharacters(
          in: .whitespacesAndNewlines), candidates.contains(header)
      else {
        continue
      }
      return cell.value
    }
    return nil
  }

  private static func canonicalText(for row: ExtractedRow) -> String {
    let values = row.cells.map { cell in
      let label = cell.header ?? cell.reference
      let value = cell.value ?? ""
      if let formula = cell.formula {
        return "\(label)=\(value) [formula: \(formula)]"
      }
      return "\(label)=\(value)"
    }
    return values.joined(separator: "\t")
  }

  private static func cellRange(for cells: [KnowledgeSpreadsheetCell]) -> String? {
    guard let first = cells.first?.reference, let last = cells.last?.reference else { return nil }
    return first == last ? first : "\(first):\(last)"
  }

  private static func csvValueType(_ value: String) -> KnowledgeSpreadsheetCellValueType {
    if value.isEmpty { return .blank }
    if value.caseInsensitiveCompare("true") == .orderedSame
      || value.caseInsensitiveCompare("false") == .orderedSame
    {
      return .boolean
    }
    if Double(value) != nil { return .number }
    return .text
  }

  private static func isCSVCommentRecord(_ record: [String]) -> Bool {
    guard
      let first = record.first?.trimmingCharacters(in: .whitespacesAndNewlines),
      first.hasPrefix("#")
    else {
      return false
    }
    return record.dropFirst().allSatisfy {
      $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
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
      throw KnowledgeSpreadsheetIngestionError.archiveExtractionFailed(error.localizedDescription)
    }
    guard process.terminationStatus == 0 else {
      let data = standardError.fileHandleForReading.readDataToEndOfFile()
      let detail = String(data: data, encoding: .utf8)?.trimmingCharacters(
        in: .whitespacesAndNewlines)
      throw KnowledgeSpreadsheetIngestionError.archiveExtractionFailed(
        detail?.isEmpty == false ? detail! : "ditto exited with \(process.terminationStatus)")
    }
  }

  private static func parseXML<Delegate: NSObject & XMLParserDelegate>(
    _ url: URL,
    delegate: Delegate
  ) throws -> Delegate.Result where Delegate: XMLResultProviding {
    guard let parser = XMLParser(contentsOf: url) else {
      throw KnowledgeSpreadsheetIngestionError.invalidXLSX(
        "cannot open \(url.lastPathComponent)")
    }
    parser.delegate = delegate
    parser.shouldResolveExternalEntities = false
    guard parser.parse() else {
      throw KnowledgeSpreadsheetIngestionError.invalidXLSX(
        parser.parserError?.localizedDescription ?? "invalid XML in \(url.lastPathComponent)")
    }
    return delegate.result
  }

  /// Resolves a workbook relationship target inside the extraction root.
  /// Returns nil when the resolved path escapes the extracted archive — a
  /// crafted .rels must not read arbitrary local files into the pack.
  static func relationshipTargetURL(_ target: String, under xlDirectory: URL) -> URL? {
    let trimmed = target.hasPrefix("/") ? String(target.dropFirst()) : target
    let base = trimmed.hasPrefix("xl/") ? xlDirectory.deletingLastPathComponent() : xlDirectory
    let resolved = base.appendingPathComponent(trimmed).standardizedFileURL
    let root = xlDirectory.deletingLastPathComponent().standardizedFileURL
    guard resolved.path == root.path || resolved.path.hasPrefix(root.path + "/") else {
      return nil
    }
    return resolved
  }

  private static func locatorKey(sheet: String?, row: Int?) -> String {
    "\(sheet ?? "csv")|\(row ?? 0)"
  }

  private static func columnName(_ index: Int) -> String {
    var value = index
    var result = ""
    while value > 0 {
      value -= 1
      result.insert(Character(UnicodeScalar(65 + value % 26)!), at: result.startIndex)
      value /= 26
    }
    return result
  }

  private static func columnIndex(from reference: String) -> Int {
    reference.prefix(while: \.isLetter).reduce(0) { partial, character in
      partial * 26 + Int(character.asciiValue! - Character("A").asciiValue! + 1)
    }
  }

  private static func isSafeRelativePath(_ path: String) -> Bool {
    guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else { return false }
    return !path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private struct ExtractedSpreadsheet {
    let rows: [ExtractedRow]
    let warnings: [KnowledgeSpreadsheetIngestionWarning]
  }

  private struct ExtractedRow {
    let sheet: String?
    let rowNumber: Int
    let cells: [KnowledgeSpreadsheetCell]
    let period: String?
    let unit: String?
    let isHeaderRow: Bool
  }
}

private protocol XMLResultProviding {
  associatedtype Result
  var result: Result { get }
}

private struct WorkbookSheetDescriptor {
  let name: String
  let relationshipID: String
}

private final class WorkbookSheetParser: NSObject, XMLParserDelegate, XMLResultProviding {
  private var sheets: [WorkbookSheetDescriptor] = []
  var result: [WorkbookSheetDescriptor] { sheets }

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    guard localName(qName ?? elementName) == "sheet",
      let name = attributeValue("name", in: attributeDict),
      let relationshipID = attributeValue("id", in: attributeDict)
    else {
      return
    }
    sheets.append(WorkbookSheetDescriptor(name: name, relationshipID: relationshipID))
  }
}

private final class RelationshipParser: NSObject, XMLParserDelegate, XMLResultProviding {
  private var relationships: [String: String] = [:]
  var result: [String: String] { relationships }

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    guard localName(qName ?? elementName) == "Relationship",
      let id = attributeValue("Id", in: attributeDict),
      let target = attributeValue("Target", in: attributeDict)
    else {
      return
    }
    relationships[id] = target
  }
}

private final class SharedStringsParser: NSObject, XMLParserDelegate, XMLResultProviding {
  private var strings: [String] = []
  private var current = ""
  private var inItem = false
  private var inText = false
  var result: [String] { strings }

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    switch localName(qName ?? elementName) {
    case "si":
      current = ""
      inItem = true
    case "t" where inItem:
      inText = true
    default:
      break
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    if inText { current.append(string) }
  }

  func parser(
    _ parser: XMLParser,
    didEndElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    switch localName(qName ?? elementName) {
    case "t": inText = false
    case "si":
      strings.append(current)
      inItem = false
    default: break
    }
  }
}

private final class StylesParser: NSObject, XMLParserDelegate, XMLResultProviding {
  private static let builtInFormats: [Int: String] = [
    0: "General", 1: "0", 2: "0.00", 9: "0%", 10: "0.00%", 14: "mm-dd-yy",
    37: "#,##0;(#,##0)", 38: "#,##0;[Red](#,##0)", 39: "#,##0.00;(#,##0.00)",
    40: "#,##0.00;[Red](#,##0.00)",
  ]

  private var customFormats: [Int: String] = [:]
  private var formatsByStyle: [String?] = []
  private var inCellFormats = false
  var result: [String?] { formatsByStyle }

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    let name = localName(qName ?? elementName)
    if name == "numFmt", let idText = attributeValue("numFmtId", in: attributeDict),
      let id = Int(idText), let code = attributeValue("formatCode", in: attributeDict)
    {
      customFormats[id] = code
    } else if name == "cellXfs" {
      inCellFormats = true
    } else if name == "xf", inCellFormats,
      let idText = attributeValue("numFmtId", in: attributeDict), let id = Int(idText)
    {
      formatsByStyle.append(customFormats[id] ?? Self.builtInFormats[id])
    }
  }

  func parser(
    _ parser: XMLParser,
    didEndElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    if localName(qName ?? elementName) == "cellXfs" { inCellFormats = false }
  }
}

private struct ParsedWorksheetRow {
  let rowNumber: Int
  let cells: [ParsedWorksheetCell]
}

private struct ParsedWorksheetCell {
  let reference: String
  let value: String?
  let valueType: KnowledgeSpreadsheetCellValueType
  let formula: String?
  let numberFormat: String?
}

private final class WorksheetParser: NSObject, XMLParserDelegate, XMLResultProviding {
  private let sharedStrings: [String]
  private let numberFormats: [String?]
  private var rows: [ParsedWorksheetRow] = []
  private var currentRowNumber: Int?
  private var currentCells: [ParsedWorksheetCell] = []
  private var currentCell: CellState?
  private var capture: Capture?
  var result: [ParsedWorksheetRow] { rows }

  init(sharedStrings: [String], numberFormats: [String?]) {
    self.sharedStrings = sharedStrings
    self.numberFormats = numberFormats
  }

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    switch localName(qName ?? elementName) {
    case "row":
      currentRowNumber = attributeValue("r", in: attributeDict).flatMap(Int.init)
      currentCells = []
    case "c":
      guard let reference = attributeValue("r", in: attributeDict)?.uppercased() else { return }
      currentCell = CellState(
        reference: reference,
        type: attributeValue("t", in: attributeDict),
        styleIndex: attributeValue("s", in: attributeDict).flatMap(Int.init)
      )
    case "f" where currentCell != nil:
      capture = .formula
    case "v" where currentCell != nil:
      capture = .value
    case "t" where currentCell != nil:
      capture = .inlineText
    default:
      break
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    guard var cell = currentCell, let capture else { return }
    switch capture {
    case .formula: cell.formula.append(string)
    case .value: cell.value.append(string)
    case .inlineText: cell.inlineText.append(string)
    }
    currentCell = cell
  }

  func parser(
    _ parser: XMLParser,
    didEndElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    switch localName(qName ?? elementName) {
    case "f", "v", "t":
      capture = nil
    case "c":
      if let currentCell { currentCells.append(resolve(currentCell)) }
      currentCell = nil
      capture = nil
    case "row":
      if !currentCells.isEmpty {
        let inferred = currentCells.first.flatMap { rowNumber(from: $0.reference) }
        rows.append(
          ParsedWorksheetRow(
            rowNumber: currentRowNumber ?? inferred ?? (rows.count + 1),
            cells: currentCells.sorted {
              columnIndex(from: $0.reference) < columnIndex(from: $1.reference)
            }
          ))
      }
      currentRowNumber = nil
      currentCells = []
    default:
      break
    }
  }

  private func resolve(_ cell: CellState) -> ParsedWorksheetCell {
    let raw = cell.value.isEmpty ? nil : cell.value
    let formula =
      cell.formula.isEmpty
      ? nil : (cell.formula.hasPrefix("=") ? cell.formula : "=\(cell.formula)")
    let resolved: (String?, KnowledgeSpreadsheetCellValueType)
    switch cell.type {
    case "s":
      if let raw, let index = Int(raw), sharedStrings.indices.contains(index) {
        resolved = (sharedStrings[index], .text)
      } else {
        resolved = (raw, raw == nil ? .blank : .error)
      }
    case "inlineStr":
      resolved = (cell.inlineText.isEmpty ? nil : cell.inlineText, .text)
    case "b":
      resolved = (raw == "1" ? "true" : raw == nil ? nil : "false", raw == nil ? .blank : .boolean)
    case "e": resolved = (raw, .error)
    case "str": resolved = (raw, raw == nil ? .blank : .text)
    default: resolved = (raw, raw == nil ? .blank : .number)
    }
    let numberFormat = cell.styleIndex.flatMap {
      numberFormats.indices.contains($0) ? numberFormats[$0] : nil
    }
    return ParsedWorksheetCell(
      reference: cell.reference,
      value: resolved.0,
      valueType: resolved.1,
      formula: formula,
      numberFormat: numberFormat
    )
  }

  private func rowNumber(from reference: String) -> Int? {
    Int(reference.drop(while: \.isLetter))
  }

  private func columnIndex(from reference: String) -> Int {
    reference.prefix(while: \.isLetter).reduce(0) { partial, character in
      partial * 26 + Int(character.asciiValue! - Character("A").asciiValue! + 1)
    }
  }

  private enum Capture {
    case formula
    case inlineText
    case value
  }

  private struct CellState {
    let reference: String
    let type: String?
    let styleIndex: Int?
    var formula = ""
    var value = ""
    var inlineText = ""
  }
}

private enum CSVRecordParser {
  static func parse(_ text: String) throws -> [[String]] {
    let normalizedText =
      text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    var records: [[String]] = []
    var record: [String] = []
    var field = ""
    var isQuoted = false
    var index = normalizedText.startIndex

    while index < normalizedText.endIndex {
      let character = normalizedText[index]
      let next = normalizedText.index(after: index)
      if isQuoted {
        if character == "\"" {
          if next < normalizedText.endIndex, normalizedText[next] == "\"" {
            field.append("\"")
            index = normalizedText.index(after: next)
            continue
          }
          isQuoted = false
        } else {
          field.append(character)
        }
      } else {
        switch character {
        case "\"" where field.isEmpty:
          isQuoted = true
        case ",":
          record.append(field)
          field = ""
        case "\n":
          record.append(field.trimmingSuffix("\r"))
          records.append(record)
          record = []
          field = ""
        default:
          field.append(character)
        }
      }
      index = next
    }
    guard !isQuoted else {
      throw KnowledgeSpreadsheetIngestionError.invalidCSV("unterminated quoted field")
    }
    if !field.isEmpty || !record.isEmpty {
      record.append(field.trimmingSuffix("\r"))
      records.append(record)
    }
    return records
  }
}

private func localName(_ qualifiedName: String) -> String {
  qualifiedName.split(separator: ":").last.map(String.init) ?? qualifiedName
}

private func attributeValue(_ name: String, in attributes: [String: String]) -> String? {
  attributes.first { localName($0.key) == name }?.value
}

extension String {
  fileprivate func trimmingSuffix(_ suffix: Character) -> String {
    last == suffix ? String(dropLast()) : self
  }
}
