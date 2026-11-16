import Foundation

// MARK: - Profile

enum Goal: String, Codable, CaseIterable, Identifiable {
    case reduceSugar, buildMuscle, manageWeight, everydayEnergy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reduceSugar: "Reduce sugar"
        case .buildMuscle: "Build muscle"
        case .manageWeight: "Manage weight"
        case .everydayEnergy: "Support everyday energy"
        }
    }

    var symbol: String {
        switch self {
        case .reduceSugar: "cube"
        case .buildMuscle: "dumbbell"
        case .manageWeight: "scalemass"
        case .everydayEnergy: "bolt"
        }
    }

    /// Nutrients shown first for this goal. A preference for what to look at, not a prescription.
    var focusNutrients: [Nutrient] {
        switch self {
        case .reduceSugar: [.totalSugars, .addedSugars]
        case .buildMuscle: [.protein, .energy]
        case .manageWeight: [.energy]
        case .everydayEnergy: [.energy, .fibre, .totalSugars]
        }
    }
}

enum DietaryPreference: String, Codable, CaseIterable, Identifiable {
    case vegetarian, vegan, pescatarian, halal, kosher, glutenFree, lactoseFree

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vegetarian: "Vegetarian"
        case .vegan: "Vegan"
        case .pescatarian: "Pescatarian"
        case .halal: "Halal"
        case .kosher: "Kosher"
        case .glutenFree: "Gluten-free"
        case .lactoseFree: "Lactose-free"
        }
    }
}

enum Allergen: String, Codable, CaseIterable, Identifiable {
    case milk, eggs, fish, shellfish, treeNuts, peanuts, wheat, soy, sesame

    var id: String { rawValue }

    var title: String {
        switch self {
        case .milk: "Milk"
        case .eggs: "Eggs"
        case .fish: "Fish"
        case .shellfish: "Crustacean shellfish"
        case .treeNuts: "Tree nuts"
        case .peanuts: "Peanuts"
        case .wheat: "Wheat"
        case .soy: "Soy"
        case .sesame: "Sesame"
        }
    }
}

/// "None" and "not provided" are different answers and are stored differently.
enum AllergyRecord: Codable, Equatable {
    case notProvided
    case noneReported
    case confirmed([Allergen])

    var summary: String {
        switch self {
        case .notProvided: "Not provided"
        case .noneReported: "None reported"
        case .confirmed(let list): list.isEmpty ? "Not provided" : list.map(\.title).joined(separator: ", ")
        }
    }
}

struct Profile: Codable, Equatable {
    static let currentConsentVersion = 1

    /// In priority order. The first goal is the current focus.
    var goals: [Goal]
    var dietaryPreferences: [DietaryPreference]
    var allergies: AllergyRecord
    var consentVersion: Int
    var updatedAt: Date

    var primaryGoal: Goal? { goals.first }
}

// MARK: - Label

enum QuantityUnit: String, Codable, CaseIterable, Identifiable {
    case gram = "g"
    case millilitre = "ml"
    var id: String { rawValue }
}

struct Quantity: Codable, Hashable {
    var value: Double
    var unit: QuantityUnit

    var text: String { "\(Fmt.number(value)) \(unit.rawValue)" }
}

enum NutrientBasis: String, Codable, CaseIterable, Identifiable {
    case per100g, per100ml, perServing
    var id: String { rawValue }

    var title: String {
        switch self {
        case .per100g: "per 100 g"
        case .per100ml: "per 100 ml"
        case .perServing: "per serving"
        }
    }
}

enum NutrientUnit: String, Codable, CaseIterable, Identifiable {
    case g, mg, kcal, kJ
    var id: String { rawValue }
}

enum Nutrient: String, Codable, CaseIterable, Identifiable {
    case energy, fat, saturatedFat, carbohydrate, totalSugars, addedSugars, fibre, protein, salt

    var id: String { rawValue }

    var title: String {
        switch self {
        case .energy: "Energy"
        case .fat: "Fat"
        case .saturatedFat: "Saturated fat"
        case .carbohydrate: "Carbohydrate"
        case .totalSugars: "Total sugars"
        case .addedSugars: "Added sugars"
        case .fibre: "Fibre"
        case .protein: "Protein"
        case .salt: "Salt"
        }
    }

    var allowedUnits: [NutrientUnit] { self == .energy ? [.kcal, .kJ] : [.g, .mg] }
    var defaultUnit: NutrientUnit { self == .energy ? .kcal : .g }
}

struct NutrientValue: Codable, Hashable {
    var amount: Double
    var unit: NutrientUnit

    var text: String { "\(Fmt.number(amount)) \(unit.rawValue)" }
}

enum PrecautionaryRecord: Codable, Hashable {
    case notProvided
    case noneOnPackage
    case statement(String)
}

/// A label the user has checked against the package. Missing values are absent, never zero.
struct ConfirmedLabel: Codable, Hashable {
    var productName: String
    var isSample: Bool
    var rawText: String
    var basis: NutrientBasis
    /// Keyed by `Nutrient.rawValue`. A nutrient with no entry is unknown.
    var values: [String: NutrientValue]
    var serving: Quantity?
    var package: Quantity?
    /// `nil` means ingredients were not provided.
    var ingredients: String?
    var precautionary: PrecautionaryRecord
    var confirmedAt: Date

    func value(_ nutrient: Nutrient) -> NutrientValue? { values[nutrient.rawValue] }
}

// MARK: - Portion and calculation

enum Portion: Codable, Equatable {
    case servings(Double)
    case amount(Quantity)

    var text: String {
        switch self {
        case .servings(let n): "\(Fmt.number(n)) serving\(n == 1 ? "" : "s")"
        case .amount(let q): q.text
        }
    }
}

enum PortionBlock: String, Codable, Error {
    case invalidAmount, servingSizeUnknown, massVolumeMismatch

    var explanation: String {
        switch self {
        case .invalidAmount:
            "Enter a portion greater than zero."
        case .servingSizeUnknown:
            "The serving size is not known, so this portion cannot be worked out. Add the serving size from the package."
        case .massVolumeMismatch:
            "Grams and millilitres cannot be converted without knowing the density of this product. Choose a portion in the same unit as the label."
        }
    }
}

struct PortionCalculation: Codable, Equatable {
    var portion: Portion
    /// `nil` when the calculation is blocked.
    var factor: Double?
    var blocked: PortionBlock?
    /// Scaled values for the selected portion. Unknown nutrients stay absent.
    var values: [String: NutrientValue]

    func value(_ nutrient: Nutrient) -> NutrientValue? { values[nutrient.rawValue] }
}

// MARK: - Allergy check

struct AllergenMatch: Codable, Equatable, Identifiable {
    enum Source: String, Codable { case ingredients, precautionary }
    var allergen: Allergen
    var term: String
    var source: Source

    var id: String { "\(allergen.rawValue)-\(term)-\(source.rawValue)" }
}

enum AllergenCheckStatus: String, Codable {
    case notChecked, incomplete, matchFound, noMatchFound
}

struct AllergenCheckResult: Codable, Equatable {
    var status: AllergenCheckStatus
    var matches: [AllergenMatch]
    var gaps: [String]
    var headline: String
    var detail: String
}

// MARK: - Evidence

enum ReviewState: String, Codable {
    case draft, reviewed, unavailable

    var title: String {
        switch self {
        case .draft: "Draft, not reviewed"
        case .reviewed: "Reviewed"
        case .unavailable: "Not available yet"
        }
    }
}

struct EvidenceSource: Codable, Equatable, Identifiable {
    var title: String
    var url: String
    var dateDescription: String
    var id: String { url }
}

struct EvidenceCard: Codable, Equatable, Identifiable {
    var id: String
    var goal: Goal
    var claim: String
    var population: String
    var exclusions: String
    var sources: [EvidenceSource]
    var reviewer: String?
    var state: ReviewState
    var version: String
    var reviewedOn: Date?
    var expiresOn: Date?

    /// Only reviewed, applicable, unexpired cards may back an actionable recommendation.
    func isEligible(for goal: Goal, on date: Date) -> Bool {
        guard state == .reviewed, self.goal == goal, reviewer != nil, reviewedOn != nil,
              let expiresOn, expiresOn > date else { return false }
        return true
    }
}

struct EvidenceCardRef: Codable, Equatable, Identifiable {
    var id: String
    var version: String
    var state: ReviewState
    var claim: String
    var sources: [EvidenceSource]
}

// MARK: - Assessment

struct FactLine: Codable, Equatable, Identifiable {
    var nutrient: Nutrient
    /// `nil` means the label does not state this nutrient.
    var labelValue: NutrientValue?
    var portionValue: NutrientValue?
    var isFocus: Bool
    var id: String { nutrient.rawValue }
}

struct NextStep: Codable, Equatable {
    var text: String
    /// Set only when a reviewed, applicable, unexpired evidence card backs this step.
    var evidenceCardID: String?
}

/// An immutable snapshot. Later profile changes never alter a stored assessment.
struct Assessment: Codable, Equatable, Identifiable {
    let id: UUID
    let createdAt: Date
    let label: ConfirmedLabel
    let calculation: PortionCalculation
    let goal: Goal?
    let goalPriorities: [Goal]
    let summary: [String]
    let facts: [FactLine]
    let missing: [String]
    let allergen: AllergenCheckResult
    let nextStep: NextStep
    let guidanceNote: String
    let ruleVersion: String
    let evidenceCards: [EvidenceCardRef]
}

// MARK: - Saved records

enum DecisionAction: String, Codable, CaseIterable, Identifiable {
    case considering, bought, ate
    var id: String { rawValue }

    var title: String {
        switch self {
        case .considering: "Considering"
        case .bought: "Bought"
        case .ate: "Ate"
        }
    }
}

struct SavedDecision: Codable, Equatable, Identifiable {
    var id: UUID
    var assessmentID: UUID
    var action: DecisionAction
    var timestamp: Date
}

struct CheckIn: Codable, Equatable, Identifiable {
    var id: UUID
    var timestamp: Date
    /// 1 (very low) to 5 (very good), self-reported.
    var energy: Int
    /// 1 (very hard) to 5 (very manageable), self-reported.
    var manageability: Int
    var note: String?
}

struct AppData: Codable, Equatable {
    static let currentSchema = 1

    var schemaVersion = AppData.currentSchema
    var profile: Profile?
    var assessments: [Assessment] = []
    var decisions: [SavedDecision] = []
    var checkIns: [CheckIn] = []

    static let empty = AppData()
}

// MARK: - Formatting

enum Fmt {
    /// Locale-independent number text with at most one decimal place.
    static func number(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() { return String(format: "%.0f", rounded) }
        return String(format: "%.1f", rounded)
    }

    static func date(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
