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
          predicate: "hospitality.room_count",
          label: "Room count",
          aliases: ["keys", "rooms", "number of rooms"],
          valueType: .number,
          requiredQualifierKeys: ["period"],
          allowedUnits: ["room"]
        ),
        DomainPredicateDefinition(
          predicate: "hospitality.days_available",
          label: "Days available",
          aliases: ["operating days", "days open"],
          valueType: .number,
          requiredQualifierKeys: ["period"],
          allowedUnits: ["day"]
        ),
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
          predicate: "hospitality.rooms_sold",
          label: "Rooms sold",
          aliases: ["occupied room nights", "sold room nights"],
          valueType: .number,
          requiredQualifierKeys: ["period"],
          allowedUnits: ["room_night"]
        ),
        DomainPredicateDefinition(
          predicate: "hospitality.occupancy",
          label: "Occupancy",
          aliases: ["occupancy rate", "occ"],
          valueType: .number,
          requiredQualifierKeys: ["period"],
          allowedUnits: ["ratio"]
        ),
        DomainPredicateDefinition(
          predicate: "hospitality.adr",
          label: "Average daily rate",
          aliases: ["ADR", "average room rate"],
          valueType: .number,
          requiredQualifierKeys: ["period"],
          allowedUnits: ["USD_per_sold_room"]
        ),
        DomainPredicateDefinition(
          predicate: "hospitality.revpar",
          label: "Revenue per available room",
          aliases: ["RevPAR", "rev par"],
          valueType: .number,
          requiredQualifierKeys: ["period"],
          allowedUnits: ["USD_per_available_room"]
        ),
        DomainPredicateDefinition(
          predicate: "hospitality.food_beverage_revenue",
          label: "Food and beverage revenue",
          aliases: ["F&B revenue", "food beverage sales"],
          valueType: .number,
          requiredQualifierKeys: ["period"],
          allowedUnits: ["USD"]
        ),
        DomainPredicateDefinition(
          predicate: "hospitality.other_revenue",
          label: "Other operated department revenue",
          aliases: ["other revenue", "other department revenue"],
          valueType: .number,
          requiredQualifierKeys: ["period"],
          allowedUnits: ["USD"]
        ),
        DomainPredicateDefinition(
          predicate: "hospitality.total_revenue",
          label: "Total operating revenue",
          aliases: ["total revenue", "gross revenue"],
          valueType: .number,
          requiredQualifierKeys: ["period"],
          allowedUnits: ["USD"]
        ),
        DomainPredicateDefinition(
          predicate: "hospitality.departmental_expense",
          label: "Departmental expense",
          aliases: ["department expenses", "operated department expense"],
          valueType: .number,
          requiredQualifierKeys: ["period"],
          allowedUnits: ["USD"]
        ),
        DomainPredicateDefinition(
          predicate: "hospitality.undistributed_expense",
          label: "Undistributed operating expense",
          aliases: ["undistributed expenses", "undistributed operating costs"],
          valueType: .number,
          requiredQualifierKeys: ["period"],
          allowedUnits: ["USD"]
        ),
        DomainPredicateDefinition(
          predicate: "hospitality.gross_operating_profit",
          label: "Gross operating profit",
          aliases: ["GOP", "gross operating income"],
          valueType: .number,
          requiredQualifierKeys: ["period"],
          allowedUnits: ["USD"]
        ),
      ],
      calculations: [
        DomainCalculationDefinition(
          id: "hospitality.available_room_nights",
          version: "1.0.0",
          expression: "room_count * days_available",
          inputPredicates: [
            "hospitality.room_count",
            "hospitality.days_available",
          ],
          outputPredicate: "hospitality.available_room_nights"
        ),
        DomainCalculationDefinition(
          id: "hospitality.occupancy",
          version: "1.0.0",
          expression: "rooms_sold / available_room_nights",
          inputPredicates: [
            "hospitality.rooms_sold",
            "hospitality.available_room_nights",
          ],
          outputPredicate: "hospitality.occupancy"
        ),
        DomainCalculationDefinition(
          id: "hospitality.adr",
          version: "1.0.0",
          expression: "room_revenue / rooms_sold",
          inputPredicates: [
            "hospitality.room_revenue",
            "hospitality.rooms_sold",
          ],
          outputPredicate: "hospitality.adr"
        ),
        DomainCalculationDefinition(
          id: "hospitality.revpar",
          version: "1.0.0",
          expression: "room_revenue / available_room_nights",
          inputPredicates: [
            "hospitality.room_revenue",
            "hospitality.available_room_nights",
          ],
          outputPredicate: "hospitality.revpar"
        ),
        DomainCalculationDefinition(
          id: "hospitality.total_revenue",
          version: "1.0.0",
          expression: "room_revenue + food_beverage_revenue + other_revenue",
          inputPredicates: [
            "hospitality.room_revenue",
            "hospitality.food_beverage_revenue",
            "hospitality.other_revenue",
          ],
          outputPredicate: "hospitality.total_revenue"
        ),
        DomainCalculationDefinition(
          id: "hospitality.gross_operating_profit",
          version: "1.0.0",
          expression: "total_revenue - departmental_expense - undistributed_expense",
          inputPredicates: [
            "hospitality.total_revenue",
            "hospitality.departmental_expense",
            "hospitality.undistributed_expense",
          ],
          outputPredicate: "hospitality.gross_operating_profit"
        ),
      ]
    )
  }
}
