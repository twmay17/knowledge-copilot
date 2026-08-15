import Foundation

public enum KnowledgePackSchema {
  public static let currentVersion = 1
}

public struct KnowledgePack: Equatable, Sendable {
  public let manifest: KnowledgePackManifest
  public let sources: [KnowledgeSource]
  public let passages: [KnowledgePassage]
  public let assertions: [KnowledgeAssertion]
  public let evidenceLinks: [KnowledgeEvidenceLink]
  public let calculations: [KnowledgeCalculation]
  public let responseCards: [KnowledgeResponseCard]
  public let questionFamilies: [KnowledgeQuestionFamily]

  public init(
    manifest: KnowledgePackManifest,
    sources: [KnowledgeSource],
    passages: [KnowledgePassage],
    assertions: [KnowledgeAssertion],
    evidenceLinks: [KnowledgeEvidenceLink],
    calculations: [KnowledgeCalculation],
    responseCards: [KnowledgeResponseCard],
    questionFamilies: [KnowledgeQuestionFamily]
  ) {
    self.manifest = manifest
    self.sources = sources
    self.passages = passages
    self.assertions = assertions
    self.evidenceLinks = evidenceLinks
    self.calculations = calculations
    self.responseCards = responseCards
    self.questionFamilies = questionFamilies
  }
}

public struct KnowledgePackManifest: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let packID: String
  public let title: String
  public let createdAt: Date
  public let defaultLocale: String
  public let domainProfiles: [DomainProfileReference]

  public init(
    schemaVersion: Int,
    packID: String,
    title: String,
    createdAt: Date,
    defaultLocale: String,
    domainProfiles: [DomainProfileReference]
  ) {
    self.schemaVersion = schemaVersion
    self.packID = packID
    self.title = title
    self.createdAt = createdAt
    self.defaultLocale = defaultLocale
    self.domainProfiles = domainProfiles
  }
}

public struct DomainProfileReference: Codable, Equatable, Sendable {
  public let id: String
  public let version: String

  public init(id: String, version: String) {
    self.id = id
    self.version = version
  }
}

public enum KnowledgeSourceKind: String, Codable, Equatable, Sendable {
  case document
  case spreadsheet
  case presentation
  case note
  case structuredData = "structured_data"
  case transcript
  case other
}

public struct KnowledgeSource: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let kind: KnowledgeSourceKind
  public let title: String
  public let relativePath: String
  public let sha256: String
  public let importedAt: Date

  public init(
    id: String,
    kind: KnowledgeSourceKind,
    title: String,
    relativePath: String,
    sha256: String,
    importedAt: Date
  ) {
    self.id = id
    self.kind = kind
    self.title = title
    self.relativePath = relativePath
    self.sha256 = sha256
    self.importedAt = importedAt
  }
}

public struct KnowledgeSourceLocator: Codable, Equatable, Sendable {
  public let page: Int?
  public let table: Int?
  public let block: Int?
  public let sheet: String?
  public let cellRange: String?
  public let sectionPath: [String]
  public let rowStart: Int?
  public let rowEnd: Int?
  public let contentSHA256: String?

  public init(
    page: Int? = nil,
    table: Int? = nil,
    block: Int? = nil,
    sheet: String? = nil,
    cellRange: String? = nil,
    sectionPath: [String] = [],
    rowStart: Int? = nil,
    rowEnd: Int? = nil,
    contentSHA256: String? = nil
  ) {
    self.page = page
    self.table = table
    self.block = block
    self.sheet = sheet
    self.cellRange = cellRange
    self.sectionPath = sectionPath
    self.rowStart = rowStart
    self.rowEnd = rowEnd
    self.contentSHA256 = contentSHA256
  }
}

public enum KnowledgeExtractionMethod: String, Codable, Equatable, Sendable {
  case pdfTextLayer = "pdf_text_layer"
  case docxXML = "docx_xml"
}

public enum KnowledgeExtractionQuality: String, Codable, Equatable, Sendable {
  case high
  case low
}

public enum KnowledgeExtractionQualityFlag: String, Codable, Equatable, Sendable {
  case lowQualityOCR = "low_quality_ocr"
  case noExtractableText = "no_extractable_text"
}

public struct KnowledgePassageExtraction: Codable, Equatable, Sendable {
  public let method: KnowledgeExtractionMethod
  public let quality: KnowledgeExtractionQuality
  public let confidence: Double?
  public let flags: [KnowledgeExtractionQualityFlag]

  public init(
    method: KnowledgeExtractionMethod,
    quality: KnowledgeExtractionQuality,
    confidence: Double? = nil,
    flags: [KnowledgeExtractionQualityFlag] = []
  ) {
    self.method = method
    self.quality = quality
    self.confidence = confidence
    self.flags = flags
  }
}

public enum KnowledgeSpreadsheetCellValueType: String, Codable, Equatable, Sendable {
  case blank
  case boolean
  case error
  case number
  case text
}

public struct KnowledgeSpreadsheetCell: Codable, Equatable, Sendable {
  public let reference: String
  public let header: String?
  public let value: String?
  public let valueType: KnowledgeSpreadsheetCellValueType
  public let formula: String?
  public let numberFormat: String?

  public init(
    reference: String,
    header: String? = nil,
    value: String? = nil,
    valueType: KnowledgeSpreadsheetCellValueType,
    formula: String? = nil,
    numberFormat: String? = nil
  ) {
    self.reference = reference
    self.header = header
    self.value = value
    self.valueType = valueType
    self.formula = formula
    self.numberFormat = numberFormat
  }
}

public struct KnowledgeSpreadsheetPassage: Codable, Equatable, Sendable {
  public let cells: [KnowledgeSpreadsheetCell]
  public let period: String?
  public let unit: String?
  public let isHeaderRow: Bool

  public init(
    cells: [KnowledgeSpreadsheetCell],
    period: String? = nil,
    unit: String? = nil,
    isHeaderRow: Bool = false
  ) {
    self.cells = cells
    self.period = period
    self.unit = unit
    self.isHeaderRow = isHeaderRow
  }
}

public struct KnowledgePassage: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let sourceID: String
  public let text: String
  public let locator: KnowledgeSourceLocator
  public let extraction: KnowledgePassageExtraction?
  public let spreadsheet: KnowledgeSpreadsheetPassage?

  public init(
    id: String,
    sourceID: String,
    text: String,
    locator: KnowledgeSourceLocator,
    extraction: KnowledgePassageExtraction? = nil,
    spreadsheet: KnowledgeSpreadsheetPassage? = nil
  ) {
    self.id = id
    self.sourceID = sourceID
    self.text = text
    self.locator = locator
    self.extraction = extraction
    self.spreadsheet = spreadsheet
  }
}

public enum KnowledgeValueType: String, Codable, Equatable, Sendable {
  case text
  case number
  case boolean
  case date
  case reference
}

public struct KnowledgeValue: Codable, Equatable, Sendable {
  public let type: KnowledgeValueType
  public let text: String?
  public let number: Double?
  public let boolean: Bool?
  public let date: String?
  public let referenceID: String?
  public let unit: String?
  public let scale: Double?

  public init(
    type: KnowledgeValueType,
    text: String? = nil,
    number: Double? = nil,
    boolean: Bool? = nil,
    date: String? = nil,
    referenceID: String? = nil,
    unit: String? = nil,
    scale: Double? = nil
  ) {
    self.type = type
    self.text = text
    self.number = number
    self.boolean = boolean
    self.date = date
    self.referenceID = referenceID
    self.unit = unit
    self.scale = scale
  }
}

public enum KnowledgeAssertionKind: String, Codable, Equatable, Sendable {
  case stated
  case calculated
  case inferred
  case interpretive
}

public struct KnowledgeAssertionContext: Codable, Equatable, Sendable {
  public static let reservedQualifierKeys: Set<String> = ["period", "version", "scope"]

  public let period: String?
  public let version: String?
  public let scope: String?
  public let additionalQualifiers: [String: String]

  public init(
    period: String? = nil,
    version: String? = nil,
    scope: String? = nil,
    additionalQualifiers: [String: String] = [:]
  ) {
    self.period = period
    self.version = version
    self.scope = scope
    self.additionalQualifiers = additionalQualifiers
  }

  public init(qualifiers: [String: String]) {
    period = qualifiers["period"]
    version = qualifiers["version"]
    scope = qualifiers["scope"]
    additionalQualifiers = qualifiers.filter {
      !Self.reservedQualifierKeys.contains($0.key)
    }
  }

  public var qualifiers: [String: String] {
    var result = additionalQualifiers
    if let period { result["period"] = period }
    if let version { result["version"] = version }
    if let scope { result["scope"] = scope }
    return result
  }
}

public struct KnowledgeAssertion: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let subject: String
  public let predicate: String
  public let value: KnowledgeValue
  public let qualifiers: [String: String]
  public let kind: KnowledgeAssertionKind
  public let confidence: Double
  public let evidenceLinkIDs: [String]

  public init(
    id: String,
    subject: String,
    predicate: String,
    value: KnowledgeValue,
    qualifiers: [String: String] = [:],
    kind: KnowledgeAssertionKind,
    confidence: Double,
    evidenceLinkIDs: [String]
  ) {
    self.id = id
    self.subject = subject
    self.predicate = predicate
    self.value = value
    self.qualifiers = qualifiers
    self.kind = kind
    self.confidence = confidence
    self.evidenceLinkIDs = evidenceLinkIDs
  }

  public var context: KnowledgeAssertionContext {
    KnowledgeAssertionContext(qualifiers: qualifiers)
  }
}

public enum KnowledgeEvidenceRelation: String, Codable, Equatable, Sendable {
  case supports
  case contradicts
  case derives
  case contextualizes
}

public struct KnowledgeEvidenceLink: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let assertionID: String
  public let passageID: String
  public let relation: KnowledgeEvidenceRelation
  public let note: String?

  public init(
    id: String,
    assertionID: String,
    passageID: String,
    relation: KnowledgeEvidenceRelation,
    note: String? = nil
  ) {
    self.id = id
    self.assertionID = assertionID
    self.passageID = passageID
    self.relation = relation
    self.note = note
  }
}

public struct KnowledgeCalculation: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let name: String
  public let version: String
  public let expression: String
  public let inputAssertionIDs: [String]
  public let outputAssertionID: String

  public init(
    id: String,
    name: String,
    version: String,
    expression: String,
    inputAssertionIDs: [String],
    outputAssertionID: String
  ) {
    self.id = id
    self.name = name
    self.version = version
    self.expression = expression
    self.inputAssertionIDs = inputAssertionIDs
    self.outputAssertionID = outputAssertionID
  }
}

public enum KnowledgeEvidenceState: String, Codable, CaseIterable, Equatable, Sendable {
  case directlySourced = "directly_sourced"
  case calculated
  case supportedByCorpus = "supported_by_corpus"
  case contradictedByCorpus = "contradicted_by_corpus"
  case contested
  case interpretive
  case notFoundInCorpus = "not_found_in_corpus"
  case needsClarification = "needs_clarification"
}

public enum KnowledgeReviewStatus: String, Codable, Equatable, Sendable {
  case generated
  case reviewed
  case rejected
}

public struct KnowledgeResponseCard: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let title: String
  public let answer: String
  public let evidenceState: KnowledgeEvidenceState
  public let questionFamilyIDs: [String]
  public let assertionIDs: [String]
  public let citationPassageIDs: [String]
  public let calculationIDs: [String]
  public let reviewStatus: KnowledgeReviewStatus

  public init(
    id: String,
    title: String,
    answer: String,
    evidenceState: KnowledgeEvidenceState,
    questionFamilyIDs: [String],
    assertionIDs: [String],
    citationPassageIDs: [String],
    calculationIDs: [String] = [],
    reviewStatus: KnowledgeReviewStatus
  ) {
    self.id = id
    self.title = title
    self.answer = answer
    self.evidenceState = evidenceState
    self.questionFamilyIDs = questionFamilyIDs
    self.assertionIDs = assertionIDs
    self.citationPassageIDs = citationPassageIDs
    self.calculationIDs = calculationIDs
    self.reviewStatus = reviewStatus
  }
}

public struct KnowledgeQuestionFamily: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let canonicalQuestion: String
  public let variants: [String]
  public let partialPrefixes: [String]
  public let aliases: [String]
  public let tags: [String]

  public init(
    id: String,
    canonicalQuestion: String,
    variants: [String],
    partialPrefixes: [String] = [],
    aliases: [String] = [],
    tags: [String] = []
  ) {
    self.id = id
    self.canonicalQuestion = canonicalQuestion
    self.variants = variants
    self.partialPrefixes = partialPrefixes
    self.aliases = aliases
    self.tags = tags
  }
}
