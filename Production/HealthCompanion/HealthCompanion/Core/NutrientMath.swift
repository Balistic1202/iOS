import Foundation

/// Deterministic portion arithmetic. No density guesses, no silent unit conversion.
enum NutrientMath {

    /// The multiplier that turns label values into values for the selected portion.
    static func factor(basis: NutrientBasis, serving: Quantity?, portion: Portion) -> Result<Double, PortionBlock> {
        switch portion {
        case .servings(let count):
            guard count.isFinite, count > 0 else { return .failure(.invalidAmount) }
            switch basis {
            case .perServing:
                return .success(count)
            case .per100g:
                return perHundred(count: count, serving: serving, labelUnit: .gram)
            case .per100ml:
                return perHundred(count: count, serving: serving, labelUnit: .millilitre)
            }

        case .amount(let quantity):
            guard quantity.value.isFinite, quantity.value > 0 else { return .failure(.invalidAmount) }
            switch basis {
            case .per100g:
                return quantity.unit == .gram ? .success(quantity.value / 100) : .failure(.massVolumeMismatch)
            case .per100ml:
                return quantity.unit == .millilitre ? .success(quantity.value / 100) : .failure(.massVolumeMismatch)
            case .perServing:
                guard let serving, serving.value > 0 else { return .failure(.servingSizeUnknown) }
                guard serving.unit == quantity.unit else { return .failure(.massVolumeMismatch) }
                return .success(quantity.value / serving.value)
            }
        }
    }

    private static func perHundred(count: Double, serving: Quantity?, labelUnit: QuantityUnit) -> Result<Double, PortionBlock> {
        guard let serving, serving.value > 0 else { return .failure(.servingSizeUnknown) }
        guard serving.unit == labelUnit else { return .failure(.massVolumeMismatch) }
        return .success(count * serving.value / 100)
    }

    /// Scales every known label value. Unknown nutrients stay unknown.
    static func calculate(label: ConfirmedLabel, portion: Portion) -> PortionCalculation {
        switch factor(basis: label.basis, serving: label.serving, portion: portion) {
        case .success(let factor):
            let scaled = label.values.mapValues { NutrientValue(amount: $0.amount * factor, unit: $0.unit) }
            return PortionCalculation(portion: portion, factor: factor, blocked: nil, values: scaled)
        case .failure(let block):
            return PortionCalculation(portion: portion, factor: nil, blocked: block, values: [:])
        }
    }
}

/// Parses numbers typed from a label. Accepts a decimal comma. Empty text is "unknown", not zero.
enum DecimalParsing {
    enum Parsed: Equatable {
        case unknown
        case value(Double)
        case invalid
    }

    static func parse(_ text: String) -> Parsed {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .unknown }
        let normalised = trimmed.replacingOccurrences(of: ",", with: ".")
        let allowed = CharacterSet(charactersIn: "0123456789.")
        guard normalised.unicodeScalars.allSatisfy(allowed.contains),
              normalised.filter({ $0 == "." }).count <= 1,
              let number = Double(normalised), number.isFinite, number >= 0 else { return .invalid }
        return .value(number)
    }
}
