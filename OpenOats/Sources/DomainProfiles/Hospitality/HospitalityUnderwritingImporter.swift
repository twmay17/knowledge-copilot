import CryptoKit
import Foundation
import OpenOatsKit

public enum HospitalityUnderwritingSourceRole: String, Codable, Equatable, Sendable, CaseIterable {
  case brokerSource = "broker_source"
  case analysisExtraction = "analysis_extraction"
  case analysisModel = "analysis_model"
  case analysisVerification = "analysis_verification"
  case analysisNarrative = "analysis_narrative"
}

public enum HospitalityUnderwritingDocumentType: String, Codable, Equatable, Sendable {
  case offeringMemorandum = "offering_memorandum"
  case profitAndLoss = "profit_and_loss"
  case strStar = "str_star"
  case costarMarketsMonthly = "costar_markets_monthly"
  case costarMarketsDaily = "costar_markets_daily"
  case costarSegmentation = "costar_segmentation"
  case costarAnalyticsMonthly = "costar_analytics_monthly"
  case costarAnalyticsDaily = "costar_analytics_daily"
  case costarHotelMixList = "costar_hotel_mix_list"
  case boe
  case pipMatrix = "pip_matrix"
  case marketMixList = "market_mix_list"
  case flagsRegister = "flags_register"
  case tieOut = "tie_out"
  case businessPlan = "business_plan"
  case fullModel = "full_model"
  case icMemo = "ic_memo"
  case centralQuestion = "central_question"
  case unknown
}

public enum HospitalityUnderwritingValueStage: String, Codable, Equatable, Sendable {
  case exactTranscription = "exact_transcription"
  case canonical
  case normalized
  case modeled
}

public struct HospitalityUnderwritingSourceLabels: Codable, Equatable, Sendable {
  public let role: HospitalityUnderwritingSourceRole
  public let documentType: HospitalityUnderwritingDocumentType
  public let valueStage: HospitalityUnderwritingValueStage

  public init(
    role: HospitalityUnderwritingSourceRole,
    documentType: HospitalityUnderwritingDocumentType,
    valueStage: HospitalityUnderwritingValueStage
  ) {
    self.role = role
    self.documentType = documentType
    self.valueStage = valueStage
  }
}

public struct HospitalityUnderwritingPathClassifier: Sendable {
  public init() {}

  public func labels(for relativePath: String) -> HospitalityUnderwritingSourceLabels {
    let path = relativePath.lowercased().replacingOccurrences(of: "\\", with: "/")
    let boundedPath = "/" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/"
    let filename = URL(fileURLWithPath: path).lastPathComponent
    let analysisPath = boundedPath.replacingOccurrences(
      of: "/jmi analysis/", with: "/deal analysis/")

    let role: HospitalityUnderwritingSourceRole
    if analysisPath.contains("/deal analysis/00 extraction csvs/") {
      role = .analysisExtraction
    } else if analysisPath.contains("/deal analysis/01 boe/")
      || analysisPath.contains("/deal analysis/06 full model/")
    {
      role = .analysisModel
    } else if analysisPath.contains("/deal analysis/04 flags & verification/") {
      role = .analysisVerification
    } else if analysisPath.contains("/deal analysis/") {
      role = .analysisNarrative
    } else {
      role = .brokerSource
    }

    let documentType: HospitalityUnderwritingDocumentType
    if filename == "central_question.md" {
      documentType = .centralQuestion
    } else if filename == "flags_register.md" {
      documentType = .flagsRegister
    } else if filename.contains("tieout") {
      documentType = .tieOut
    } else if filename.contains("properties_hotelmixlist") {
      documentType = .costarHotelMixList
    } else if filename.contains("markets_segmentation") {
      documentType = .costarSegmentation
    } else if filename.contains("markets_monthly") {
      documentType = .costarMarketsMonthly
    } else if filename.contains("markets_daily") {
      documentType = .costarMarketsDaily
    } else if filename.contains("analytics_monthly") {
      documentType = .costarAnalyticsMonthly
    } else if filename.contains("analytics_daily") {
      documentType = .costarAnalyticsDaily
    } else if filename.contains("star") || filename.contains("str_summary") {
      documentType = .strStar
    } else if filename.contains("_pl_") || filename.hasPrefix("pl_") {
      documentType = .profitAndLoss
    } else if filename.contains("pip_matrix") {
      documentType = .pipMatrix
    } else if filename.contains("mix list") || filename.contains("mix_list") {
      documentType = .marketMixList
    } else if filename.hasPrefix("boe -") || filename.contains("boe_") {
      documentType = .boe
    } else if boundedPath.contains("/06 full model/") || filename.contains("full im") {
      documentType = .fullModel
    } else if boundedPath.contains("/07 ic memo/") || filename.contains("ic memo") {
      documentType = .icMemo
    } else if boundedPath.contains("/05 business plan/") || filename.contains("business_plan") {
      documentType = .businessPlan
    } else if boundedPath.contains("/01 om/") || filename.contains("offering memorandum") {
      documentType = .offeringMemorandum
    } else {
      documentType = .unknown
    }

    let valueStage: HospitalityUnderwritingValueStage
    if role == .analysisModel {
      valueStage = .modeled
    } else if filename.contains("_canonical") {
      valueStage = .canonical
    } else if filename.contains("normalized") {
      valueStage = .normalized
    } else {
      valueStage = .exactTranscription
    }
    return HospitalityUnderwritingSourceLabels(
      role: role,
      documentType: documentType,
      valueStage: valueStage
    )
  }
}

public struct HospitalityUnderwritingImportWarning: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let code: String
  public let row: Int?
  public let message: String

  public init(id: String, code: String, row: Int?, message: String) {
    self.id = id
    self.code = code
    self.row = row
    self.message = message
  }
}

public struct HospitalityUnderwritingImportResult: Codable, Equatable, Sendable {
  public let profileID: String
  public let profileVersion: String
  public let labels: HospitalityUnderwritingSourceLabels
  public let provenance: [String: String]
  public let source: KnowledgeSource
  public let passages: [KnowledgePassage]
  public let assertions: [KnowledgeAssertion]
  public let evidenceLinks: [KnowledgeEvidenceLink]
  public let warnings: [HospitalityUnderwritingImportWarning]

  public init(
    profileID: String,
    profileVersion: String,
    labels: HospitalityUnderwritingSourceLabels,
    provenance: [String: String],
    source: KnowledgeSource,
    passages: [KnowledgePassage],
    assertions: [KnowledgeAssertion],
    evidenceLinks: [KnowledgeEvidenceLink],
    warnings: [HospitalityUnderwritingImportWarning]
  ) {
    self.profileID = profileID
    self.profileVersion = profileVersion
    self.labels = labels
    self.provenance = provenance
    self.source = source
    self.passages = passages
    self.assertions = assertions
    self.evidenceLinks = evidenceLinks
    self.warnings = warnings
  }
}

public enum HospitalityUnderwritingImportError: Error, CustomStringConvertible {
  case unsupportedCSVSchema
  case missingReportingPeriod(String)
  case invalidStatus(String)

  public var description: String {
    switch self {
    case .unsupportedCSVSchema:
      return "Unsupported underwriting CSV schema; expected the canonical P&L or STAR columns."
    case .missingReportingPeriod(let filename):
      return
        "No reporting period was supplied or inferable from '\(filename)'; pass --period using YYYY, YYYY-MM, TTM:YYYY-MM, or YTD:YYYY-MM."
    case .invalidStatus(let status):
      return "Invalid reporting status '\(status)'; expected actual, budget, or forecast."
    }
  }
}

public struct HospitalityUnderwritingCSVImporter: Sendable {
  public static let profileVersion = "0.2.0"

  private let classifier = HospitalityUnderwritingPathClassifier()
  private let spreadsheetIngestor = KnowledgeSpreadsheetIngestor()

  public init() {}

  public func ingest(
    fileAt fileURL: URL,
    relativePath: String,
    assetID: String,
    period: String? = nil,
    status: String? = nil,
    title: String? = nil,
    importedAt: Date = Date()
  ) throws -> HospitalityUnderwritingImportResult {
    let ingestion = try spreadsheetIngestor.ingest(
      fileAt: fileURL,
      relativePath: relativePath,
      title: title,
      importedAt: importedAt
    )
    let labels = classifier.labels(for: relativePath)
    let provenance = Self.provenance(from: ingestion.passages)
    let header = ingestion.passages.first { $0.spreadsheet?.isHeaderRow == true }
    let headerValues = Set(
      header?.spreadsheet?.cells.compactMap { $0.value?.lowercased() } ?? [])
    let requestedStatus = try Self.reportingStatus(
      explicit: status,
      filename: fileURL.lastPathComponent
    )

    let imported: ImportedRecords
    if ["section", "metric", "unit"].allSatisfy(headerValues.contains) {
      guard
        let reportingPeriod = period
          ?? Self.inferReportingPeriod(from: fileURL.deletingPathExtension().lastPathComponent)
      else {
        throw HospitalityUnderwritingImportError.missingReportingPeriod(fileURL.lastPathComponent)
      }
      imported = Self.importProfitAndLoss(
        ingestion,
        assetID: assetID,
        reportingPeriod: reportingPeriod,
        status: requestedStatus,
        labels: labels,
        headerRow: header?.locator.rowStart ?? 0
      )
    } else if ["period", "metric", "subject", "comp_set", "index", "basis"].allSatisfy(
      headerValues.contains)
    {
      imported = Self.importSTAR(
        ingestion,
        assetID: assetID,
        status: requestedStatus,
        labels: labels,
        headerRow: header?.locator.rowStart ?? 0
      )
    } else {
      throw HospitalityUnderwritingImportError.unsupportedCSVSchema
    }

    return HospitalityUnderwritingImportResult(
      profileID: "hospitality",
      profileVersion: Self.profileVersion,
      labels: labels,
      provenance: provenance,
      source: ingestion.source,
      passages: ingestion.passages,
      assertions: imported.assertions,
      evidenceLinks: imported.evidenceLinks,
      warnings: imported.warnings
    )
  }

  private static func importProfitAndLoss(
    _ ingestion: KnowledgeSpreadsheetIngestionResult,
    assetID: String,
    reportingPeriod: String,
    status: String,
    labels: HospitalityUnderwritingSourceLabels,
    headerRow: Int
  ) -> ImportedRecords {
    var records = ImportedRecords()
    for passage in ingestion.passages where (passage.locator.rowStart ?? 0) > headerRow {
      let fields = fieldsByHeader(passage)
      guard let section = fields["section"]?.lowercased(),
        let metric = fields["metric"]?.lowercased(),
        let sourceUnit = fields["unit"]?.lowercased()
      else {
        continue
      }
      let key = "\(section).\(metric)"
      guard let mapping = profitAndLossMappings[key] else {
        records.warn(
          code: "unmapped_metric",
          row: passage.locator.rowStart,
          message:
            "Controlled metric '\(key)' is retained as evidence but not promoted to an assertion."
        )
        continue
      }
      guard mapping.sourceUnits.contains(sourceUnit) else {
        records.warn(
          code: "unexpected_unit",
          row: passage.locator.rowStart,
          message:
            "Metric '\(key)' uses unit '\(sourceUnit)'; expected \(mapping.sourceUnits.sorted().joined(separator: ", "))."
        )
        continue
      }

      for cell in passage.spreadsheet?.cells ?? [] {
        guard let header = cell.header, let value = cell.value,
          let period = valuePeriod(column: header, reportingPeriod: reportingPeriod)
        else { continue }
        guard let parsed = parseNumber(value, normalizedUnit: mapping.normalizedUnit) else {
          records.warn(
            code: "invalid_numeric_value",
            row: passage.locator.rowStart,
            message: "Metric '\(key)' value '\(value)' in column '\(header)' is not numeric."
          )
          continue
        }
        records.addAssertion(
          sourceID: ingestion.source.id,
          passage: passage,
          assetID: assetID,
          predicate: mapping.predicate,
          number: parsed.number,
          unit: mapping.normalizedUnit,
          scale: parsed.scale,
          qualifiers: qualifiers(
            period: period,
            scope: mapping.scope,
            status: status,
            labels: labels,
            benchmark: "subject",
            comparisonBasis: "direct_asset"
          ),
          discriminator: header,
          note: fields["note"]
        )
      }
    }
    return records
  }

  private static func importSTAR(
    _ ingestion: KnowledgeSpreadsheetIngestionResult,
    assetID: String,
    status: String,
    labels: HospitalityUnderwritingSourceLabels,
    headerRow: Int
  ) -> ImportedRecords {
    var records = ImportedRecords()
    for passage in ingestion.passages where (passage.locator.rowStart ?? 0) > headerRow {
      let fields = fieldsByHeader(passage)
      guard let period = fields["period"], let metric = fields["metric"]?.lowercased(),
        let mapping = starMappings[metric]
      else {
        continue
      }
      let basis = fields["basis"]?.lowercased()
      let note = fields["note"]

      if let subject = fields["subject"],
        let parsed = parseNumber(subject, normalizedUnit: mapping.normalizedUnit)
      {
        records.addAssertion(
          sourceID: ingestion.source.id,
          passage: passage,
          assetID: assetID,
          predicate: mapping.predicate,
          number: parsed.number,
          unit: mapping.normalizedUnit,
          scale: parsed.scale,
          qualifiers: qualifiers(
            period: period,
            scope: "rooms",
            status: status,
            labels: labels,
            benchmark: "subject",
            comparisonBasis: "direct_asset"
          ),
          discriminator: "subject",
          note: note
        )
      }

      let comparison: (benchmark: String, basis: String)?
      if basis == "star_compset" {
        comparison = ("comp_set", "star_compset")
      } else if basis == "market_proxy" {
        comparison = ("market", "market_proxy")
      } else {
        comparison = nil
        records.warn(
          code: "missing_comparison_basis",
          row: passage.locator.rowStart,
          message:
            "STAR row basis must be 'star_compset' or 'market_proxy'; comparison values were not promoted."
        )
      }

      if let comparison, let value = fields["comp_set"],
        let parsed = parseNumber(value, normalizedUnit: mapping.normalizedUnit)
      {
        records.addAssertion(
          sourceID: ingestion.source.id,
          passage: passage,
          assetID: assetID,
          predicate: mapping.predicate,
          number: parsed.number,
          unit: mapping.normalizedUnit,
          scale: parsed.scale,
          qualifiers: qualifiers(
            period: period,
            scope: "rooms",
            status: status,
            labels: labels,
            benchmark: comparison.benchmark,
            comparisonBasis: comparison.basis
          ),
          discriminator: "comparison",
          note: note
        )
      }

      if let comparison, let value = fields["index"],
        let parsed = parseNumber(value, normalizedUnit: "ratio")
      {
        records.addAssertion(
          sourceID: ingestion.source.id,
          passage: passage,
          assetID: assetID,
          predicate: mapping.indexPredicate,
          number: parsed.number,
          unit: "ratio",
          scale: parsed.scale,
          qualifiers: qualifiers(
            period: period,
            scope: "rooms",
            status: status,
            labels: labels,
            benchmark: comparison.benchmark,
            comparisonBasis: comparison.basis
          ),
          discriminator: "index",
          note: note
        )
      }
    }
    return records
  }

  private static func fieldsByHeader(_ passage: KnowledgePassage) -> [String: String] {
    (passage.spreadsheet?.cells ?? []).reduce(into: [String: String]()) { fields, cell in
      guard let header = cell.header?.lowercased(), let value = cell.value else { return }
      fields[header] = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }

  private static func provenance(from passages: [KnowledgePassage]) -> [String: String] {
    passages.reduce(into: [String: String]()) { result, passage in
      guard passage.locator.rowStart != nil,
        passage.spreadsheet?.isHeaderRow != true,
        let raw = passage.spreadsheet?.cells.first?.value?.trimmingCharacters(
          in: .whitespacesAndNewlines),
        raw.hasPrefix("#"), let separator = raw.firstIndex(of: ":")
      else { return }
      let key = raw[raw.index(after: raw.startIndex)..<separator]
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: " ", with: "_")
      let value = raw[raw.index(after: separator)...]
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if !key.isEmpty, !value.isEmpty { result[key] = value }
    }
  }

  private static func reportingStatus(explicit: String?, filename: String) throws -> String {
    let candidate: String
    if let explicit {
      candidate = explicit.lowercased()
    } else {
      let name = filename.lowercased()
      if name.contains("budget") {
        candidate = "budget"
      } else if name.contains("forecast") {
        candidate = "forecast"
      } else {
        candidate = "actual"
      }
    }
    guard ["actual", "budget", "forecast"].contains(candidate) else {
      throw HospitalityUnderwritingImportError.invalidStatus(candidate)
    }
    return candidate
  }

  private static func inferReportingPeriod(from filename: String) -> String? {
    let normalized = filename.uppercased().replacingOccurrences(of: "_", with: "-")
    if let match = normalized.range(
      of: "(TTM|YTD)[ -]?(20\\d{2})[.-](0[1-9]|1[0-2])",
      options: .regularExpression
    ) {
      let parts = normalized[match]
        .replacingOccurrences(of: " ", with: "-")
        .split(separator: "-")
      if parts.count == 3 { return "\(parts[0]):\(parts[1])-\(parts[2])" }
    }
    if let range = normalized.range(of: "20\\d{2}", options: .regularExpression) {
      return String(normalized[range])
    }
    return nil
  }

  private static func valuePeriod(column: String, reportingPeriod: String) -> String? {
    let normalized = column.lowercased()
    if ["fy", "ytd", "ttm", "actual", "budget", "forecast"].contains(normalized) {
      return reportingPeriod
    }
    let months = [
      "jan": "01", "feb": "02", "mar": "03", "apr": "04", "may": "05", "jun": "06",
      "jul": "07", "aug": "08", "sep": "09", "oct": "10", "nov": "11", "dec": "12",
    ]
    guard let month = months[normalized], reportingPeriod.count == 4 else { return nil }
    return "\(reportingPeriod)-\(month)"
  }

  private static func parseNumber(
    _ raw: String,
    normalizedUnit: String
  ) -> (number: Double, scale: Double)? {
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, !["-", "—", "n/a", "null"].contains(value.lowercased()) else {
      return nil
    }
    let isNegative = value.hasPrefix("(") && value.hasSuffix(")")
    let hasPercent = value.contains("%")
    value =
      value
      .replacingOccurrences(of: "$", with: "")
      .replacingOccurrences(of: ",", with: "")
      .replacingOccurrences(of: "%", with: "")
      .replacingOccurrences(of: "(", with: "")
      .replacingOccurrences(of: ")", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard var number = Double(value), number.isFinite else { return nil }
    if isNegative { number *= -1 }
    let scale = normalizedUnit == "ratio" && (hasPercent || abs(number) > 2) ? 0.01 : 1
    return (number, scale)
  }

  private static func qualifiers(
    period: String,
    scope: String,
    status: String,
    labels: HospitalityUnderwritingSourceLabels,
    benchmark: String,
    comparisonBasis: String
  ) -> [String: String] {
    [
      "period": period,
      "scope": scope,
      "status": status,
      "value_stage": labels.valueStage.rawValue,
      "benchmark": benchmark,
      "comparison_basis": comparisonBasis,
      "source_role": labels.role.rawValue,
    ]
  }

  private struct MetricMapping {
    let predicate: String
    let normalizedUnit: String
    let sourceUnits: Set<String>
    let scope: String
  }

  private struct STARMapping {
    let predicate: String
    let indexPredicate: String
    let normalizedUnit: String
  }

  private static let profitAndLossMappings: [String: MetricMapping] = [
    "stats.room_count": MetricMapping(
      predicate: "hospitality.room_count", normalizedUnit: "room",
      sourceUnits: ["count", "rooms"], scope: "rooms"),
    "stats.days_available": MetricMapping(
      predicate: "hospitality.days_available", normalizedUnit: "day",
      sourceUnits: ["count"], scope: "rooms"),
    "stats.rooms_available": MetricMapping(
      predicate: "hospitality.available_room_nights", normalizedUnit: "room_night",
      sourceUnits: ["rooms"], scope: "rooms"),
    "stats.rooms_sold": MetricMapping(
      predicate: "hospitality.rooms_sold", normalizedUnit: "room_night",
      sourceUnits: ["rooms"], scope: "rooms"),
    "stats.occupancy": MetricMapping(
      predicate: "hospitality.occupancy", normalizedUnit: "ratio",
      sourceUnits: ["occ", "pct"], scope: "rooms"),
    "stats.adr": MetricMapping(
      predicate: "hospitality.adr", normalizedUnit: "USD_per_sold_room",
      sourceUnits: ["adr"], scope: "rooms"),
    "stats.revpar": MetricMapping(
      predicate: "hospitality.revpar", normalizedUnit: "USD_per_available_room",
      sourceUnits: ["revpar"], scope: "rooms"),
    "revenue.rooms": MetricMapping(
      predicate: "hospitality.room_revenue", normalizedUnit: "USD",
      sourceUnits: ["usd"], scope: "rooms"),
    "revenue.food": MetricMapping(
      predicate: "hospitality.food_revenue", normalizedUnit: "USD",
      sourceUnits: ["usd"], scope: "asset"),
    "revenue.beverage": MetricMapping(
      predicate: "hospitality.beverage_revenue", normalizedUnit: "USD",
      sourceUnits: ["usd"], scope: "asset"),
    "revenue.food_beverage": MetricMapping(
      predicate: "hospitality.food_beverage_revenue", normalizedUnit: "USD",
      sourceUnits: ["usd"], scope: "asset"),
    "revenue.other_operated": MetricMapping(
      predicate: "hospitality.other_revenue", normalizedUnit: "USD",
      sourceUnits: ["usd"], scope: "asset"),
    "revenue.misc_income": MetricMapping(
      predicate: "hospitality.miscellaneous_income", normalizedUnit: "USD",
      sourceUnits: ["usd"], scope: "asset"),
    "revenue.total_revenue": MetricMapping(
      predicate: "hospitality.total_revenue", normalizedUnit: "USD",
      sourceUnits: ["usd"], scope: "asset"),
    "departmental_expense.total_dept_expense": MetricMapping(
      predicate: "hospitality.departmental_expense", normalizedUnit: "USD",
      sourceUnits: ["usd"], scope: "asset"),
    "undistributed_expense.total_undistributed": MetricMapping(
      predicate: "hospitality.undistributed_expense", normalizedUnit: "USD",
      sourceUnits: ["usd"], scope: "asset"),
    "fixed_charges.total_fixed": MetricMapping(
      predicate: "hospitality.fixed_charges", normalizedUnit: "USD",
      sourceUnits: ["usd"], scope: "asset"),
    "fixed_charges.total_fixed_charges": MetricMapping(
      predicate: "hospitality.fixed_charges", normalizedUnit: "USD",
      sourceUnits: ["usd"], scope: "asset"),
    "ebitda.gop": MetricMapping(
      predicate: "hospitality.gross_operating_profit", normalizedUnit: "USD",
      sourceUnits: ["usd"], scope: "asset"),
    "ebitda.ebitda": MetricMapping(
      predicate: "hospitality.ebitda", normalizedUnit: "USD",
      sourceUnits: ["usd"], scope: "asset"),
    "ebitda.noi": MetricMapping(
      predicate: "hospitality.net_operating_income", normalizedUnit: "USD",
      sourceUnits: ["usd"], scope: "asset"),
  ]

  private static let starMappings: [String: STARMapping] = [
    "occ": STARMapping(
      predicate: "hospitality.occupancy", indexPredicate: "hospitality.occupancy_index",
      normalizedUnit: "ratio"),
    "adr": STARMapping(
      predicate: "hospitality.adr", indexPredicate: "hospitality.adr_index",
      normalizedUnit: "USD_per_sold_room"),
    "revpar": STARMapping(
      predicate: "hospitality.revpar", indexPredicate: "hospitality.revpar_index",
      normalizedUnit: "USD_per_available_room"),
  ]

  private struct ImportedRecords {
    var assertions: [KnowledgeAssertion] = []
    var evidenceLinks: [KnowledgeEvidenceLink] = []
    var warnings: [HospitalityUnderwritingImportWarning] = []

    mutating func addAssertion(
      sourceID: String,
      passage: KnowledgePassage,
      assetID: String,
      predicate: String,
      number: Double,
      unit: String,
      scale: Double,
      qualifiers: [String: String],
      discriminator: String,
      note: String?
    ) {
      let identity = [
        sourceID, passage.id, assetID, predicate, qualifiers["period"] ?? "", discriminator,
      ].joined(separator: "|")
      let suffix = HospitalityUnderwritingCSVImporter.sha256(identity)
      let assertionID = "assertion-\(suffix.prefix(24))"
      let evidenceID = "evidence-\(suffix.prefix(24))"
      assertions.append(
        KnowledgeAssertion(
          id: assertionID,
          subject: assetID,
          predicate: predicate,
          value: KnowledgeValue(
            type: .number,
            number: number,
            unit: unit,
            scale: scale
          ),
          qualifiers: qualifiers,
          kind: .stated,
          confidence: 1,
          evidenceLinkIDs: [evidenceID]
        ))
      evidenceLinks.append(
        KnowledgeEvidenceLink(
          id: evidenceID,
          assertionID: assertionID,
          passageID: passage.id,
          relation: .supports,
          note: note?.isEmpty == false ? note : "Exact transcription from underwriting CSV."
        ))
    }

    mutating func warn(code: String, row: Int?, message: String) {
      let identity = "\(code)|\(row ?? 0)|\(message)"
      warnings.append(
        HospitalityUnderwritingImportWarning(
          id: "warning-\(HospitalityUnderwritingCSVImporter.sha256(identity).prefix(24))",
          code: code,
          row: row,
          message: message
        ))
    }
  }

  private static func sha256(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}
