import Foundation

/// Evidence cards. Everything here is a draft or unavailable until a qualified reviewer signs it off.
enum EvidenceLibrary {
    static let drafts: [EvidenceCard] = [
        EvidenceCard(
            id: "sugar-free-sugars", goal: .reduceSugar,
            claim: "Draft topic: limiting free sugars.",
            population: "Adults", exclusions: "Not yet defined",
            sources: [EvidenceSource(title: "WHO guideline: sugars intake for adults and children",
                                     url: "https://www.who.int/publications/i/item/9789241549028",
                                     dateDescription: "Published 4 March 2015. Research backlog, not verified for this app.")],
            reviewer: nil, state: .draft, version: "0.1", reviewedOn: nil, expiresOn: nil),
        EvidenceCard(
            id: "muscle-protein", goal: .buildMuscle,
            claim: "Draft topic: protein intake alongside resistance training.",
            population: "Healthy adults", exclusions: "Not yet defined",
            sources: [EvidenceSource(title: "Morton et al., Br J Sports Med 2018",
                                     url: "https://doi.org/10.1136/bjsports-2017-097608",
                                     dateDescription: "Published 2018. Research backlog, not verified for this app.")],
            reviewer: nil, state: .draft, version: "0.1", reviewedOn: nil, expiresOn: nil),
        EvidenceCard(
            id: "weight-gradual", goal: .manageWeight,
            claim: "Draft topic: gradual weight change.",
            population: "Adults", exclusions: "Not yet defined",
            sources: [EvidenceSource(title: "CDC: Steps for Losing Weight",
                                     url: "https://www.cdc.gov/healthy-weight-growth/losing-weight/index.html",
                                     dateDescription: "Page dated 17 January 2025. Research backlog, not verified for this app.")],
            reviewer: nil, state: .draft, version: "0.1", reviewedOn: nil, expiresOn: nil),
        EvidenceCard(
            id: "energy-everyday", goal: .everydayEnergy,
            claim: "No card has been drafted for this goal.",
            population: "Adults", exclusions: "Not yet defined",
            sources: [], reviewer: nil, state: .unavailable, version: "0.0", reviewedOn: nil, expiresOn: nil),
    ]
}

/// Builds an assessment from structured facts and fixed templates. No model-generated text.
enum AssessmentEngine {
    static let ruleVersion = "rules-0.1"

    static let noGuidanceNote = "Reviewed guidance is not available yet for this goal, so this shows label facts only. Nothing here is clinically reviewed advice."

    static func assess(
        label: ConfirmedLabel,
        profile: Profile?,
        portion: Portion,
        library: [EvidenceCard] = EvidenceLibrary.drafts,
        now: Date = .now,
        id: UUID = UUID()
    ) -> Assessment {
        let goal = profile?.primaryGoal
        let calculation = NutrientMath.calculate(label: label, portion: portion)
        let allergen = AllergenCheck.check(label: label, allergies: profile?.allergies ?? .notProvided)
        let focus = goal?.focusNutrients ?? []

        let facts = Nutrient.allCases.map { nutrient in
            FactLine(nutrient: nutrient,
                     labelValue: label.value(nutrient),
                     portionValue: calculation.value(nutrient),
                     isFocus: focus.contains(nutrient))
        }

        let cards = library.filter { $0.goal == goal }
        let eligible = goal.flatMap { goal in cards.first { $0.isEligible(for: goal, on: now) } }
        let note = eligible.map { "Backed by a reviewed evidence card (version \($0.version))." } ?? noGuidanceNote

        return Assessment(
            id: id,
            createdAt: now,
            label: label,
            calculation: calculation,
            goal: goal,
            goalPriorities: profile?.goals ?? [],
            summary: summary(label: label, calculation: calculation, goal: goal),
            facts: facts,
            missing: missing(label: label, calculation: calculation, focus: focus),
            allergen: allergen,
            nextStep: nextStep(label: label, calculation: calculation, focus: focus, eligible: eligible),
            guidanceNote: note,
            ruleVersion: ruleVersion,
            evidenceCards: cards.map {
                EvidenceCardRef(id: $0.id, version: $0.version, state: $0.state, claim: $0.claim, sources: $0.sources)
            })
    }

    // MARK: Templates

    static func summary(label: ConfirmedLabel, calculation: PortionCalculation, goal: Goal?) -> [String] {
        var lines: [String] = []
        let basis = label.basis.title

        func stated(_ nutrient: Nutrient) -> String {
            if let value = label.value(nutrient) {
                return "\(nutrient.title): \(value.text) \(basis), as stated on the label."
            }
            return "\(nutrient.title): not stated on the confirmed label."
        }

        switch goal {
        case .reduceSugar:
            lines.append(stated(.totalSugars))
            if let added = label.value(.addedSugars) {
                lines.append("Added sugars: \(added.text) \(basis), as stated on the label.")
            } else {
                lines.append("The label does not state added sugars. Total sugars include sugars naturally present in ingredients, so they cannot be compared with guidance about added or free sugars.")
            }
        case .buildMuscle:
            lines.append(stated(.protein))
            lines.append(stated(.energy))
        case .manageWeight:
            lines.append(stated(.energy))
        case .everydayEnergy:
            lines.append(stated(.energy))
            lines.append(stated(.fibre))
            lines.append(stated(.totalSugars))
        case nil:
            lines.append("No goal is selected, so this shows label facts only.")
        }

        if let block = calculation.blocked {
            lines.append("Portion figures are not shown. \(block.explanation)")
        } else if let goal, let first = goal.focusNutrients.first, let scaled = calculation.value(first) {
            lines.append("In the portion you selected (\(calculation.portion.text)): \(first.title.lowercased()) \(scaled.text).")
        }
        return lines
    }

    static func missing(label: ConfirmedLabel, calculation: PortionCalculation, focus: [Nutrient]) -> [String] {
        var items: [String] = []
        for nutrient in focus where label.value(nutrient) == nil {
            items.append("\(nutrient.title) is not on the confirmed label. It is unknown, not zero.")
        }
        let others = Nutrient.allCases.filter { !focus.contains($0) && label.value($0) == nil }
        if !others.isEmpty {
            items.append("Also not stated: \(others.map { $0.title.lowercased() }.joined(separator: ", ")).")
        }
        if label.serving == nil {
            items.append("Serving size is not known.")
        }
        if label.ingredients == nil {
            items.append("Ingredients were not provided.")
        }
        if label.precautionary == .notProvided {
            items.append("Precautionary allergy statements were not provided.")
        }
        if let block = calculation.blocked {
            items.append(block.explanation)
        }
        if label.isSample {
            items.append("This is an invented sample product, not a real label.")
        }
        return items
    }

    static func nextStep(label: ConfirmedLabel, calculation: PortionCalculation, focus: [Nutrient], eligible: EvidenceCard?) -> NextStep {
        if let eligible {
            return NextStep(text: eligible.claim, evidenceCardID: eligible.id)
        }
        if calculation.blocked == .servingSizeUnknown {
            return NextStep(text: "Look for the serving size on the package and add it, so portion figures can be worked out.", evidenceCardID: nil)
        }
        if calculation.blocked == .massVolumeMismatch {
            return NextStep(text: "Choose a portion in the same unit as the label to see portion figures.", evidenceCardID: nil)
        }
        if let gap = focus.first(where: { label.value($0) == nil }) {
            return NextStep(text: "Check the package for \(gap.title.lowercased()). If it is printed there, add it to the label details.", evidenceCardID: nil)
        }
        return NextStep(text: "To compare this with another product, look at both on the same basis (\(label.basis.title)).", evidenceCardID: nil)
    }
}
