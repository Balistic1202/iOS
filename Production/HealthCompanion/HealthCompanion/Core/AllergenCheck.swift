import Foundation

/// Looks for a user's confirmed allergens in label text the user has checked.
/// A match can raise a warning. The absence of a match is never an all-clear.
enum AllergenCheck {

    /// Draft English word list. Not reviewed. Not complete.
    static let terms: [Allergen: [String]] = [
        .milk: ["milk", "whey", "casein", "caseinate", "lactose", "butter", "cream", "cheese", "yoghurt", "yogurt"],
        .eggs: ["egg", "albumen", "albumin"],
        .fish: ["fish", "anchovy", "cod", "salmon", "tuna"],
        .shellfish: ["shellfish", "crustacean", "shrimp", "prawn", "crab", "lobster", "crayfish"],
        .treeNuts: ["nut", "almond", "hazelnut", "walnut", "cashew", "pecan", "pistachio", "macadamia", "brazil nut"],
        .peanuts: ["peanut", "groundnut", "arachis"],
        .wheat: ["wheat", "spelt", "semolina", "durum"],
        .soy: ["soy", "soya", "soybean", "edamame", "tofu"],
        .sesame: ["sesame", "tahini"],
    ]

    static let limitation = "Matching uses a short English word list that has not been reviewed. It cannot see ingredients missing from the text, other languages, or unusual names. Always check the package yourself."

    static func check(label: ConfirmedLabel, allergies: AllergyRecord) -> AllergenCheckResult {
        let allergens: [Allergen]
        switch allergies {
        case .notProvided:
            return AllergenCheckResult(
                status: .notChecked, matches: [], gaps: [],
                headline: "Allergy check not run",
                detail: "You have not saved any allergies, so nothing was compared. This says nothing about whether the product suits you.")
        case .noneReported:
            return AllergenCheckResult(
                status: .notChecked, matches: [], gaps: [],
                headline: "Allergy check not run",
                detail: "You reported no allergies, so nothing was compared.")
        case .confirmed(let list):
            if list.isEmpty {
                return check(label: label, allergies: .notProvided)
            }
            allergens = list
        }

        var gaps: [String] = []
        var matches: [AllergenMatch] = []

        if let ingredients = label.ingredients, !ingredients.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            matches += find(allergens, in: ingredients, source: .ingredients)
        } else {
            gaps.append("Ingredients were not provided, so they could not be compared.")
        }

        switch label.precautionary {
        case .notProvided:
            gaps.append("Precautionary statements (such as \"may contain\") were not provided.")
        case .noneOnPackage:
            break
        case .statement(let text):
            matches += find(allergens, in: text, source: .precautionary)
        }

        if !matches.isEmpty {
            let names = orderedUnique(matches.map(\.allergen)).map(\.title).joined(separator: ", ")
            return AllergenCheckResult(
                status: .matchFound, matches: matches, gaps: gaps,
                headline: "Possible match with your allergies: \(names)",
                detail: "The confirmed label text contains words linked to an allergy you saved. Check the package before deciding. " + limitation)
        }
        if !gaps.isEmpty {
            return AllergenCheckResult(
                status: .incomplete, matches: [], gaps: gaps,
                headline: "Allergy check incomplete",
                detail: "Part of the label is missing, so no conclusion is possible. " + limitation)
        }
        return AllergenCheckResult(
            status: .noMatchFound, matches: [], gaps: [],
            headline: "No match found in the text you confirmed",
            detail: "This is not an all-clear. " + limitation)
    }

    static func find(_ allergens: [Allergen], in text: String, source: AllergenMatch.Source) -> [AllergenMatch] {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
        var found: [AllergenMatch] = []
        for allergen in allergens {
            for term in terms[allergen] ?? [] {
                let pattern = "\\b" + NSRegularExpression.escapedPattern(for: term) + "(s|es)?\\b"
                if folded.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                    found.append(AllergenMatch(allergen: allergen, term: term, source: source))
                }
            }
        }
        return found
    }

    private static func orderedUnique(_ items: [Allergen]) -> [Allergen] {
        var seen = Set<Allergen>()
        return items.filter { seen.insert($0).inserted }
    }
}
