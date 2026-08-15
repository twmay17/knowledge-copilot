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
      qualifiers: [
        DomainQualifierDefinition(
          key: "period",
          label: "Reporting year",
          valueType: .year
        ),
        DomainQualifierDefinition(
          key: "current_period",
          label: "Current comparison year",
          valueType: .year
        ),
        DomainQualifierDefinition(
          key: "prior_period",
          label: "Prior comparison year",
          valueType: .year
        ),
        DomainQualifierDefinition(
          key: "scope",
          label: "Metric scope",
          valueType: .text,
          allowedValues: ["asset", "portfolio", "rooms"]
        ),
        DomainQualifierDefinition(
          key: "status",
          label: "Reporting status",
          valueType: .text,
          allowedValues: ["actual", "budget", "forecast"]
        ),
      ],
      predicates: [
        DomainPredicateDefinition(
          predicate: "hospitality.room_count",
          label: "Room count",
          aliases: ["keys", "rooms", "number of rooms"],
          valueType: .number,
          requiredQualifierKeys: ["period", "scope", "status"],
          allowedUnits: ["room"]
        ),
        DomainPredicateDefinition(
          predicate: "hospitality.days_available",
          label: "Days available",
          aliases: ["operating days", "days open"],
          valueType: .number,
          requiredQualifierKeys: ["period", "scope", "status"],
          allowedUnits: ["day"]
        ),
        DomainPredicateDefinition(
          predicate: "hospitality.room_revenue",
          label: "Room revenue",
          aliases: ["rooms revenue", "room sales"],
          valueType: .number,
          requiredQualifierKeys: ["period", "scope", "status"],
          allowedUnits: ["USD"]
        ),
        DomainPredicateDefinition(
          predicate: "hospitality.available_room_nights",
          label: "Available room nights",
          aliases: ["available rooms", "room nights available"],
          valueType: .number,
          requiredQualifierKeys: ["period", "scope", "status"],
          allowedUnits: ["room_night"]
        ),
        DomainPredicateDefinition(
          predicate: "hospitality.rooms_sold",
          label: "Rooms sold",
          aliases: ["occupied room nights", "sold room nights"],
          valueType: .number,
          requiredQualifierKeys: ["period", "scope", "status"],
          allowedUnits: ["room_night"]
        ),
        DomainPredicateDefinition(
          predicate: "hospitality.occupancy",
          label: "Occupancy",
          aliases: ["occupancy rate", "occ"],
          valueType: .number,
          requiredQualifierKeys: ["period", "scope", "status"],
          allowedUnits: ["ratio"]
        ),
        DomainPredicateDefinition(
          predicate: "hospitality.adr",
          label: "Average daily rate",
          aliases: ["ADR", "average room rate"],
          valueType: .number,
          requiredQualifierKeys: ["period", "scope", "status"],
          allowedUnits: ["USD_per_sold_room"]
        ),
        DomainPredicateDefinition(
          predicate: "hospitality.revpar",
          label: "Revenue per available room",
          aliases: ["RevPAR", "rev par"],
          valueType: .number,
          requiredQualifierKeys: ["period", "scope", "status"],
          allowedUnits: ["USD_per_available_room"]
        ),
        DomainPredicateDefinition(
          predicate: "hospitality.food_beverage_revenue",
          label: "Food and beverage revenue",
          aliases: ["F&B revenue", "food beverage sales"],
          valueType: .number,
          requiredQualifierKeys: ["period", "status"],
          allowedUnits: ["USD"]
        ),
        DomainPredicateDefinition(
          predicate: "hospitality.other_revenue",
          label: "Other operated department revenue",
          aliases: ["other revenue", "other department revenue"],
          valueType: .number,
          requiredQualifierKeys: ["period", "status"],
          allowedUnits: ["USD"]
        ),
        DomainPredicateDefinition(
          predicate: "hospitality.total_revenue",
          label: "Total operating revenue",
          aliases: ["total revenue", "gross revenue"],
          valueType: .number,
          requiredQualifierKeys: ["period", "status"],
          allowedUnits: ["USD"]
        ),
        DomainPredicateDefinition(
          predicate: "hospitality.departmental_expense",
          label: "Departmental expense",
          aliases: ["department expenses", "operated department expense"],
          valueType: .number,
          requiredQualifierKeys: ["period", "status"],
          allowedUnits: ["USD"]
        ),
        DomainPredicateDefinition(
          predicate: "hospitality.undistributed_expense",
          label: "Undistributed operating expense",
          aliases: ["undistributed expenses", "undistributed operating costs"],
          valueType: .number,
          requiredQualifierKeys: ["period", "status"],
          allowedUnits: ["USD"]
        ),
        DomainPredicateDefinition(
          predicate: "hospitality.gross_operating_profit",
          label: "Gross operating profit",
          aliases: ["GOP", "gross operating income"],
          valueType: .number,
          requiredQualifierKeys: ["period", "status"],
          allowedUnits: ["USD"]
        ),
        DomainPredicateDefinition(
          predicate: "hospitality.fixed_charges",
          label: "Fixed charges",
          aliases: ["property-level fixed charges", "taxes insurance and reserves"],
          valueType: .number,
          requiredQualifierKeys: ["period", "status"],
          allowedUnits: ["USD"]
        ),
        DomainPredicateDefinition(
          predicate: "hospitality.net_operating_income",
          label: "Net operating income",
          aliases: ["NOI", "net property income"],
          valueType: .number,
          requiredQualifierKeys: ["period", "status"],
          allowedUnits: ["USD"]
        ),
        DomainPredicateDefinition(
          predicate: "hospitality.noi_margin",
          label: "Net operating income margin",
          aliases: ["NOI margin", "net operating margin"],
          valueType: .number,
          requiredQualifierKeys: ["period", "status"],
          allowedUnits: ["ratio"]
        ),
        DomainPredicateDefinition(
          predicate: "hospitality.total_revenue_growth",
          label: "Total revenue growth",
          aliases: ["revenue growth", "year-over-year revenue growth"],
          valueType: .number,
          requiredQualifierKeys: ["current_period", "prior_period", "status"],
          allowedUnits: ["ratio"]
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
          inputUnits: [["room"], ["day"]],
          outputPredicate: "hospitality.available_room_nights",
          outputUnits: ["room_night"],
          operation: .multiply
        ),
        DomainCalculationDefinition(
          id: "hospitality.occupancy",
          version: "1.0.0",
          expression: "rooms_sold / available_room_nights",
          inputPredicates: [
            "hospitality.rooms_sold",
            "hospitality.available_room_nights",
          ],
          inputUnits: [["room_night"], ["room_night"]],
          outputPredicate: "hospitality.occupancy",
          outputUnits: ["ratio"],
          operation: .divide
        ),
        DomainCalculationDefinition(
          id: "hospitality.adr",
          version: "1.0.0",
          expression: "room_revenue / rooms_sold",
          inputPredicates: [
            "hospitality.room_revenue",
            "hospitality.rooms_sold",
          ],
          inputUnits: [["USD"], ["room_night"]],
          outputPredicate: "hospitality.adr",
          outputUnits: ["USD_per_sold_room"],
          operation: .divide
        ),
        DomainCalculationDefinition(
          id: "hospitality.revpar",
          version: "1.0.0",
          expression: "room_revenue / available_room_nights",
          inputPredicates: [
            "hospitality.room_revenue",
            "hospitality.available_room_nights",
          ],
          inputUnits: [["USD"], ["room_night"]],
          outputPredicate: "hospitality.revpar",
          outputUnits: ["USD_per_available_room"],
          operation: .divide
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
          inputUnits: [["USD"], ["USD"], ["USD"]],
          outputPredicate: "hospitality.total_revenue",
          outputUnits: ["USD"],
          operation: .sum
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
          inputUnits: [["USD"], ["USD"], ["USD"]],
          outputPredicate: "hospitality.gross_operating_profit",
          outputUnits: ["USD"],
          operation: .subtract
        ),
        DomainCalculationDefinition(
          id: "hospitality.net_operating_income",
          version: "1.0.0",
          expression: "gross_operating_profit - fixed_charges",
          inputPredicates: [
            "hospitality.gross_operating_profit",
            "hospitality.fixed_charges",
          ],
          inputUnits: [["USD"], ["USD"]],
          outputPredicate: "hospitality.net_operating_income",
          outputUnits: ["USD"],
          operation: .subtract
        ),
        DomainCalculationDefinition(
          id: "hospitality.noi_margin",
          version: "1.0.0",
          expression: "net_operating_income / total_revenue",
          inputPredicates: [
            "hospitality.net_operating_income",
            "hospitality.total_revenue",
          ],
          inputUnits: [["USD"], ["USD"]],
          outputPredicate: "hospitality.noi_margin",
          outputUnits: ["ratio"],
          operation: .divide
        ),
        DomainCalculationDefinition(
          id: "hospitality.total_revenue_growth",
          version: "1.0.0",
          expression: "(current_total_revenue / prior_total_revenue) - 1",
          inputPredicates: [
            "hospitality.total_revenue",
            "hospitality.total_revenue",
          ],
          inputUnits: [["USD"], ["USD"]],
          outputPredicate: "hospitality.total_revenue_growth",
          outputUnits: ["ratio"],
          operation: .growth,
          periodRule: .orderedComparison(
            currentQualifierKey: "current_period",
            priorQualifierKey: "prior_period"
          )
        ),
      ],
      contextQualifierKeys: ["status"]
    )
  }
}
