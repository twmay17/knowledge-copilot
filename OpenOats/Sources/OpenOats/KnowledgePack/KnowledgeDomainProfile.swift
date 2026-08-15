import Foundation

public enum DomainQualifierValueType: String, Equatable, Sendable {
  case text
  case integer
  case number
  case boolean
  case date
  case year
}

public struct DomainQualifierDefinition: Equatable, Sendable {
  public let key: String
  public let label: String
  public let valueType: DomainQualifierValueType
  public let allowedValues: Set<String>

  public init(
    key: String,
    label: String,
    valueType: DomainQualifierValueType,
    allowedValues: Set<String> = []
  ) {
    self.key = key
    self.label = label
    self.valueType = valueType
    self.allowedValues = allowedValues
  }
}

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

public enum DomainCalculationOperation: String, Equatable, Sendable {
  case sum
  case subtract
  case multiply
  case divide
  case growth
}

public enum DomainCalculationPeriodRule: Equatable, Sendable {
  case notApplicable
  case matchingOutput
  case orderedComparison(currentQualifierKey: String, priorQualifierKey: String)
}

public struct DomainCalculationDefinition: Equatable, Sendable {
  public let id: String
  public let version: String
  public let expression: String
  public let inputPredicates: [String]
  public let inputUnits: [Set<String>]
  public let outputPredicate: String
  public let outputUnits: Set<String>
  public let operation: DomainCalculationOperation
  public let periodRule: DomainCalculationPeriodRule

  public init(
    id: String,
    version: String,
    expression: String,
    inputPredicates: [String],
    inputUnits: [Set<String>],
    outputPredicate: String,
    outputUnits: Set<String>,
    operation: DomainCalculationOperation,
    periodRule: DomainCalculationPeriodRule = .matchingOutput
  ) {
    self.id = id
    self.version = version
    self.expression = expression
    self.inputPredicates = inputPredicates
    self.inputUnits = inputUnits
    self.outputPredicate = outputPredicate
    self.outputUnits = outputUnits
    self.operation = operation
    self.periodRule = periodRule
  }
}

public struct KnowledgeDomainProfileSchema: Equatable, Sendable {
  public let predicateNamespace: String
  public let qualifiers: [DomainQualifierDefinition]
  public let predicates: [DomainPredicateDefinition]
  public let calculations: [DomainCalculationDefinition]
  public let contextQualifierKeys: Set<String>

  public init(
    predicateNamespace: String,
    qualifiers: [DomainQualifierDefinition] = [],
    predicates: [DomainPredicateDefinition],
    calculations: [DomainCalculationDefinition] = [],
    contextQualifierKeys: Set<String> = []
  ) {
    self.predicateNamespace = predicateNamespace
    self.qualifiers = qualifiers
    self.predicates = predicates
    self.calculations = calculations
    self.contextQualifierKeys = contextQualifierKeys
  }
}

/// A domain plug-in describes vocabulary, typed qualifiers, and deterministic calculations without
/// gaining access to audio capture, storage permissions, retrieval state, or presentation UI.
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

  /// Resolves one uniquely registered profile schema without exposing the profile implementation.
  public func schema(id: String, version: String) -> KnowledgeDomainProfileSchema? {
    let matches = profiles.filter { $0.id == id }
    guard matches.count == 1, let profile = matches.first,
      profile.supportedVersions.contains(version)
    else { return nil }
    return profile.schema(for: version)
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

      issues.append(contentsOf: validate(schema, profileID: id))
      issues.append(contentsOf: validate(pack, with: schema, profileID: id))
      issues.append(contentsOf: profile.validate(pack, version: version))
    }
    return issues
  }

  /// Returns profile-owned vocabulary as opaque term aliases for the domain-neutral live path.
  public func termAliases(for manifest: KnowledgePackManifest) -> [KnowledgeTermAlias] {
    var aliases: [KnowledgeTermAlias] = []

    for reference in manifest.domainProfiles {
      guard let schema = schema(id: reference.id, version: reference.version) else { continue }
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
    manifest.domainProfiles.reduce(into: Set<String>()) { keys, reference in
      guard let schema = schema(id: reference.id, version: reference.version) else { return }
      keys.formUnion(schema.contextQualifierKeys)
    }
  }

  private func validate(
    _ schema: KnowledgeDomainProfileSchema,
    profileID: String
  ) -> [KnowledgePackValidationIssue] {
    var issues: [KnowledgePackValidationIssue] = []
    let predicateGroups = Dictionary(
      grouping: schema.predicates, by: \DomainPredicateDefinition.predicate)
    let qualifierGroups = Dictionary(
      grouping: schema.qualifiers, by: \DomainQualifierDefinition.key)
    let calculationGroups = Dictionary(
      grouping: schema.calculations,
      by: { "\($0.id)@\($0.version)" }
    )
    let calculationSignatureGroups = Dictionary(
      grouping: schema.calculations,
      by: {
        [
          $0.outputPredicate,
          $0.version,
          normalize($0.expression),
          $0.inputPredicates.joined(separator: ","),
        ].joined(separator: "|")
      }
    )

    if !Self.isNormalizedIdentifier(schema.predicateNamespace) {
      issues.append(
        error(
          "profile.invalid_namespace",
          "Domain profile '\(profileID)' must declare a normalized predicate namespace."))
    }
    for (predicate, matches) in predicateGroups where matches.count > 1 {
      issues.append(
        error(
          "profile.duplicate_predicate_definition",
          "Domain profile '\(profileID)' defines predicate '\(predicate)' more than once."))
    }
    for (key, matches) in qualifierGroups where matches.count > 1 {
      issues.append(
        error(
          "profile.duplicate_qualifier_definition",
          "Domain profile '\(profileID)' defines qualifier '\(key)' more than once."))
    }
    for (key, matches) in calculationGroups where matches.count > 1 {
      issues.append(
        error(
          "profile.duplicate_calculation_definition",
          "Domain profile '\(profileID)' defines calculation '\(key)' more than once."))
    }
    for (_, matches) in calculationSignatureGroups where matches.count > 1 {
      issues.append(
        error(
          "profile.ambiguous_calculation_definition",
          "Domain profile '\(profileID)' defines more than one policy for the same calculation signature."
        ))
    }

    let namespacePrefix = schema.predicateNamespace + "."
    let predicateIDs = Set(predicateGroups.keys)
    let qualifierIDs = Set(qualifierGroups.keys)
    let availableQualifierIDs = qualifierIDs.union(
      KnowledgeAssertionContext.reservedQualifierKeys)
    for definition in schema.qualifiers {
      if !Self.isNormalizedIdentifier(definition.key)
        || definition.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        issues.append(
          error(
            "profile.invalid_qualifier_definition",
            "Domain profile '\(profileID)' qualifier '\(definition.key)' has an invalid key or label."
          ))
      }
      if definition.allowedValues.contains(where: {
        $0.isEmpty || $0 != $0.trimmingCharacters(in: .whitespacesAndNewlines)
      }) {
        issues.append(
          error(
            "profile.invalid_qualifier_definition",
            "Domain profile '\(profileID)' qualifier '\(definition.key)' has a non-normalized allowed value."
          ))
      }
      if definition.allowedValues.contains(where: {
        !Self.isValidQualifierValue($0, definition: definition)
      }) {
        issues.append(
          error(
            "profile.invalid_qualifier_definition",
            "Domain profile '\(profileID)' qualifier '\(definition.key)' has an allowed value that does not match its declared type."
          ))
      }
    }
    for definition in schema.predicates {
      if !definition.predicate.hasPrefix(namespacePrefix)
        || !Self.isNormalizedIdentifier(definition.predicate)
        || definition.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        issues.append(
          error(
            "profile.invalid_predicate_definition",
            "Domain profile '\(profileID)' predicate '\(definition.predicate)' has an invalid ID or label."
          ))
      }
      let undefinedQualifiers = definition.requiredQualifierKeys.subtracting(
        availableQualifierIDs)
      if !undefinedQualifiers.isEmpty {
        issues.append(
          error(
            "profile.undefined_qualifier",
            "Predicate '\(definition.predicate)' requires undefined qualifier(s): \(undefinedQualifiers.sorted().joined(separator: ", "))."
          ))
      }
    }
    let undefinedContextKeys = schema.contextQualifierKeys.subtracting(availableQualifierIDs)
    if !undefinedContextKeys.isEmpty {
      issues.append(
        error(
          "profile.undefined_context_qualifier",
          "Domain profile '\(profileID)' protects undefined qualifier(s): \(undefinedContextKeys.sorted().joined(separator: ", "))."
        ))
    }

    for definition in schema.calculations {
      if !Self.isNormalizedIdentifier(definition.id)
        || definition.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || definition.expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        issues.append(
          error(
            "profile.invalid_calculation_definition",
            "Domain profile '\(profileID)' has an invalid calculation definition '\(definition.id)'."
          ))
      }
      if definition.inputPredicates.isEmpty
        || definition.inputPredicates.count != definition.inputUnits.count
        || definition.inputUnits.contains(where: \.isEmpty)
        || definition.outputUnits.isEmpty
      {
        issues.append(
          error(
            "profile.invalid_calculation_units",
            "Calculation definition '\(definition.id)' must declare one non-empty unit set per input and a non-empty output unit set."
          ))
      }
      let referencedPredicates = Set(definition.inputPredicates + [definition.outputPredicate])
      let undefinedPredicates = referencedPredicates.subtracting(predicateIDs)
      if !undefinedPredicates.isEmpty {
        issues.append(
          error(
            "profile.undefined_calculation_predicate",
            "Calculation definition '\(definition.id)' references undefined predicate(s): \(undefinedPredicates.sorted().joined(separator: ", "))."
          ))
      }
      if definition.inputPredicates.count == definition.inputUnits.count {
        for (predicate, units) in zip(definition.inputPredicates, definition.inputUnits) {
          guard let predicateDefinition = predicateGroups[predicate]?.first,
            predicateGroups[predicate]?.count == 1,
            !predicateDefinition.allowedUnits.isEmpty,
            !units.isSubset(of: predicateDefinition.allowedUnits)
          else { continue }
          issues.append(
            error(
              "profile.incompatible_calculation_units",
              "Calculation definition '\(definition.id)' accepts units outside predicate '\(predicate)' policy."
            ))
        }
      }
      if let outputDefinition = predicateGroups[definition.outputPredicate]?.first,
        predicateGroups[definition.outputPredicate]?.count == 1,
        !outputDefinition.allowedUnits.isEmpty,
        !definition.outputUnits.isSubset(of: outputDefinition.allowedUnits)
      {
        issues.append(
          error(
            "profile.incompatible_calculation_units",
            "Calculation definition '\(definition.id)' output units exceed predicate '\(definition.outputPredicate)' policy."
          ))
      }
      if !Self.hasValidArity(definition) {
        issues.append(
          error(
            "profile.invalid_calculation_arity",
            "Calculation definition '\(definition.id)' has invalid input arity for operation '\(definition.operation.rawValue)'."
          ))
      }
      if case .orderedComparison(let currentKey, let priorKey) = definition.periodRule,
        !qualifierIDs.contains(currentKey) || !qualifierIDs.contains(priorKey)
      {
        issues.append(
          error(
            "profile.undefined_period_qualifier",
            "Calculation definition '\(definition.id)' references undefined comparison-period qualifiers."
          ))
      }
      if case .orderedComparison = definition.periodRule,
        definition.inputPredicates.count != 2
      {
        issues.append(
          error(
            "profile.invalid_period_rule",
            "Calculation definition '\(definition.id)' requires exactly two inputs for an ordered comparison."
          ))
      }
    }
    return issues
  }

  private func validate(
    _ pack: KnowledgePack,
    with schema: KnowledgeDomainProfileSchema,
    profileID: String
  ) -> [KnowledgePackValidationIssue] {
    var issues: [KnowledgePackValidationIssue] = []
    let predicateGroups = Dictionary(
      grouping: schema.predicates, by: \DomainPredicateDefinition.predicate)
    let qualifierGroups = Dictionary(
      grouping: schema.qualifiers, by: \DomainQualifierDefinition.key)
    let calculationGroups = Dictionary(
      grouping: schema.calculations, by: \DomainCalculationDefinition.outputPredicate)

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
      for (key, value) in assertion.qualifiers {
        guard let qualifier = qualifierGroups[key]?.first, qualifierGroups[key]?.count == 1 else {
          continue
        }
        if !Self.isValidQualifierValue(value, definition: qualifier) {
          issues.append(
            error(
              "profile.invalid_qualifier_value",
              "Assertion '\(assertion.id)' qualifier '\(key)' has invalid \(qualifier.valueType.rawValue) value '\(value)'."
            ))
        }
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

      let inputs = calculation.inputAssertionIDs.compactMap { assertionsByID[$0] }
      guard inputs.count == calculation.inputAssertionIDs.count else { continue }
      let inputPredicates = inputs.map(\.predicate)
      guard
        let definition = definitions.first(where: {
          $0.version == calculation.version
            && normalize($0.expression) == normalize(calculation.expression)
            && $0.inputPredicates == inputPredicates
        })
      else {
        issues.append(
          error(
            "profile.calculation_mismatch",
            "Calculation '\(calculation.id)' does not match a registered version, expression, and ordered input signature for '\(output.predicate)'."
          ))
        continue
      }

      issues.append(
        contentsOf: validate(
          calculation,
          definition: definition,
          inputs: inputs,
          output: output
        ))
    }
    return issues
  }

  private func validate(
    _ calculation: KnowledgeCalculation,
    definition: DomainCalculationDefinition,
    inputs: [KnowledgeAssertion],
    output: KnowledgeAssertion
  ) -> [KnowledgePackValidationIssue] {
    var issues: [KnowledgePackValidationIssue] = []
    for (index, pair) in zip(inputs, definition.inputUnits).enumerated() {
      guard let unit = pair.0.value.unit, pair.1.contains(unit) else {
        issues.append(
          error(
            "profile.calculation_input_unit_mismatch",
            "Calculation '\(calculation.id)' input \(index + 1) must use one of these units: \(pair.1.sorted().joined(separator: ", "))."
          ))
        continue
      }
    }
    if output.value.unit.map({ definition.outputUnits.contains($0) }) != true {
      issues.append(
        error(
          "profile.calculation_output_unit_mismatch",
          "Calculation '\(calculation.id)' output must use one of these units: \(definition.outputUnits.sorted().joined(separator: ", "))."
        ))
    }

    issues.append(
      contentsOf: validatePeriods(
        calculation,
        definition: definition,
        inputs: inputs,
        output: output
      ))

    guard let expected = Self.evaluate(definition.operation, inputs: inputs),
      let actualNumber = output.value.number,
      let outputScale = output.value.scale
    else {
      issues.append(
        error(
          "profile.calculation_invalid_arithmetic",
          "Calculation '\(calculation.id)' has missing, non-numeric, or undefined arithmetic inputs."
        ))
      return issues
    }
    let actual = actualNumber * outputScale
    let tolerance = max(1e-8, abs(expected) * 1e-10)
    if abs(expected - actual) > tolerance {
      issues.append(
        error(
          "profile.calculation_result_mismatch",
          "Calculation '\(calculation.id)' stores \(Self.format(actual)) but its registered arithmetic produces \(Self.format(expected))."
        ))
    }
    return issues
  }

  private func validatePeriods(
    _ calculation: KnowledgeCalculation,
    definition: DomainCalculationDefinition,
    inputs: [KnowledgeAssertion],
    output: KnowledgeAssertion
  ) -> [KnowledgePackValidationIssue] {
    switch definition.periodRule {
    case .notApplicable:
      return []
    case .matchingOutput:
      guard let expected = output.qualifiers["period"] else {
        return [
          error(
            "profile.calculation_missing_period",
            "Calculation '\(calculation.id)' output must declare a period.")
        ]
      }
      guard inputs.allSatisfy({ $0.qualifiers["period"] == expected }) else {
        return [
          error(
            "profile.calculation_period_mismatch",
            "Calculation '\(calculation.id)' requires every input and output to use period '\(expected)'."
          )
        ]
      }
    case .orderedComparison(let currentKey, let priorKey):
      guard inputs.count == 2,
        let currentPeriod = inputs[0].qualifiers["period"],
        let priorPeriod = inputs[1].qualifiers["period"],
        currentPeriod != priorPeriod,
        output.qualifiers[currentKey] == currentPeriod,
        output.qualifiers[priorKey] == priorPeriod
      else {
        return [
          error(
            "profile.calculation_period_mismatch",
            "Calculation '\(calculation.id)' requires ordered, distinct current and prior input periods matching output qualifiers '\(currentKey)' and '\(priorKey)'."
          )
        ]
      }
    }
    return []
  }

  private func normalize(_ expression: String) -> String {
    expression.filter { !$0.isWhitespace }
  }

  private static func evaluate(
    _ operation: DomainCalculationOperation,
    inputs: [KnowledgeAssertion]
  ) -> Double? {
    let values = inputs.compactMap { assertion -> Double? in
      guard assertion.value.type == .number,
        let number = assertion.value.number,
        let scale = assertion.value.scale,
        number.isFinite,
        scale.isFinite
      else { return nil }
      return number * scale
    }
    guard values.count == inputs.count else { return nil }

    let result: Double?
    switch operation {
    case .sum:
      result = values.reduce(0, +)
    case .subtract:
      guard let first = values.first else { return nil }
      result = values.dropFirst().reduce(first, -)
    case .multiply:
      result = values.reduce(1, *)
    case .divide:
      guard values.count == 2, values[1] != 0 else { return nil }
      result = values[0] / values[1]
    case .growth:
      guard values.count == 2, values[1] != 0 else { return nil }
      result = (values[0] / values[1]) - 1
    }
    guard result?.isFinite == true else { return nil }
    return result
  }

  private static func hasValidArity(_ definition: DomainCalculationDefinition) -> Bool {
    switch definition.operation {
    case .sum: definition.inputPredicates.count >= 1
    case .subtract, .multiply: definition.inputPredicates.count >= 2
    case .divide, .growth: definition.inputPredicates.count == 2
    }
  }

  private static func isNormalizedIdentifier(_ value: String) -> Bool {
    value.range(of: "^[a-z][a-z0-9_.-]*$", options: .regularExpression) != nil
  }

  private static func isValidQualifierValue(
    _ value: String,
    definition: DomainQualifierDefinition
  ) -> Bool {
    if !definition.allowedValues.isEmpty, !definition.allowedValues.contains(value) { return false }
    switch definition.valueType {
    case .text:
      return !value.isEmpty
    case .integer:
      return Int(value) != nil
    case .number:
      return Double(value)?.isFinite == true
    case .boolean:
      return value == "true" || value == "false"
    case .date:
      guard value.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil
      else { return false }
      let formatter = DateFormatter()
      formatter.calendar = Calendar(identifier: .gregorian)
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      formatter.dateFormat = "yyyy-MM-dd"
      formatter.isLenient = false
      return formatter.date(from: value) != nil
    case .year:
      return value.range(of: "^\\d{4}$", options: .regularExpression) != nil
    }
  }

  private static func format(_ value: Double) -> String {
    String(format: "%.12g", value)
  }

  private func error(_ code: String, _ message: String) -> KnowledgePackValidationIssue {
    KnowledgePackValidationIssue(severity: .error, code: code, message: message)
  }
}
