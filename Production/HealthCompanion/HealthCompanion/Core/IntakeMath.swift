import Foundation

/// Adds up portion figures from saved assessments. Used only for items the user saved as "Ate".
///
/// Unknown is never zero: an item that does not state a nutrient for its portion is counted as
/// unknown, and a total exists only when at least one item states a value.
struct IntakeSummary: Equatable {
    var itemCount = 0
    /// Energy in kcal, everything else in grams.
    var totals: [Nutrient: Double] = [:]
    /// How many items had no portion figure for this nutrient.
    var unknown: [Nutrient: Int] = [:]

    func total(_ nutrient: Nutrient) -> Double? { totals[nutrient] }
    func unknownCount(_ nutrient: Nutrient) -> Int { unknown[nutrient] ?? 0 }
}

enum IntakeMath {
    static let kilojoulesPerKilocalorie = 4.184

    /// The value in the summary's unit: kcal for energy, grams for everything else.
    static func normalised(_ value: NutrientValue) -> Double {
        switch value.unit {
        case .kcal, .g: value.amount
        case .kJ: value.amount / kilojoulesPerKilocalorie
        case .mg: value.amount / 1000
        }
    }

    static func summary(of assessments: [Assessment]) -> IntakeSummary {
        var summary = IntakeSummary(itemCount: assessments.count)
        for assessment in assessments {
            for nutrient in Nutrient.allCases {
                if let value = assessment.calculation.value(nutrient) {
                    summary.totals[nutrient, default: 0] += normalised(value)
                } else {
                    summary.unknown[nutrient, default: 0] += 1
                }
            }
        }
        return summary
    }
}

extension AppStore {
    /// Assessments the user saved as "Ate" on the given day. Scans saved any other way are not included.
    func eaten(on day: Date, calendar: Calendar = .current) -> [Assessment] {
        data.decisions
            .filter { $0.action == .ate && calendar.isDate($0.timestamp, inSameDayAs: day) }
            .compactMap(assessment(for:))
    }

    func hasSavedDecision(on day: Date, calendar: Calendar = .current) -> Bool {
        data.decisions.contains { calendar.isDate($0.timestamp, inSameDayAs: day) }
    }
}
