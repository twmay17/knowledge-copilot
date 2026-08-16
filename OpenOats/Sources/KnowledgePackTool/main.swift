import Darwin
import Foundation
import HospitalityDomainProfile
import OpenOatsKit

@main
struct KnowledgePackTool {
  static func main() async {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else {
      fail(usage)
    }

    do {
      let profiles = KnowledgeDomainProfileRegistry(profiles: [HospitalityDomainProfile()])
      switch command {
      case "validate":
        let (pack, _) = try loadPack(arguments: arguments, profiles: profiles)
        validate(pack)
      case "inspect":
        let (pack, _) = try loadPack(arguments: arguments, profiles: profiles)
        inspect(pack)
      case "search":
        try search(arguments: arguments, profiles: profiles)
      case "replay":
        try replay(arguments: arguments, profiles: profiles)
      case "benchmark-replay":
        try benchmarkReplay(arguments: arguments, profiles: profiles)
      case "audit-correctness":
        try auditCorrectness(arguments: arguments, profiles: profiles)
      case "fingerprint-correctness":
        try fingerprintCorrectness(arguments: arguments, profiles: profiles)
      case "benchmark-latency":
        try await benchmarkLatency(arguments: arguments, profiles: profiles)
      case "ingest-document":
        try ingestDocument(arguments: arguments)
      case "ingest-spreadsheet":
        try ingestSpreadsheet(arguments: arguments)
      case "import-underwriting-csv":
        try importUnderwritingCSV(arguments: arguments)
      case "export-study-bundle":
        try exportStudyBundle(arguments: arguments, profiles: profiles)
      case "analyze-study-with-ollama":
        try await analyzeStudyWithOllama(arguments: arguments, profiles: profiles)
      case "prepare-study-review":
        try prepareStudyReview(arguments: arguments, profiles: profiles)
      case "approve-study-review":
        try approveStudyReview(arguments: arguments, profiles: profiles)
      case "plan-study-import":
        try planStudyImport(arguments: arguments, profiles: profiles)
      case "apply-study-import":
        try applyStudyImport(arguments: arguments, profiles: profiles)
      case "help", "--help", "-h":
        print(usage)
      default:
        fail("Unknown command '\(command)'.\n\n\(usage)")
      }
    } catch {
      fail(String(describing: error))
    }
  }

  private static func loadPack(
    arguments: [String],
    profiles: KnowledgeDomainProfileRegistry
  ) throws -> (KnowledgePack, URL) {
    guard arguments.count == 2 else { fail(usage) }
    let directory = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
    return (try KnowledgePackLoader(profileRegistry: profiles).load(from: directory), directory)
  }

  private static func validate(_ pack: KnowledgePack) {
    print("Valid KnowledgePack: \(pack.manifest.title)")
    print("Pack ID: \(pack.manifest.packID)")
    print("Schema: \(pack.manifest.schemaVersion)")
    print(
      "Sources: \(pack.sources.count); passages: \(pack.passages.count); assertions: \(pack.assertions.count); cards: \(pack.responseCards.count)"
    )
  }

  private static func inspect(_ pack: KnowledgePack) {
    print("\(pack.manifest.title) [\(pack.manifest.packID)]")
    print(
      "Profiles: \(pack.manifest.domainProfiles.map { "\($0.id)@\($0.version)" }.joined(separator: ", "))"
    )
    for card in pack.responseCards {
      print("- [\(card.evidenceState.rawValue)] \(card.title): \(card.answer)")
    }
  }

  private static func search(
    arguments: [String],
    profiles: KnowledgeDomainProfileRegistry
  ) throws {
    guard arguments.count >= 3 else { fail(usage) }
    let directory = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
    let options = parseOptions(
      Array(arguments.dropFirst(3)),
      supported: ["--kind", "--source", "--qualifier", "--limit"]
    )
    let pack = try KnowledgePackLoader(profileRegistry: profiles).load(from: directory)
    let kinds: Set<KnowledgePackSearchRecordKind>
    if let rawKind = options["--kind"] {
      guard let kind = KnowledgePackSearchRecordKind(rawValue: rawKind) else { fail(usage) }
      kinds = [kind]
    } else {
      kinds = []
    }
    let requiredQualifiers: [String: String]
    if let qualifier = options["--qualifier"] {
      let parts = qualifier.split(separator: "=", maxSplits: 1).map(String.init)
      guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { fail(usage) }
      requiredQualifiers = [parts[0]: parts[1]]
    } else {
      requiredQualifiers = [:]
    }
    let limit = options["--limit"].flatMap(Int.init) ?? 10
    let results = try KnowledgePackSearchIndex(pack: pack).search(
      KnowledgePackSearchQuery(
        text: arguments[2],
        scope: KnowledgePackSearchScope(
          packID: pack.manifest.packID,
          recordKinds: kinds,
          sourceIDs: options["--source"].map { [$0] } ?? [],
          requiredQualifiers: requiredQualifiers
        ),
        limit: limit
      )
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    FileHandle.standardOutput.write(try encoder.encode(results))
    FileHandle.standardOutput.write(Data("\n".utf8))
  }

  private static func replay(
    arguments: [String],
    profiles: KnowledgeDomainProfileRegistry
  ) throws {
    guard arguments.count == 3 || arguments.count == 5 else { fail(usage) }
    guard arguments.count == 3 || arguments[3] == "--output" else { fail(usage) }

    let directory = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
    let specURL = URL(fileURLWithPath: arguments[2]).standardizedFileURL
    let pack = try KnowledgePackLoader(profileRegistry: profiles).load(from: directory)
    let spec = try JSONDecoder().decode(
      KnowledgeProofReplaySpec.self,
      from: Data(contentsOf: specURL)
    )
    let report = try KnowledgeProofReplayRunner(
      pack: pack,
      rootDirectory: directory,
      termAliases: profiles.termAliases(for: pack.manifest)
    ).run(spec)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let reportData = try encoder.encode(report)

    if arguments.count == 5 {
      let outputURL = URL(fileURLWithPath: arguments[4]).standardizedFileURL
      try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try reportData.write(to: outputURL, options: .atomic)
      printReplaySummary(report)
      print("Report: \(outputURL.path)")
    } else {
      FileHandle.standardOutput.write(reportData)
      FileHandle.standardOutput.write(Data("\n".utf8))
    }

    if report.verdict == .fail {
      Darwin.exit(EXIT_FAILURE)
    }
  }

  private static func benchmarkReplay(
    arguments: [String],
    profiles: KnowledgeDomainProfileRegistry
  ) throws {
    guard arguments.count == 2 || arguments.count == 4 else { fail(usage) }
    guard arguments.count == 2 || arguments[2] == "--output" else { fail(usage) }

    let specURL = URL(fileURLWithPath: arguments[1]).standardizedFileURL
    let fixtureRoot = specURL.deletingLastPathComponent().resolvingSymlinksInPath()
    let spec = try JSONDecoder().decode(
      KnowledgeReplayBenchmarkSpec.self,
      from: Data(contentsOf: specURL)
    )
    var packs: [String: KnowledgeReplayBenchmarkPack] = [:]
    for reference in spec.packs {
      guard !reference.relativePath.hasPrefix("/") else {
        fail("Benchmark KnowledgePack paths must be relative to the benchmark file.")
      }
      let directory = fixtureRoot.appendingPathComponent(
        reference.relativePath,
        isDirectory: true
      ).standardizedFileURL.resolvingSymlinksInPath()
      guard isInside(directory, root: fixtureRoot) else {
        fail("Benchmark KnowledgePack paths must stay inside the benchmark fixture root.")
      }
      let pack = try KnowledgePackLoader(profileRegistry: profiles).load(from: directory)
      guard pack.manifest.packID == reference.packID else {
        fail(
          "Benchmark expected pack '\(reference.packID)' at \(reference.relativePath), but loaded '\(pack.manifest.packID)'."
        )
      }
      packs[reference.packID] = KnowledgeReplayBenchmarkPack(
        pack: pack,
        rootDirectory: directory,
        termAliases: profiles.termAliases(for: pack.manifest)
      )
    }
    let report = try KnowledgeReplayBenchmarkRunner(packs: packs).run(spec)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let reportData = try encoder.encode(report)

    if arguments.count == 4 {
      let outputURL = URL(fileURLWithPath: arguments[3]).standardizedFileURL
      try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try reportData.write(to: outputURL, options: .atomic)
      printReplayBenchmarkSummary(report)
      print("Report: \(outputURL.path)")
    } else {
      FileHandle.standardOutput.write(reportData)
      FileHandle.standardOutput.write(Data("\n".utf8))
    }

    if report.verdict == .fail {
      Darwin.exit(EXIT_FAILURE)
    }
  }

  private static func benchmarkLatency(
    arguments: [String],
    profiles: KnowledgeDomainProfileRegistry
  ) async throws {
    guard arguments.count >= 2 else { fail(usage) }
    let options = parseOptions(
      Array(arguments.dropFirst(2)),
      supported: ["--samples", "--output"]
    )
    let sampleCount = options["--samples"].flatMap(Int.init) ?? 50
    guard (1...10_000).contains(sampleCount) else { fail(usage) }

    let directory = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
    let pack = try KnowledgePackLoader(profileRegistry: profiles).load(from: directory)
    guard
      let responseCard = pack.responseCards.first(where: {
        $0.reviewStatus == .reviewed && !$0.questionFamilyIDs.isEmpty
      }),
      let questionFamilyID = responseCard.questionFamilyIDs.first,
      let questionFamily = pack.questionFamilies.first(where: { $0.id == questionFamilyID })
    else {
      fail("Latency benchmark requires at least one reviewed response card and question family.")
    }

    let hotResolver = try makeTieredResolver(pack: pack, rootDirectory: directory)
    let warmPack = KnowledgePack(
      manifest: pack.manifest,
      sources: pack.sources,
      passages: pack.passages,
      assertions: pack.assertions,
      evidenceLinks: pack.evidenceLinks,
      calculations: pack.calculations,
      responseCards: [],
      questionFamilies: pack.questionFamilies
    )
    let warmResolver = try makeTieredResolver(pack: warmPack, rootDirectory: directory)
    var samples: [KnowledgeAnswerLatencySample] = []

    for index in 0..<sampleCount {
      let streamID = "latency-hot-\(index)"
      let candidate = QuestionCandidate(
        id: "\(streamID)#1",
        streamID: streamID,
        revisionSequence: 1,
        questionFamilyID: questionFamily.id,
        sourceText: questionFamily.canonicalQuestion,
        confidence: 1,
        status: .stable,
        bindings: []
      )
      let start = ContinuousClock().now
      let updates = await collect(hotResolver.updates(for: .questionStable(candidate)))
      guard let update = updates.first(where: { $0.lane == .hot }), let timing = update.timing
      else { fail("Hot lane did not produce a benchmark answer.") }
      samples.append(
        KnowledgeAnswerLatencySample(
          lane: .hot,
          endToEndMilliseconds: milliseconds(start.duration(to: ContinuousClock().now)),
          resolverMilliseconds: timing.elapsedMilliseconds
        )
      )
    }

    for index in 0..<sampleCount {
      let streamID = "latency-warm-\(index)"
      let candidate = QuestionCandidate(
        id: "\(streamID)#1",
        streamID: streamID,
        revisionSequence: 1,
        questionFamilyID: questionFamily.id,
        sourceText: questionFamily.canonicalQuestion,
        confidence: 0.7,
        status: .provisional,
        bindings: [
          ResolvedQuestionBinding(
            key: "term",
            value: "question_family:\(questionFamily.id)",
            surfaceText: questionFamily.canonicalQuestion
          )
        ]
      )
      let start = ContinuousClock().now
      let updates = await collect(warmResolver.updates(for: .questionCandidate(candidate)))
      guard let update = updates.first(where: { $0.lane == .warm }), let timing = update.timing
      else { fail("Warm lane did not produce a benchmark answer.") }
      samples.append(
        KnowledgeAnswerLatencySample(
          lane: .warm,
          endToEndMilliseconds: milliseconds(start.duration(to: ContinuousClock().now)),
          resolverMilliseconds: timing.elapsedMilliseconds
        )
      )
    }

    let report = KnowledgeAnswerLatencyReport(samples: samples)
    let budgets = KnowledgeAnswerLatencyBudgets()
    let output = LatencyBenchmarkOutput(
      generatedAt: Date(),
      packID: pack.manifest.packID,
      sampleCountPerLane: sampleCount,
      verdict: report.meetsLiveP50Targets ? "pass" : "fail",
      lanes: report.summaries.filter { $0.lane != .cold }.map {
        LatencyBenchmarkOutput.Lane(
          lane: $0.lane.rawValue,
          sampleCount: $0.sampleCount,
          componentBudgetMilliseconds: budgets.milliseconds(for: $0.lane),
          liveP50TargetMilliseconds: $0.targetMilliseconds ?? 0,
          resolverP50Milliseconds: $0.resolverP50Milliseconds,
          endToEndP50Milliseconds: $0.endToEndP50Milliseconds,
          endToEndP95Milliseconds: $0.endToEndP95Milliseconds,
          endToEndMaximumMilliseconds: $0.endToEndMaximumMilliseconds,
          meetsLiveP50Target: $0.meetsP50Target == true
        )
      }
    )

    if let outputPath = options["--output"] {
      let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL
      requireOutputOutsidePack(outputURL, packDirectory: directory)
      try writeJSON(output, to: outputURL)
      printLatencyBenchmarkSummary(output)
      print("Report: \(outputURL.path)")
    } else {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      encoder.dateEncodingStrategy = .iso8601
      FileHandle.standardOutput.write(try encoder.encode(output))
      FileHandle.standardOutput.write(Data("\n".utf8))
    }

    if !report.meetsLiveP50Targets { Darwin.exit(EXIT_FAILURE) }
  }

  private static func fingerprintCorrectness(
    arguments: [String],
    profiles: KnowledgeDomainProfileRegistry
  ) throws {
    let (pack, _) = try loadPack(arguments: arguments, profiles: profiles)
    let fingerprints = try KnowledgeCorrectnessFingerprints.make(for: pack)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    FileHandle.standardOutput.write(try encoder.encode(fingerprints))
    FileHandle.standardOutput.write(Data("\n".utf8))
  }

  private static func auditCorrectness(
    arguments: [String],
    profiles: KnowledgeDomainProfileRegistry
  ) throws {
    guard arguments.count == 2 || arguments.count == 4 else { fail(usage) }
    guard arguments.count == 2 || arguments[2] == "--output" else { fail(usage) }

    let specURL = URL(fileURLWithPath: arguments[1]).standardizedFileURL
    let fixtureRoot = specURL.deletingLastPathComponent().resolvingSymlinksInPath()
    let spec = try JSONDecoder().decode(
      KnowledgeCorrectnessGateSpec.self,
      from: Data(contentsOf: specURL)
    )
    guard !spec.benchmarkRelativePath.hasPrefix("/") else {
      fail("Correctness benchmark path must be relative to the correctness spec.")
    }
    let benchmarkURL = fixtureRoot.appendingPathComponent(spec.benchmarkRelativePath)
      .standardizedFileURL.resolvingSymlinksInPath()
    guard isInside(benchmarkURL, root: fixtureRoot) else {
      fail("Correctness benchmark path must stay inside the fixture root.")
    }
    let benchmark = try JSONDecoder().decode(
      KnowledgeReplayBenchmarkSpec.self,
      from: Data(contentsOf: benchmarkURL)
    )

    var packs: [String: KnowledgeReplayBenchmarkPack] = [:]
    for reference in spec.packs {
      guard !reference.relativePath.hasPrefix("/") else {
        fail("Correctness KnowledgePack paths must be relative to the correctness spec.")
      }
      let directory = fixtureRoot.appendingPathComponent(
        reference.relativePath,
        isDirectory: true
      ).standardizedFileURL.resolvingSymlinksInPath()
      guard isInside(directory, root: fixtureRoot) else {
        fail("Correctness KnowledgePack paths must stay inside the fixture root.")
      }
      let pack = try KnowledgePackLoader(profileRegistry: profiles).load(from: directory)
      guard pack.manifest.packID == reference.packID else {
        fail(
          "Correctness gate expected pack '\(reference.packID)' at \(reference.relativePath), but loaded '\(pack.manifest.packID)'."
        )
      }
      packs[reference.packID] = KnowledgeReplayBenchmarkPack(
        pack: pack,
        rootDirectory: directory,
        termAliases: profiles.termAliases(for: pack.manifest)
      )
    }

    let report = try KnowledgeCorrectnessGateRunner(
      packs: packs,
      profileRegistry: profiles
    ).run(spec, benchmark: benchmark)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let reportData = try encoder.encode(report)

    if arguments.count == 4 {
      let outputURL = URL(fileURLWithPath: arguments[3]).standardizedFileURL
      try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try reportData.write(to: outputURL, options: .atomic)
      printCorrectnessSummary(report)
      print("Report: \(outputURL.path)")
    } else {
      FileHandle.standardOutput.write(reportData)
      FileHandle.standardOutput.write(Data("\n".utf8))
    }

    if report.verdict == .fail {
      Darwin.exit(EXIT_FAILURE)
    }
  }

  private static func makeTieredResolver(
    pack: KnowledgePack,
    rootDirectory: URL
  ) throws -> KnowledgeTieredAnswerResolver {
    let searchIndex = try KnowledgePackSearchIndex(pack: pack)
    let evaluator = try KnowledgeEvidenceOutcomeEvaluator(
      pack: pack,
      searchIndex: searchIndex,
      rootDirectory: rootDirectory
    )
    return try KnowledgeTieredAnswerResolver(
      pack: pack,
      searchIndex: searchIndex,
      evidenceEvaluator: evaluator,
      rootDirectory: rootDirectory
    )
  }

  private static func collect(
    _ stream: AsyncStream<KnowledgeTieredAnswerUpdate>
  ) async -> [KnowledgeTieredAnswerUpdate] {
    var updates: [KnowledgeTieredAnswerUpdate] = []
    for await update in stream { updates.append(update) }
    return updates
  }

  private static func ingestDocument(arguments: [String]) throws {
    guard arguments.count >= 4 else { fail(usage) }
    let documentURL = URL(fileURLWithPath: arguments[1]).standardizedFileURL
    let options = parseOptions(
      Array(arguments.dropFirst(2)),
      supported: ["--relative-path", "--title", "--output"]
    )
    guard let relativePath = options["--relative-path"] else { fail(usage) }

    let result = try KnowledgeDocumentIngestor().ingest(
      fileAt: documentURL,
      relativePath: relativePath,
      title: options["--title"]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    let resultData = try encoder.encode(result)

    if let outputPath = options["--output"] {
      let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL
      try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try resultData.write(to: outputURL, options: .atomic)
      printDocumentIngestionSummary(result)
      print("Result: \(outputURL.path)")
    } else {
      FileHandle.standardOutput.write(resultData)
      FileHandle.standardOutput.write(Data("\n".utf8))
    }
  }

  private static func ingestSpreadsheet(arguments: [String]) throws {
    guard arguments.count >= 4 else { fail(usage) }
    let spreadsheetURL = URL(fileURLWithPath: arguments[1]).standardizedFileURL
    let options = parseOptions(
      Array(arguments.dropFirst(2)),
      supported: ["--relative-path", "--title", "--output"]
    )
    guard let relativePath = options["--relative-path"] else { fail(usage) }

    let result = try KnowledgeSpreadsheetIngestor().ingest(
      fileAt: spreadsheetURL,
      relativePath: relativePath,
      title: options["--title"]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    let resultData = try encoder.encode(result)

    if let outputPath = options["--output"] {
      let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL
      try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try resultData.write(to: outputURL, options: .atomic)
      printSpreadsheetIngestionSummary(result)
      print("Result: \(outputURL.path)")
    } else {
      FileHandle.standardOutput.write(resultData)
      FileHandle.standardOutput.write(Data("\n".utf8))
    }
  }

  private static func importUnderwritingCSV(arguments: [String]) throws {
    guard arguments.count >= 6 else { fail(usage) }
    let csvURL = URL(fileURLWithPath: arguments[1]).standardizedFileURL
    let options = parseOptions(
      Array(arguments.dropFirst(2)),
      supported: [
        "--relative-path", "--asset-id", "--period", "--status", "--title", "--output",
      ]
    )
    guard let relativePath = options["--relative-path"],
      let assetID = options["--asset-id"]
    else { fail(usage) }

    let result = try HospitalityUnderwritingCSVImporter().ingest(
      fileAt: csvURL,
      relativePath: relativePath,
      assetID: assetID,
      period: options["--period"],
      status: options["--status"],
      title: options["--title"]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    let resultData = try encoder.encode(result)

    if let outputPath = options["--output"] {
      let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL
      try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try resultData.write(to: outputURL, options: .atomic)
      printUnderwritingImportSummary(result)
      print("Result: \(outputURL.path)")
    } else {
      FileHandle.standardOutput.write(resultData)
      FileHandle.standardOutput.write(Data("\n".utf8))
    }
  }

  private static func exportStudyBundle(
    arguments: [String],
    profiles: KnowledgeDomainProfileRegistry
  ) throws {
    guard arguments.count == 4 else { fail(usage) }
    let directory = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
    let options = parseOptions(
      Array(arguments.dropFirst(2)),
      supported: ["--output"]
    )
    guard let outputPath = options["--output"] else { fail(usage) }

    let pack = try KnowledgePackLoader(profileRegistry: profiles).load(from: directory)
    let bundle = try KnowledgeStudyBundleBuilder().build(from: pack)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(bundle)
    let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL
    try FileManager.default.createDirectory(
      at: outputURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: outputURL, options: .atomic)

    print("Exported Study Bundle: \(bundle.bundleID)")
    print("Pack: \(bundle.packTitle) [\(bundle.packID)]")
    print(
      "Sources: \(bundle.sources.count); cited passages: \(bundle.citedPassages.count); assertions: \(bundle.assertions.count); calculations: \(bundle.calculations.count); reviewed cards: \(bundle.reviewedResponseCards.count)"
    )
    print("Closed corpus: yes; web search: disabled; citations: required")
    print("Result: \(outputURL.path)")
  }

  private static func analyzeStudyWithOllama(
    arguments: [String],
    profiles: KnowledgeDomainProfileRegistry
  ) async throws {
    guard arguments.count >= 6, arguments.count.isMultiple(of: 2) else { fail(usage) }
    let directory = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
    let options = parseOptions(
      Array(arguments.dropFirst(2)),
      supported: ["--model", "--base-url", "--timeout-seconds", "--output"]
    )
    guard let model = options["--model"], let outputPath = options["--output"] else {
      fail(usage)
    }
    let baseURLValue =
      options["--base-url"] ?? KnowledgeOllamaStudyProvider.defaultBaseURL.absoluteString
    guard let baseURL = URL(string: baseURLValue) else {
      fail("Invalid --base-url '\(baseURLValue)'.")
    }
    let requestTimeout: TimeInterval
    if let rawTimeout = options["--timeout-seconds"] {
      guard let parsedTimeout = TimeInterval(rawTimeout), parsedTimeout > 0 else {
        fail("--timeout-seconds must be a positive number.")
      }
      requestTimeout = parsedTimeout
    } else {
      requestTimeout = KnowledgeOllamaStudyProvider.defaultRequestTimeout
    }

    let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL
    requireOutputOutsidePack(outputURL, packDirectory: directory)
    let pack = try KnowledgePackLoader(profileRegistry: profiles).load(from: directory)
    let bundle = try KnowledgeStudyBundleBuilder().build(from: pack)
    let provider = try KnowledgeOllamaStudyProvider(
      baseURL: baseURL,
      model: model,
      requestTimeout: requestTimeout
    )
    let analysis = try await provider.analyze(bundle: bundle)
    try writeJSON(analysis, to: outputURL)

    print("Generated local Study Analysis: \(analysis.analysisID)")
    print("Bundle: \(analysis.bundleID); pack: \(analysis.packID)")
    print("Generator: \(analysis.generator)")
    print(
      "Question families: \(analysis.questionFamilyProposals.count); response cards: \(analysis.responseCardProposals.count); contradictions: \(analysis.contradictions.count); gaps: \(analysis.corpusGaps.count)"
    )
    print("Endpoint: \(provider.endpoint.absoluteString); external network: blocked")
    print("All proposals remain generated and require the existing human-review gate.")
    print("Result: \(outputURL.path)")
  }

  private static func prepareStudyReview(
    arguments: [String],
    profiles: KnowledgeDomainProfileRegistry
  ) throws {
    guard arguments.count == 5 else { fail(usage) }
    let directory = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
    let analysisURL = URL(fileURLWithPath: arguments[2]).standardizedFileURL
    let options = parseOptions(
      Array(arguments.dropFirst(3)),
      supported: ["--output"]
    )
    guard let outputPath = options["--output"] else { fail(usage) }

    let pack = try KnowledgePackLoader(profileRegistry: profiles).load(from: directory)
    let bundle = try KnowledgeStudyBundleBuilder().build(from: pack)
    let analysis = try decodeJSON(KnowledgeStudyAnalysis.self, from: analysisURL)
    let queue = try KnowledgeStudyAnalysisValidator().makeReviewQueue(
      analysis: analysis,
      bundle: bundle
    )
    let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL
    try writeJSON(queue, to: outputURL)

    print("Prepared Study Review: \(queue.queueID)")
    print("Analysis: \(queue.analysis.analysisID); generator: \(queue.analysis.generator)")
    print(
      "Pending question families: \(queue.analysis.questionFamilyProposals.count); response cards: \(queue.responseCardItems.count); contradictions: \(queue.analysis.contradictions.count); gaps: \(queue.analysis.corpusGaps.count)"
    )
    print("All model proposals remain generated and require an explicit human decision.")
    print("Result: \(outputURL.path)")
  }

  private static func approveStudyReview(
    arguments: [String],
    profiles: KnowledgeDomainProfileRegistry
  ) throws {
    guard arguments.count == 6 else { fail(usage) }
    let directory = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
    let queueURL = URL(fileURLWithPath: arguments[2]).standardizedFileURL
    let decisionsURL = URL(fileURLWithPath: arguments[3]).standardizedFileURL
    let options = parseOptions(
      Array(arguments.dropFirst(4)),
      supported: ["--output"]
    )
    guard let outputPath = options["--output"] else { fail(usage) }

    let pack = try KnowledgePackLoader(profileRegistry: profiles).load(from: directory)
    let queue = try decodeJSON(KnowledgeStudyReviewQueue.self, from: queueURL)
    let decisions = try decodeJSON(KnowledgeStudyReviewDecisionSet.self, from: decisionsURL)
    let approvedImport = try KnowledgeStudyReviewGate(profileRegistry: profiles).approve(
      queue: queue,
      decisions: decisions,
      pack: pack
    )
    let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL
    try writeJSON(approvedImport, to: outputURL)

    print("Approved Study Import: \(approvedImport.importID)")
    print(
      "Reviewer: \(approvedImport.reviewer); question families: \(approvedImport.approvedQuestionFamilies.count); response cards: \(approvedImport.approvedResponseCards.count); rejected: \(approvedImport.rejectedDecisions.count)"
    )
    print("No KnowledgePack files were modified; the output is a reviewed import artifact.")
    print("Result: \(outputURL.path)")
  }

  private static func planStudyImport(
    arguments: [String],
    profiles: KnowledgeDomainProfileRegistry
  ) throws {
    guard arguments.count == 5 else { fail(usage) }
    let directory = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
    let importURL = URL(fileURLWithPath: arguments[2]).standardizedFileURL
    let options = parseOptions(
      Array(arguments.dropFirst(3)),
      supported: ["--output"]
    )
    guard let outputPath = options["--output"] else { fail(usage) }

    let approvedImport = try decodeJSON(KnowledgeStudyApprovedImport.self, from: importURL)
    let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL
    requireOutputOutsidePack(outputURL, packDirectory: directory)
    let plan = try KnowledgeStudyImportApplier(profileRegistry: profiles).plan(
      approvedImport: approvedImport,
      packDirectory: directory
    )
    try writeJSON(plan, to: outputURL)

    print("Study Import Plan: \(plan.state.rawValue)")
    print("Import: \(plan.importID); pack: \(plan.packID)")
    print(
      "Approved question families: \(plan.approvedQuestionFamilyIDs.count); response cards: \(plan.approvedResponseCardIDs.count); rejected: \(plan.rejectedProposalCount)"
    )
    print("No KnowledgePack files were modified.")
    print("Result: \(outputURL.path)")
  }

  private static func applyStudyImport(
    arguments: [String],
    profiles: KnowledgeDomainProfileRegistry
  ) throws {
    guard arguments.count == 5 else { fail(usage) }
    let directory = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
    let importURL = URL(fileURLWithPath: arguments[2]).standardizedFileURL
    let options = parseOptions(
      Array(arguments.dropFirst(3)),
      supported: ["--output"]
    )
    guard let outputPath = options["--output"] else { fail(usage) }

    let approvedImport = try decodeJSON(KnowledgeStudyApprovedImport.self, from: importURL)
    let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL
    requireOutputOutsidePack(outputURL, packDirectory: directory)
    try FileManager.default.createDirectory(
      at: outputURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    guard FileManager.default.isWritableFile(atPath: outputURL.deletingLastPathComponent().path)
    else {
      throw CocoaError(.fileWriteNoPermission)
    }
    let receipt = try KnowledgeStudyImportApplier(profileRegistry: profiles).apply(
      approvedImport: approvedImport,
      to: directory
    )
    try writeJSON(receipt, to: outputURL)

    print("Study Import: \(receipt.outcome.rawValue)")
    print("Import: \(receipt.importID); reviewer: \(receipt.reviewer)")
    print(
      "Question families: \(receipt.approvedQuestionFamilyIDs.count); response cards: \(receipt.approvedResponseCardIDs.count)"
    )
    print("Pack hash: \(receipt.resultingPackContentHash)")
    print("Receipt: \(outputURL.path)")
  }

  private static func decodeJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(type, from: Data(contentsOf: url))
  }

  private static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(value)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: url, options: .atomic)
  }

  private static func requireOutputOutsidePack(_ outputURL: URL, packDirectory: URL) {
    let root = packDirectory.standardizedFileURL.resolvingSymlinksInPath()
    let target = outputURL.standardizedFileURL.resolvingSymlinksInPath()
    guard target.path != root.path, !target.path.hasPrefix(root.path + "/") else {
      fail(
        "Output must be outside the KnowledgePack directory so a plan or receipt cannot overwrite corpus files."
      )
    }
  }

  private static func parseOptions(
    _ arguments: [String],
    supported: Set<String>
  ) -> [String: String] {
    var options: [String: String] = [:]
    var index = 0
    while index < arguments.count {
      let key = arguments[index]
      guard supported.contains(key), index + 1 < arguments.count else { fail(usage) }
      options[key] = arguments[index + 1]
      index += 2
    }
    return options
  }

  private static func printDocumentIngestionSummary(_ result: KnowledgeDocumentIngestionResult) {
    let tableCount = Set(result.passages.compactMap(\.locator.table)).count
    print("Ingested: \(result.source.title)")
    print(
      "Passages: \(result.passages.count); tables: \(tableCount); warnings: \(result.warnings.count)"
    )
    for warning in result.warnings {
      print("Warning [\(warning.flag.rawValue)]: \(warning.message)")
    }
  }

  private static func printUnderwritingImportSummary(
    _ result: HospitalityUnderwritingImportResult
  ) {
    print("Imported: \(result.source.title)")
    print(
      "Profile: \(result.profileID)@\(result.profileVersion); role: \(result.labels.role.rawValue); type: \(result.labels.documentType.rawValue)"
    )
    print(
      "Passages: \(result.passages.count); assertions: \(result.assertions.count); warnings: \(result.warnings.count)"
    )
    for warning in result.warnings {
      let row = warning.row.map { " row \($0)" } ?? ""
      print("Warning [\(warning.code)]\(row): \(warning.message)")
    }
  }

  private static func printSpreadsheetIngestionSummary(
    _ result: KnowledgeSpreadsheetIngestionResult
  ) {
    let sheets = Set(result.passages.compactMap(\.locator.sheet)).count
    let formulaCells = result.passages.reduce(0) { count, passage in
      count + (passage.spreadsheet?.cells.filter { $0.formula != nil }.count ?? 0)
    }
    print("Ingested: \(result.source.title)")
    print(
      "Passages: \(result.passages.count); sheets: \(sheets); formula cells: \(formulaCells); warnings: \(result.warnings.count)"
    )
    for warning in result.warnings {
      print("Warning [\(warning.code)]: \(warning.message)")
    }
  }

  private static func printReplaySummary(_ report: KnowledgeProofReport) {
    print("\(report.verdict.rawValue): \(report.replayName)")
    print(
      "Answer: \(report.answerAppearedAtMilliseconds.map(formatted) ?? "never") ms; deadline: \(report.responseDeadlineMilliseconds) ms; headroom: \(report.deadlineHeadroomMilliseconds.map(formatted) ?? "n/a") ms"
    )
    print(
      "Processing latency: median \(formatted(report.latency.medianMilliseconds)) ms; p95 \(formatted(report.latency.p95Milliseconds)) ms; max \(formatted(report.latency.maximumMilliseconds)) ms"
    )
    for check in report.checks where !check.passed {
      print("Failed \(check.name): \(check.detail)")
    }
  }

  private static func printReplayBenchmarkSummary(_ report: KnowledgeReplayBenchmarkReport) {
    print("\(report.verdict.rawValue): \(report.benchmarkName)")
    print(
      "Scenarios: \(report.passedScenarioCount)/\(report.scenarioCount) passed; false cards: \(report.falseCardCount)/\(report.negativeScenarioCount) (\(formatted(report.falseCardRate)))"
    )
    print(
      "Processing latency: median \(formatted(report.latency.medianMilliseconds)) ms; p95 \(formatted(report.latency.p95Milliseconds)) ms; max \(formatted(report.latency.maximumMilliseconds)) ms"
    )
    for check in report.checks where !check.passed {
      print("Failed \(check.name): \(check.detail)")
    }
  }

  private static func printCorrectnessSummary(_ report: KnowledgeCorrectnessGateReport) {
    print("\(report.verdict.rawValue): \(report.gateName)")
    print(
      "Packs: \(report.packAudits.filter { $0.verdict == .pass }.count)/\(report.packAudits.count) passed; outcome probes: \(report.outcomeAudits.filter(\.passed).count)/\(report.outcomeAudits.count) passed"
    )
    if let replay = report.replayAudit {
      print(
        "Replay: \(replay.passedScenarioCount)/\(replay.scenarioCount) passed; cross-pack: \(replay.passedCrossPackScenarioCount)/\(replay.crossPackScenarioCount) passed"
      )
    }
    for check in report.checks where !check.passed {
      print("Failed \(check.name): \(check.detail)")
    }
  }

  private static func printLatencyBenchmarkSummary(_ report: LatencyBenchmarkOutput) {
    print("\(report.verdict.uppercased()): hot/warm latency benchmark")
    for lane in report.lanes {
      print(
        "\(lane.lane): end-to-end p50 \(formatted(lane.endToEndP50Milliseconds)) ms; p95 \(formatted(lane.endToEndP95Milliseconds)) ms; resolver p50 \(formatted(lane.resolverP50Milliseconds)) ms; target \(formatted(lane.liveP50TargetMilliseconds)) ms"
      )
    }
  }

  private static func milliseconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) * 1_000
      + Double(components.attoseconds) / 1_000_000_000_000_000
  }

  private static func formatted(_ value: Double) -> String {
    String(format: "%.3f", value)
  }

  private static func isInside(_ fileURL: URL, root: URL) -> Bool {
    let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
    return fileURL.path.hasPrefix(rootPath)
  }

  private static func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("knowledge-pack: \(message)\n".utf8))
    Darwin.exit(EXIT_FAILURE)
  }

  private static let usage = """
    Usage:
      knowledge-pack validate <pack-directory>
      knowledge-pack inspect <pack-directory>
      knowledge-pack search <pack-directory> <query> [--kind <record-kind>] [--source <source-id>] [--qualifier <key=value>] [--limit <1-100>]
      knowledge-pack replay <pack-directory> <replay-spec.json> [--output <report.json>]
      knowledge-pack benchmark-replay <benchmark-spec.json> [--output <report.json>]
      knowledge-pack audit-correctness <correctness-spec.json> [--output <report.json>]
      knowledge-pack fingerprint-correctness <pack-directory>
      knowledge-pack benchmark-latency <pack-directory> [--samples <1-10000>] [--output <report.json>]
      knowledge-pack ingest-document <document.pdf|document.docx> --relative-path <pack-relative-path> [--title <title>] [--output <result.json>]
      knowledge-pack ingest-spreadsheet <spreadsheet.xlsx|spreadsheet.csv> --relative-path <pack-relative-path> [--title <title>] [--output <result.json>]
      knowledge-pack import-underwriting-csv <pl-or-star.csv> --relative-path <pack-relative-path> --asset-id <stable-asset-id> [--period <YYYY|YYYY-MM|TTM:YYYY-MM|YTD:YYYY-MM>] [--status <actual|budget|forecast>] [--title <title>] [--output <result.json>]
      knowledge-pack export-study-bundle <pack-directory> --output <study-bundle.json>
      knowledge-pack analyze-study-with-ollama <pack-directory> --model <ollama-model> [--base-url <http://localhost:11434>] [--timeout-seconds <seconds>] --output <study-analysis.json>
      knowledge-pack prepare-study-review <pack-directory> <study-analysis.json> --output <review-queue.json>
      knowledge-pack approve-study-review <pack-directory> <review-queue.json> <review-decisions.json> --output <approved-import.json>
      knowledge-pack plan-study-import <pack-directory> <approved-import.json> --output <plan.json>
      knowledge-pack apply-study-import <pack-directory> <approved-import.json> --output <receipt.json>
    """
}

private struct LatencyBenchmarkOutput: Encodable {
  struct Lane: Encodable {
    let lane: String
    let sampleCount: Int
    let componentBudgetMilliseconds: Int
    let liveP50TargetMilliseconds: Double
    let resolverP50Milliseconds: Double
    let endToEndP50Milliseconds: Double
    let endToEndP95Milliseconds: Double
    let endToEndMaximumMilliseconds: Double
    let meetsLiveP50Target: Bool
  }

  let generatedAt: Date
  let packID: String
  let sampleCountPerLane: Int
  let verdict: String
  let lanes: [Lane]
}
