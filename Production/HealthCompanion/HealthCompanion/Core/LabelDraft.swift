import Foundation

/// The editable form of a label. Text fields stay as text so that blank (unknown) and "0" (zero) remain different.
struct LabelDraft: Equatable {
    struct Entry: Equatable {
        var text: String = ""
        var unit: NutrientUnit
    }

    enum PrecautionaryMode: String, CaseIterable, Identifiable {
        case notProvided, noneOnPackage, hasStatement
        var id: String { rawValue }

        var title: String {
            switch self {
            case .notProvided: "Not checked"
            case .noneOnPackage: "None on package"
            case .hasStatement: "Has a statement"
            }
        }
    }

    var productName = ""
    var isSample = false
    var rawText = ""
    var basis: NutrientBasis?
    var entries: [Nutrient: Entry] = Dictionary(uniqueKeysWithValues: Nutrient.allCases.map { ($0, Entry(unit: $0.defaultUnit)) })
    var servingText = ""
    var servingUnit: QuantityUnit = .gram
    var packageText = ""
    var packageUnit: QuantityUnit = .gram
    var ingredientsText = ""
    var ingredientsUnavailable = false
    var precautionaryMode: PrecautionaryMode = .notProvided
    var precautionaryText = ""
    var checkedNutrition = false
    var checkedIngredients = false

    subscript(nutrient: Nutrient) -> Entry {
        get { entries[nutrient] ?? Entry(unit: nutrient.defaultUnit) }
        set { entries[nutrient] = newValue }
    }

    /// Problems that must be fixed before the label can be confirmed.
    var issues: [String] {
        var list: [String] = []
        if basis == nil {
            list.append("Choose what the values refer to: per 100 g, per 100 ml or per serving.")
        }
        for nutrient in Nutrient.allCases where DecimalParsing.parse(self[nutrient].text) == .invalid {
            list.append("\(nutrient.title) is not a number. Leave it blank if the label does not state it.")
        }
        if DecimalParsing.parse(servingText) == .invalid {
            list.append("Serving size is not a number. Leave it blank if unknown.")
        }
        if DecimalParsing.parse(packageText) == .invalid {
            list.append("Package size is not a number. Leave it blank if unknown.")
        }
        let hasIngredients = !ingredientsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !hasIngredients && !ingredientsUnavailable {
            list.append("Enter the ingredients, or mark them as not available.")
        }
        if precautionaryMode == .hasStatement && precautionaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            list.append("Enter the precautionary statement, or change its setting.")
        }
        if !checkedNutrition {
            list.append("Confirm that you checked the nutrition values against the package.")
        }
        if !checkedIngredients {
            list.append("Confirm that you checked ingredients and allergy statements against the package.")
        }
        return list
    }

    /// Returns a confirmed label only when there are no outstanding issues.
    func confirmed(now: Date = .now) -> ConfirmedLabel? {
        guard issues.isEmpty, let basis else { return nil }

        var values: [String: NutrientValue] = [:]
        for nutrient in Nutrient.allCases {
            if case .value(let amount) = DecimalParsing.parse(self[nutrient].text) {
                values[nutrient.rawValue] = NutrientValue(amount: amount, unit: self[nutrient].unit)
            }
        }

        func quantity(_ text: String, _ unit: QuantityUnit) -> Quantity? {
            if case .value(let amount) = DecimalParsing.parse(text), amount > 0 {
                return Quantity(value: amount, unit: unit)
            }
            return nil
        }

        let ingredients = ingredientsText.trimmingCharacters(in: .whitespacesAndNewlines)
        let precautionary: PrecautionaryRecord
        switch precautionaryMode {
        case .notProvided: precautionary = .notProvided
        case .noneOnPackage: precautionary = .noneOnPackage
        case .hasStatement: precautionary = .statement(precautionaryText.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let name = productName.trimmingCharacters(in: .whitespacesAndNewlines)
        return ConfirmedLabel(
            productName: name.isEmpty ? "Unnamed product" : name,
            isSample: isSample,
            rawText: rawText,
            basis: basis,
            values: values,
            serving: quantity(servingText, servingUnit),
            package: quantity(packageText, packageUnit),
            ingredients: (ingredientsUnavailable || ingredients.isEmpty) ? nil : ingredients,
            precautionary: precautionary,
            confirmedAt: now)
    }
}

/// Invented products for trying the flow. Always shown with a visible "Sample" label.
enum SampleProducts {
    static var all: [LabelDraft] { [granola, yoghurtDrink, proteinBar] }

    static var granola: LabelDraft {
        var d = LabelDraft()
        d.productName = "Sample: Oat and Honey Granola"
        d.isSample = true
        d.rawText = """
        NUTRITION per 100 g
        Energy 450 kcal
        Fat 15 g, of which saturates 3,0 g
        Carbohydrate 62 g, of which sugars 24 g
        Fibre 7 g
        Protein 10 g
        Salt 0,3 g
        Serving 45 g. Net weight 500 g.
        INGREDIENTS: Oats (58%), sugar, sunflower oil, honey (5%), almonds (4%), coconut, salt.
        May contain peanuts, other nuts and sesame.
        """
        d.basis = .per100g
        d[.energy].text = "450"
        d[.fat].text = "15"
        d[.saturatedFat].text = "3,0"
        d[.carbohydrate].text = "62"
        d[.totalSugars].text = "24"
        d[.fibre].text = "7"
        d[.protein].text = "10"
        d[.salt].text = "0,3"
        d.servingText = "45"
        d.packageText = "500"
        d.ingredientsText = "Oats (58%), sugar, sunflower oil, honey (5%), almonds (4%), coconut, salt."
        d.precautionaryMode = .hasStatement
        d.precautionaryText = "May contain peanuts, other nuts and sesame."
        return d
    }

    static var yoghurtDrink: LabelDraft {
        var d = LabelDraft()
        d.productName = "Sample: High-Protein Yoghurt Drink"
        d.isSample = true
        d.rawText = """
        NUTRITION per 100 ml
        Energy 60 kcal
        Fat 0.5 g
        Carbohydrate 5.0 g, of which sugars 4.8 g
        Added sugars 0 g
        Protein 8.0 g
        Salt 0.1 g
        Bottle 330 ml (1 serving)
        INGREDIENTS: Skimmed milk, milk protein, live cultures.
        """
        d.basis = .per100ml
        d[.energy].text = "60"
        d[.fat].text = "0.5"
        d[.carbohydrate].text = "5.0"
        d[.totalSugars].text = "4.8"
        d[.addedSugars].text = "0"
        d[.protein].text = "8.0"
        d[.salt].text = "0.1"
        d.servingText = "330"
        d.servingUnit = .millilitre
        d.packageText = "330"
        d.packageUnit = .millilitre
        d.ingredientsText = "Skimmed milk, milk protein, live cultures."
        d.precautionaryMode = .noneOnPackage
        return d
    }

    static var proteinBar: LabelDraft {
        var d = LabelDraft()
        d.productName = "Sample: Protein Bar"
        d.isSample = true
        d.rawText = """
        NUTRITION per bar (1 serving)
        Energy 210 kcal
        Fat 8 g
        Sugars 2 g
        Protein 20 g
        (bar weight not legible)
        INGREDIENTS: Milk protein, soy protein isolate, peanuts, cocoa butter, sweetener (maltitol).
        """
        d.basis = .perServing
        d[.energy].text = "210"
        d[.fat].text = "8"
        d[.totalSugars].text = "2"
        d[.protein].text = "20"
        d.ingredientsText = "Milk protein, soy protein isolate, peanuts, cocoa butter, sweetener (maltitol)."
        d.precautionaryMode = .notProvided
        return d
    }
}
