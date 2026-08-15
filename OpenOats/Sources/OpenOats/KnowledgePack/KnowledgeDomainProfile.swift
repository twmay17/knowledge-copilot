import Foundation

public struct DomainPredicateDefinition: Equatable, Sendable {
  public let predicate: String
  public let label: String
  public let aliases: [String]
  public let valueType: KnowledgeValueType
  public let requiredQualifierKeys: Set<String>
  public let allowedUnits: Set<String>

  public init(
    predicate: String,
    label: String,
    aliases: [String] = [],
    valueType: KnowledgeValueType,
    requiredQualifierKeys: Set<String> = [],
    allowedUnits: Set<String> = []
  ) {
    self.predicate = predicate
    self.label = label
    self.aliases = aliases
    self.valueType = valueType
    self.requiredQualifierKeys = requiredQualifierKeys
    self.allowedUnits = allowedUnits
  }
}

public struct DomainCalculationDefinition: Equatable, Sendable {
  public let id: String
  public let version: String
  public let expression: String
  public let inputPredicates: [String]
  public let outputPredicate: String

  public init(
    id: String,
    version: String,
    expression: String,
    inputPredicates: [String],
    outputPredicate: String
  ) {
    self.id = id
    self.version = version
    self.expression = expression
    self.inputPredicates = inputPredicates
    self.outputPredicate = outputPredicate
  }
}

public struct KnowledgeDomainProfileSchema: Equatable, Sendable {
  public let predicateNamespace: String
  public let predicates: [DomainPredicateDefinition]
  public let calculations: [DomainCalculationDefinition]
  public let contextQualifierKeys: Set<String>

  public init(
    predicateNamespace: String,
    predicates: [DomainPredicateDefinition],
    calculations: [DomainCalculationDefinition] = [],
    contextQualifierKeys: Set<String> = []
  ) {
    self.predicateNamespace = predicateNamespace
    self.predicates = predicates
    self.calculations = calculations
    self.contextQualifierKeys = contextQualifierKeys
  }
}

/// A domain plug-in describes vocabulary and deterministic calculations without gaining access to
/// audio capture, storage permissions, retrieval state, or presentation UI.
public protocol KnowledgeDomainProfile: Sendable {
  var id: String { get }
  var supportedVersions: Set<String> { get }

  func schema(for version: String) -> KnowledgeDomainProfileSchema?
  func validate(_ pack: KnowledgePack, version: String) -> [KnowledgePackValidationIssue]
}

extension KnowledgeDomainProfile {
  public func validate(_ pack: KnowledgePack, version: String)
    -> [KnowledgePackValidationIssue]
  {
    []
  }
}

public struct KnowledgeDomainProfileRegistry: Sendable {
  public static let empty = KnowledgeDomainProfileRegistry()

  private let profiles: [any KnowledgeDomainProfile]

  public init(profiles: [any KnowledgeDomainProfile] = []) {
    self.profiles = profiles
  }

  public func validate(_ pack: KnowledgePack) -> [KnowledgePackValidationIssue] {
    var issues: [KnowledgePackValidationIssue] = []
    let profileGroups = Dictionary(grouping: profiles, by: \KnowledgeDomainProfile.id)

    for (id, matches) in profileGroups where matches.count > 1 {
      issues.append(
        error(
          "profile.duplicate_registration",
          "Domain profile '\(id)' is registered more than once; validation cannot choose safely."))
    }

    let referenceGroups = Dictionary(
      grouping: pack.manifest.domainProfiles,
      by: { "\($0.id)@\($0.version)" }
    )
    for (key, matches) in referenceGroups where matches.count > 1 {
      issues.append(
        error(
          "profile.duplicate_reference",
          "Manifest references domain profile '\(key)' more than once."))
    }

    for reference in pack.manifest.domainProfiles {
      let id = reference.id.trimmingCharacters(in: .whitespacesAndNewlines)
      let version = reference.version.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !id.isEmpty else {
        issues.append(error("profile.empty_id", "Domain profile ID must not be empty."))
        continue
      }
      guard !version.isEmpty else {
        issues.append(
          error("profile.empty_version", "Domain profile '\(id)' must declare a version."))
        continue
      }

      guard let profile = profileGroups[id]?.first else {
        issues.append(
          error(
            "profile.unknown",
            "Domain profile '\(id)@\(version)' is not registered; the pack was rejected."))
        continue
      }
      guard profileGroups[id]?.count == 1 else { continue }
      guard profile.supportedVersions.contains(version) else {
        issues.append(
          error(
            "profile.unsupported_version",
            "Domain profile '\(id)' does not support version '\(version)'."))
        continue
      }
      guard let schema = profile.schema(for: version) else {
        issues.append(
          error(
            "profile.missing_schema",
            "Domain profile '\(id)@\(version)' is registered without a schema."))
        continue
      }

      issues.append(contentsOf: validate(pack, with: schema, profileID: id))
      issues.append(contentsOf: profile.validate(pack, version: version))
    }
    return issues
  }

  /// Returns profile-owned vocabulary as opaque term aliases for the domain-neutral live path.
  public func termAliases(for manifest: KnowledgePackManifest) -> [KnowledgeTermAlias] {
    let profileGroups = Dictionary(grouping: profiles, by: \KnowledgeDomainProfile.id)
    var aliases: [KnowledgeTermAlias] = []

    for reference in manifest.domainProfiles {
      guard profileGroups[reference.id]?.count == 1,
        let profile = profileGroups[reference.id]?.first,
        let schema = profile.schema(for: reference.version)
      else { continue }

      aliases.append(
        contentsOf: schema.predicates.map { definition in
          KnowledgeTermAlias(
            id: definition.predicate,
            canonicalText: definition.label,
            aliases: definition.aliases
          )
        })
    }

    return aliases.sorted { $0.id < $1.id }
  }

  /// Returns profile-owned qualifier dimensions that calculations must preserve whenever the
  /// output assertion declares them. Generic period, version, and scope dimensions are enforced
  /// by the core loader and do not need to be repeated here.
  public func contextQualifierKeys(for manifest: KnowledgePackManifest) -> Set<String> {
    let profileGroups = Dictionary(grouping: profiles, by: \KnowledgeDomainProfile.id)
    return manifest.domainProfiles.reduce(into: Set<String>()) { keys, reference in
      guard profileGroups[reference.id]?.count == 1,
        let profile = profileGroups[reference.id]?.first,
        let schema = profile.schema(for: reference.version)
      else { return }
      keys.formUnion(schema.contextQualifierKeys)
    }
  }

  private func validate(
    _ pack: KnowledgePack,
    with schema: KnowledgeDomainProfileSchema,
    profileID: String
  ) -> [KnowledgePackValidationIssue] {
    var issues: [KnowledgePackValidationIssue] = []
    let predicateGroups = Dictionary(
      grouping: schema.predicates, by: \DomainPredicateDefinition.predicate)
    let calculationGroups = Dictionary(
      grouping: schema.calculations, by: \DomainCalculationDefinition.outputPredicate)

    for (predicate, matches) in predicateGroups where matches.count > 1 {
      issues.append(
        error(
          "profile.duplicate_predicate_definition",
          "Domain profile '\(profileID)' defines predicate '\(predicate)' more than once."))
    }

    let namespacePrefix = schema.predicateNamespace + "."
    for assertion in pack.assertions where assertion.predicate.hasPrefix(namespacePrefix) {
      guard let definition = predicateGroups[assertion.predicate]?.first,
        predicateGroups[assertion.predicate]?.count == 1
      else {
        issues.append(
          error(
            "profile.unknown_predicate",
            "Assertion '\(assertion.id)' uses unregistered predicate '\(assertion.predicate)'."))
        continue
      }
      if assertion.value.type != definition.valueType {
        issues.append(
          error(
            "profile.value_type_mismatch",
            "Assertion '\(assertion.id)' must use value type '\(definition.valueType.rawValue)' for '\(assertion.predicate)'."
          ))
      }
      let missingQualifiers = definition.requiredQualifierKeys.subtracting(
        assertion.qualifiers.keys)
      if !missingQualifiers.isEmpty {
        issues.append(
          error(
            "profile.missing_qualifier",
            "Assertion '\(assertion.id)' is missing required qualifier(s): \(missingQualifiers.sorted().joined(separator: ", "))."
          ))
      }
      if !definition.allowedUnits.isEmpty {
        guard let unit = assertion.value.unit, definition.allowedUnits.contains(unit) else {
          issues.append(
            error(
              "profile.invalid_unit",
              "Assertion '\(assertion.id)' must use one of these units: \(definition.allowedUnits.sorted().joined(separator: ", "))."
            ))
          continue
        }
      }
    }

    let assertionsByID = Dictionary(
      pack.assertions.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    for calculation in pack.calculations {
      guard let output = assertionsByID[calculation.outputAssertionID],
        output.predicate.hasPrefix(namespacePrefix)
      else { continue }
      guard let definitions = calculationGroups[output.predicate], !definitions.isEmpty else {
        issues.append(
          error(
            "profile.unknown_calculation",
            "Calculation '\(calculation.id)' targets '\(output.predicate)' without a registered deterministic definition."
          ))
        continue
      }

      let inputPredicates = calculation.inputAssertionIDs.compactMap {
        assertionsByID[$0]?.predicate
      }
      let matches = definitions.contains {
        $0.version == calculation.version
          && normalize($0.expression) == normalize(calculation.expression)
          && $0.inputPredicates == inputPredicates
      }
      if !matches {
        issues.append(
          error(
            "profile.calculation_mismatch",
            "Calculation '\(calculation.id)' does not match a registered version, expression, and ordered input signature for '\(output.predicate)'."
          ))
      }
    }
    return issues
  }

  private func normalize(_ expression: String) -> String {
    expression.filter { !$0.isWhitespace }
  }

  private func error(_ code: String, _ message: String) -> KnowledgePackValidationIssue {
    KnowledgePackValidationIssue(severity: .error, code: code, message: message)
  }
}
