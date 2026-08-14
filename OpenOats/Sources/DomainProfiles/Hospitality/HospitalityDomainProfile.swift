import Foundation
import OpenOatsKit

public struct HospitalityDomainProfile: KnowledgeDomainProfile {
  public let id = "hospitality"
  public let supportedVersions: Set<String> = ["0.1.0"]

  public init() {}

  public func schema(for version: String) -> KnowledgeDomainProfileSchema? {
    guard supportedVersions.contains(version) else { return nil }
    return KnowledgeDomainProfileSchema(
      predicateNamespace: "hospitality",
      predicates: [
        DomainPredicateDefinition(
          predicate: "hospitality.room_revenue",
          label: "Room revenue",
          aliases: ["rooms revenue", "room sales"],
          valueType: .number,
          requiredQualifierKeys: ["period"],
          allowedUnits: ["USD"]
        ),
        DomainPredicateDefinition(
          predicate: "hospitality.available_room_nights",
          label: "Available room nights",
          aliases: ["available rooms", "room nights available"],
          valueType: .number,
          requiredQualifierKeys: ["period"],
          allowedUnits: ["room_night"]
        ),
        DomainPredicateDefinition(
          predicate: "hospitality.revpar",
          label: "Revenue per available room",
          aliases: ["RevPAR", "rev par"],
          valueType: .number,
          requiredQualifierKeys: ["period"],
          allowedUnits: ["USD_per_available_room"]
        ),
      ],
      calculations: [
        DomainCalculationDefinition(
          id: "hospitality.revpar",
          version: "1.0.0",
          expression: "room_revenue / available_room_nights",
          inputPredicates: [
            "hospitality.room_revenue",
            "hospitality.available_room_nights",
          ],
          outputPredicate: "hospitality.revpar"
        )
      ]
    )
  }
}
