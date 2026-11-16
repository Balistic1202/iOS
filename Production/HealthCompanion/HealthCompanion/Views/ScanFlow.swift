import SwiftUI

/// Capture, confirm, then assess. Nothing is stored unless the user saves a decision at the end.
struct ScanFlow: View {
    enum Route: Hashable {
        case confirm
        case assessment(ConfirmedLabel)
    }

    @Environment(\.dismiss) private var dismiss
    @State private var path: [Route] = []
    @State private var draft = LabelDraft()

    var body: some View {
        NavigationStack(path: $path) {
            CaptureView { chosen in
                draft = chosen
                path = [.confirm]
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .confirm:
                    ConfirmLabelView(draft: $draft) { confirmed in
                        // The label travels with the route, so the destination never reads stale state.
                        path.append(.assessment(confirmed))
                    }
                case .assessment(let label):
                    AssessmentScreen(label: label) { dismiss() }
                }
            }
        }
    }
}

// MARK: - Capture

struct CaptureView: View {
    let onChoose: (LabelDraft) -> Void

    var body: some View {
        List {
            Section {
                Text("In this prototype, label details are handled on this device only. Photos are not kept, and nothing is sent anywhere.")
            } header: {
                Text("How your label is handled")
            }

            Section {
                Label("Photograph a label", systemImage: "camera")
                    .foregroundStyle(.secondary)
                Label("Import a photo", systemImage: "photo")
                    .foregroundStyle(.secondary)
            } header: {
                Text("From the package")
            } footer: {
                Text("Camera and photo import are not built yet. They arrive in the next step, with on-device text recognition.")
            }

            Section {
                ForEach(Array(SampleProducts.all.enumerated()), id: \.offset) { _, sample in
                    Button {
                        onChoose(sample)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sample.productName)
                            Text("Values \(sample.basis?.title ?? "")")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Try a sample")
            } footer: {
                SampleBadge()
            }

            Section {
                Button {
                    onChoose(LabelDraft())
                } label: {
                    Label("Enter a label by hand", systemImage: "keyboard")
                }
            }
        }
        .navigationTitle("Scan a label")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Confirm

struct ConfirmLabelView: View {
    @Binding var draft: LabelDraft
    let onConfirm: (ConfirmedLabel) -> Void

    var body: some View {
        Form {
            if draft.isSample {
                Section { SampleBadge() }
            }

            if !draft.rawText.isEmpty {
                Section {
                    Text(draft.rawText)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                } header: {
                    Text("Label text")
                } footer: {
                    Text("Compare each field below with this text, and with the package itself.")
                }
            }

            Section("Product") {
                TextField("Product name", text: $draft.productName)
            }

            Section {
                Picker("Values are", selection: $draft.basis) {
                    Text("Choose").tag(NutrientBasis?.none)
                    ForEach(NutrientBasis.allCases) { basis in
                        Text(basis.title).tag(Optional(basis))
                    }
                }
                ForEach(Nutrient.allCases) { nutrient in
                    HStack {
                        Text(nutrient.title)
                        Spacer()
                        TextField("unknown", text: $draft[nutrient].text)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 90)
                            .accessibilityLabel("\(nutrient.title) amount")
                        Picker("\(nutrient.title) unit", selection: $draft[nutrient].unit) {
                            ForEach(nutrient.allowedUnits) { unit in
                                Text(unit.rawValue).tag(unit)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }
            } header: {
                Text("Nutrition values")
            } footer: {
                Text("Leave a field blank if the label does not state it. Blank means unknown. Enter 0 only if the label says 0. Total sugars and added sugars are different things and are kept apart.")
            }

            Section {
                quantityRow("Serving size", text: $draft.servingText, unit: $draft.servingUnit)
                quantityRow("Package size", text: $draft.packageText, unit: $draft.packageUnit)
            } header: {
                Text("Sizes")
            } footer: {
                Text("Leave blank if not printed or not legible.")
            }

            Section {
                TextField("Ingredients, as printed", text: $draft.ingredientsText, axis: .vertical)
                    .lineLimit(3...8)
                    .disabled(draft.ingredientsUnavailable)
                Toggle("Ingredients not available", isOn: $draft.ingredientsUnavailable)
            } header: {
                Text("Ingredients")
            }

            Section {
                Picker("On the package", selection: $draft.precautionaryMode) {
                    ForEach(LabelDraft.PrecautionaryMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                if draft.precautionaryMode == .hasStatement {
                    TextField("For example: may contain nuts", text: $draft.precautionaryText, axis: .vertical)
                        .lineLimit(2...5)
                }
            } header: {
                Text("Precautionary allergy statements")
            } footer: {
                Text("These are lines such as \"may contain\" or \"made in a facility that handles\". Please read them on the package itself.")
            }

            Section {
                Toggle("I checked the nutrition values against the package", isOn: $draft.checkedNutrition)
                Toggle("I checked ingredients and allergy statements against the package", isOn: $draft.checkedIngredients)
            } header: {
                Text("Your confirmation")
            }

            let issues = draft.issues
            if !issues.isEmpty {
                Section("Before you continue") {
                    ForEach(issues, id: \.self) { issue in
                        Label(issue, systemImage: "circle")
                            .font(.footnote)
                    }
                }
            }

            Section {
                Button {
                    if let confirmed = draft.confirmed() { onConfirm(confirmed) }
                } label: {
                    Text("See assessment").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!issues.isEmpty)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Confirm the label")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func quantityRow(_ title: String, text: Binding<String>, unit: Binding<QuantityUnit>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("unknown", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
                .accessibilityLabel(title)
            Picker("\(title) unit", selection: unit) {
                ForEach(QuantityUnit.allCases) { unit in
                    Text(unit.rawValue).tag(unit)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }
}

// MARK: - Assessment

struct AssessmentScreen: View {
    enum PortionMode: String, CaseIterable, Identifiable {
        case servings, amount
        var id: String { rawValue }
        var title: String { self == .servings ? "Servings" : "Amount" }
    }

    @Environment(AppStore.self) private var store
    let label: ConfirmedLabel
    let onDone: () -> Void

    @State private var mode: PortionMode = .servings
    @State private var amountText = "1"
    @State private var unit: QuantityUnit = .gram
    @State private var assessmentID = UUID()
    @State private var savedAction: DecisionAction?

    private var portion: Portion {
        let value: Double
        if case .value(let parsed) = DecimalParsing.parse(amountText) { value = parsed } else { value = 0 }
        return mode == .servings ? .servings(value) : .amount(Quantity(value: value, unit: unit))
    }

    private var assessment: Assessment {
        AssessmentEngine.assess(label: label, profile: store.profile, portion: portion,
                                now: label.confirmedAt, id: assessmentID)
    }

    var body: some View {
        let current = assessment
        List {
            Section {
                Picker("Portion measured in", selection: $mode) {
                    ForEach(PortionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                HStack {
                    Text(mode == .servings ? "Number of servings" : "Amount")
                    Spacer()
                    TextField("0", text: $amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90)
                        .accessibilityLabel("Portion amount")
                    if mode == .amount {
                        Picker("Portion unit", selection: $unit) {
                            ForEach(QuantityUnit.allCases) { unit in
                                Text(unit.rawValue).tag(unit)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }
            } header: {
                Text("Your portion")
            } footer: {
                Text("You choose the portion. The app only does the arithmetic and does not suggest how much to eat.")
            }

            AssessmentSections(assessment: current)

            Section {
                if let savedAction {
                    Label("Saved as \"\(savedAction.title)\". You can delete it under History.", systemImage: "checkmark.circle")
                } else {
                    Menu {
                        ForEach(DecisionAction.allCases) { action in
                            Button(action.title) {
                                store.saveDecision(assessment: current, action: action)
                                savedAction = action
                            }
                        }
                    } label: {
                        Label("Save decision", systemImage: "tray.and.arrow.down")
                    }
                }
                Button("Done", action: onDone)
            } footer: {
                Text("Saving is optional. Nothing is kept unless you save, and the app never assumes you ate something you scanned.")
            }
        }
        .navigationTitle("Assessment")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: portion) {
            // A changed portion is a new assessment; any earlier saved snapshot stays as it was.
            assessmentID = UUID()
            savedAction = nil
        }
        .onAppear {
            if label.basis == .per100ml || label.serving?.unit == .millilitre { unit = .millilitre }
        }
    }
}

/// The read-only body of an assessment, shared by the live screen and saved history.
struct AssessmentSections: View {
    let assessment: Assessment

    var body: some View {
        Section {
            if assessment.label.isSample { SampleBadge() }
            PrototypeBanner(text: "Draft assessment. Not clinically reviewed advice.")
        }

        Section {
            ForEach(assessment.summary, id: \.self) { line in
                Text(line)
            }
        } header: {
            Text(assessment.goal.map { "Summary for: \($0.title)" } ?? "Summary")
        }

        Section {
            let allergen = assessment.allergen
            Label(allergen.headline, systemImage: allergen.status == .matchFound ? "exclamationmark.triangle.fill" : "info.circle")
                .font(.body.weight(.semibold))
                .foregroundStyle(allergen.status == .matchFound ? Color.red : Color.primary)
            ForEach(allergen.matches) { match in
                Text("\(match.allergen.title): found \"\(match.term)\" in \(match.source == .ingredients ? "the ingredients" : "the precautionary statement").")
            }
            ForEach(allergen.gaps, id: \.self) { gap in
                Text(gap)
            }
            Text(allergen.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Allergy check")
        }

        Section {
            ForEach(assessment.facts) { fact in
                VStack(alignment: .leading, spacing: 2) {
                    Text(fact.nutrient.title)
                        .font(.body.weight(fact.isFocus ? .semibold : .regular))
                    Text(fact.labelValue.map { "Label: \($0.text) \(assessment.label.basis.title)" } ?? "Label: not stated")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let portionValue = fact.portionValue {
                        Text("Your portion (\(assessment.calculation.portion.text)): \(portionValue.text)")
                            .font(.footnote)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("Confirmed label facts")
        } footer: {
            if let block = assessment.calculation.blocked {
                Text("Portion figures are not shown. \(block.explanation)")
            } else {
                Text("Portion figures are the label values multiplied for the portion you chose.")
            }
        }

        if !assessment.missing.isEmpty {
            Section("Missing or uncertain") {
                ForEach(assessment.missing, id: \.self) { item in
                    Label(item, systemImage: "questionmark.circle")
                }
            }
        }

        Section {
            Text(assessment.nextStep.text)
        } header: {
            Text(assessment.nextStep.evidenceCardID == nil ? "A practical next step" : "Suggested next step")
        } footer: {
            Text(assessment.guidanceNote)
        }

        Section {
            if assessment.evidenceCards.isEmpty {
                Text("No evidence card applies.")
            }
            ForEach(assessment.evidenceCards) { card in
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.claim)
                    Text("Status: \(card.state.title) · version \(card.version)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ForEach(card.sources) { source in
                        Text("\(source.title). \(source.dateDescription)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            LabeledContent("Rule version", value: assessment.ruleVersion)
            LabeledContent("Label confirmed", value: Fmt.date(assessment.label.confirmedAt))
        } header: {
            Text("Sources and review status")
        } footer: {
            Text("Draft cards are listed for transparency and are not used to give advice.")
        }
    }
}
