import Foundation

/// Turns recognised label text into a draft for the user to check.
///
/// This is a helper, not an authority. It fills only what it can read with some confidence and
/// leaves everything else blank, so an unread value stays unknown instead of becoming a guess.
/// The user must still confirm every field against the package.
enum LabelTextParser {

    static func parse(_ text: String) -> LabelDraft {
        var draft = LabelDraft()
        merge(text, into: &draft)
        return draft
    }

    /// Adds text from a further photo. Only blank fields are filled; nothing already present is overwritten.
    /// Any earlier confirmation is cleared, because the label has changed.
    static func merge(_ text: String, into draft: inout LabelDraft) {
        let addition = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !addition.isEmpty else { return }
        draft.rawText = draft.rawText.isEmpty ? addition : draft.rawText + "\n\n" + addition
        draft.checkedNutrition = false
        draft.checkedIngredients = false

        let ingredients = ingredientsBlock(in: addition)
        var nutritionText = addition
        if let ingredients {
            nutritionText.removeSubrange(ingredients.range)
        }

        if draft.basis == nil {
            draft.basis = basis(in: nutritionText)
        }
        for nutrient in Nutrient.allCases where draft[nutrient].text.isEmpty {
            if let found = value(for: nutrient, in: nutritionText) {
                draft[nutrient].text = found.text
                draft[nutrient].unit = found.unit
            }
        }
        if draft.servingText.isEmpty, let serving = serving(in: nutritionText) {
            draft.servingText = serving.text
            draft.servingUnit = serving.unit
        }
        if draft.packageText.isEmpty, let package = package(in: nutritionText) {
            draft.packageText = package.text
            draft.packageUnit = package.unit
        }
        if draft.ingredientsText.isEmpty, let ingredients, !ingredients.text.isEmpty {
            draft.ingredientsText = ingredients.text
            draft.ingredientsUnavailable = false
        }
        if draft.precautionaryMode == .notProvided, let statement = precautionary(in: addition) {
            draft.precautionaryMode = .hasStatement
            draft.precautionaryText = statement
        }
    }

    // MARK: - Basis

    static func basis(in text: String) -> NutrientBasis? {
        let gram = firstRange(#"100\s*g\b"#, in: text)
        let millilitre = firstRange(#"100\s*ml\b"#, in: text)
        switch (gram, millilitre) {
        case let (g?, ml?): return g.lowerBound <= ml.lowerBound ? .per100g : .per100ml
        case (_?, nil): return .per100g
        case (nil, _?): return .per100ml
        case (nil, nil): break
        }
        let perServing = #"per\s+(serving|portion|bar|pack|bottle|can|pot|slice|piece)|serving size|amount per serving"#
        return firstRange(perServing, in: text) == nil ? nil : .perServing
    }

    // MARK: - Nutrients

    private static let number = #"(\d+(?:[.,]\d+)?)"#
    /// What may sit between a nutrient name and its value: a few characters on the same line,
    /// or a value that starts the next line. Commas, semicolons and "<" end the search, so
    /// ingredient lists and "less than" values are never read as amounts.
    private static let gap = #"[^\d\n,;<]{0,14}(?:\n[^\d\na-z,;<]{0,4})?"#

    static func value(for nutrient: Nutrient, in text: String) -> (text: String, unit: NutrientUnit)? {
        switch nutrient {
        case .energy:
            if let kcal = groups(number + #"\s*kcal\b"#, in: text) {
                return (kcal[0], .kcal)
            }
            if let kj = groups(number + #"\s*kj\b"#, in: text) {
                return (kj[0], .kJ)
            }
            if let plain = groups(#"(?:energy|calories)"# + gap + number, in: text) {
                return (plain[0], .kcal)
            }
            return nil
        case .addedSugars:
            if let includes = groups(#"includes\s*"# + number + #"\s*(mg|g)?\s*(?:of\s+)?added\s+sugars?"#, in: text) {
                return (includes[0], massUnit(includes[1]))
            }
            return mass(after: #"added\s+sugars?"#, in: text)
        case .totalSugars:
            return mass(after: #"(?<!added )(?<!added  )(?<!no )(?:total\s+)?sugars?"#, in: text)
        case .fat:
            return mass(after: #"(?<!saturated )(?<!trans )(?:total\s+)?fat\b"#, in: text)
        case .saturatedFat:
            return mass(after: #"saturate[sd]?(?:\s+fat)?"#, in: text)
        case .carbohydrate:
            return mass(after: #"carbohydrates?|carbs\b"#, in: text)
        case .fibre:
            return mass(after: #"fibre|fiber"#, in: text)
        case .protein:
            return mass(after: #"proteins?"#, in: text)
        case .salt:
            return mass(after: #"\bsalt\b"#, in: text)
        }
    }

    private static func mass(after name: String, in text: String) -> (text: String, unit: NutrientUnit)? {
        guard let found = groups("(?:" + name + ")" + gap + number + #"\s*(mg|kcal|kj|g)?\b"#, in: text) else { return nil }
        let unit = found[1].lowercased()
        if unit == "kcal" || unit == "kj" { return nil }
        return (found[0], massUnit(found[1]))
    }

    private static func massUnit(_ text: String) -> NutrientUnit {
        text.lowercased() == "mg" ? .mg : .g
    }

    // MARK: - Sizes

    static func serving(in text: String) -> (text: String, unit: QuantityUnit)? {
        let patterns = [
            #"serving(?:\s+size)?[^\n]{0,30}?\("# + number + #"\s*(g|ml)\)"#,
            #"serving(?:\s+size)?[^\d\n]{0,20}"# + number + #"\s*(g|ml)\b"#,
            number + #"\s*(g|ml)\s+serving"#,
        ]
        for pattern in patterns {
            if let found = groups(pattern, in: text) {
                return (found[0], found[1].lowercased() == "ml" ? .millilitre : .gram)
            }
        }
        return nil
    }

    static func package(in text: String) -> (text: String, unit: QuantityUnit)? {
        let pattern = #"net\s*(?:weight|wt\.?|contents?|quantity)[^\d\n]{0,10}"# + number + #"\s*(kg|g|ml|cl|l)\b"#
        guard let found = groups(pattern, in: text) else { return nil }
        let unit = found[1].lowercased()
        let multiplier: Double? = ["kg": 1000, "l": 1000, "cl": 10][unit]
        let quantityUnit: QuantityUnit = (unit == "g" || unit == "kg") ? .gram : .millilitre
        guard let multiplier else { return (found[0], quantityUnit) }
        guard case .value(let amount) = DecimalParsing.parse(found[0]) else { return nil }
        return (Fmt.number(amount * multiplier), quantityUnit)
    }

    // MARK: - Ingredients and precautionary statements

    static func ingredientsBlock(in text: String) -> (text: String, range: Range<String.Index>)? {
        guard let keyword = firstRange(#"\bingredients?\b[\s:.]*"#, in: text) else { return nil }
        let rest = String(text[keyword.upperBound...])
        let stop = #"\n\s*(?=nutrition|typical values|energy|per 100|serving|net (?:weight|wt|contents)|may (?:also )?contain|allerg|storage|store |best before|use by|produced in|made in|packed in|manufactured in|contains[: ])"#
        let end = firstRange(stop, in: rest).map { found -> String.Index in
            text.index(keyword.upperBound, offsetBy: rest.distance(from: rest.startIndex, to: found.lowerBound))
        } ?? text.endIndex
        return (collapse(String(text[keyword.upperBound..<end])), keyword.lowerBound..<end)
    }

    static func precautionary(in text: String) -> String? {
        let pattern = #"(?:may (?:also )?contain|(?:produced|made|packed|manufactured) in an? (?:factory|facility|environment|site))[^.]{0,160}\.?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let statements = matches.compactMap { Range($0.range, in: text).map { collapse(String(text[$0])) } }
        return statements.isEmpty ? nil : statements.joined(separator: " ")
    }

    // MARK: - Regex helpers

    private static func collapse(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func firstRange(_ pattern: String, in text: String) -> Range<String.Index>? {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive])
    }

    /// Capture groups of the first match. Groups that did not take part come back as empty text.
    private static func groups(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
}
