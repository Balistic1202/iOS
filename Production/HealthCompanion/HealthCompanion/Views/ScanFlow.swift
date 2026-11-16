import SwiftUI

/// Label photos for one scan. Held in memory only and gone when the flow closes.
/// A reference type, so every screen in the flow reads the current photos.
@Observable
final class ScanPhotos {
    var images: [UIImage] = []
}

/// Capture, confirm, then assess. Nothing is stored unless the user saves a decision at the end.
struct ScanFlow: View {
    enum Route: Hashable {
        case confirm
        case assessment(ConfirmedLabel)
    }

    @Environment(\.dismiss) private var dismiss
    @State private var path: [Route] = []
    @State private var draft = LabelDraft()
    @State private var photos = ScanPhotos()

    var body: some View {
        NavigationStack(path: $path) {
            CaptureView { chosen, image in
                draft = chosen
                photos.images = image.map { [$0] } ?? []
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
                    ConfirmLabelView(draft: $draft, images: Binding(get: { photos.images }, set: { photos.images = $0 })) { confirmed in
                        // The label travels with the route, so the destination never reads stale state.
                        path.append(.assessment(confirmed))
                    }
                case .assessment(let label):
                    AssessmentScreen(label: label, image: photos.images.first) { dismiss() }
                }
            }
        }
    }
}

// MARK: - Capture

struct CaptureView: View {
    let onChoose: (LabelDraft, UIImage?) -> Void

    var body: some View {
        List {
            Section {
                Text("Your photo is read on this device to find the label text. It is not saved and nothing is sent anywhere. Only the details you confirm, and choose to save, are kept.")
            } header: {
                Text("How your label is handled")
            }

            Section {
                LabelPhotoSource { text, image in
                    onChoose(LabelTextParser.parse(text), image)
                }
            } header: {
                Text("From the package")
            } footer: {
                Text("Photograph the nutrition table and the ingredients. If they are on different sides, you can add a second photo on the next screen. Text reading makes mistakes, so you will check every field.")
            }

            Section {
                ForEach(Array(SampleProducts.all.enumerated()), id: \.offset) { _, sample in
                    Button {
                        onChoose(sample, nil)
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
                    onChoose(LabelDraft(), nil)
                } label: {
                    Label("Enter a label by hand", systemImage: "keyboard")
                }
            }
        }
        .themedForm()
        .navigationTitle("Scan a label")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Confirm

struct ConfirmLabelView: View {
    @Binding var draft: LabelDraft
    @Binding var images: [UIImage]
    let onConfirm: (ConfirmedLabel) -> Void

    var body: some View {
        Form {
            if draft.isSample {
                Section { SampleBadge() }
            }

            if !draft.isSample {
                Section {
                    if !images.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 12) {
                                ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: 260)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .accessibilityLabel("Label photo \(index + 1)")
                                }
                            }
                        }
                    }
                    LabelPhotoSource(cameraTitle: "Add a photo with the camera", importTitle: "Add a photo from the library") { text, image in
                        LabelTextParser.merge(text, into: &draft)
                        images.append(image)
                    }
                } header: {
                    Text(images.isEmpty ? "Label photos" : "Your label photos")
                } footer: {
                    Text("Photos are used only to read the label and are not saved. A further photo fills in blank fields and never overwrites what is already there.")
                }
            }

            if !draft.rawText.isEmpty {
                Section {
                    Text(draft.rawText)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                } header: {
                    Text(draft.isSample ? "Label text" : "Text read from your photos")
                } footer: {
                    Text(draft.isSample
                         ? "Compare each field below with this text, and with the package itself."
                         : "Text reading can misread digits, units and decimal points. Fields the app could not read are left blank. Check each one against the package itself.")
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
                    Text("See assessment")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!issues.isEmpty)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .themedForm()
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
    @Environment(\.dismiss) private var dismiss
    let label: ConfirmedLabel
    /// The first label photo of this scan, shown as a header. Memory only; never stored.
    var image: UIImage?
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
        ScrollView {
            VStack(spacing: 0) {
                hero
                VStack(alignment: .leading, spacing: 14) {
                    AssessmentTitleCard(assessment: current) { dismiss() }
                    AssessmentNutrition(assessment: current)
                    portionCard
                    AssessmentDetails(assessment: current)
                    Footnote("Saving is optional. Nothing is kept unless you save, and the app never assumes you ate something you scanned.")
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 12)
                .background(Theme.background, in: UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous))
                .padding(.top, -30)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Theme.background.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .overlay(alignment: .top) { topButtons }
        .safeAreaInset(edge: .bottom, spacing: 0) { actions(current) }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: portion) {
            // A changed portion is a new assessment; any earlier saved snapshot stays as it was.
            assessmentID = UUID()
            savedAction = nil
        }
        .onAppear {
            if label.basis == .per100ml || label.serving?.unit == .millilitre { unit = .millilitre }
        }
    }

    /// The label photo fills the top of the screen, under the status bar. Without a photo
    /// (a sample or a label typed by hand) a soft placeholder takes its place.
    @ViewBuilder private var hero: some View {
        if let image {
            Color.clear
                .frame(height: 360)
                .overlay {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
                .accessibilityLabel("Your label photo. It is not saved.")
        } else {
            LinearGradient(colors: [Color.orange.opacity(0.3), Color.pink.opacity(0.18), Theme.accent.opacity(0.25)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(height: 300)
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 40, weight: .light))
                        Text("No photo for this label")
                            .font(.footnote)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, 30)
                }
                .accessibilityHidden(true)
        }
    }

    private var topButtons: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                circleIcon("arrow.left")
            }
            .accessibilityLabel("Back to the label")
            Spacer()
            Menu {
                Button("Edit the label", systemImage: "pencil") { dismiss() }
                Button("Close without saving", systemImage: "xmark", action: onDone)
            } label: {
                circleIcon("ellipsis")
            }
            .accessibilityLabel("More")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private func circleIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial, in: Circle())
    }

    private var portionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle("Your portion")
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
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: 100)
                    .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            Footnote("You choose the portion. The app only does the arithmetic and does not suggest how much to eat.")
        }
        .card()
    }

    private func actions(_ current: Assessment) -> some View {
        VStack(spacing: 10) {
            if let savedAction {
                Label("Saved as \"\(savedAction.title)\". You can delete it under History.", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Done", action: onDone)
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                Group {
                    Menu {
                        ForEach(DecisionAction.allCases) { action in
                            Button(action.title) {
                                store.saveDecision(assessment: current, action: action)
                                savedAction = action
                            }
                        }
                    } label: {
                        Text("Save decision")
                            .font(.headline)
                            .foregroundStyle(Theme.onInk)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Theme.ink, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.regularMaterial)
    }
}

// MARK: - Read-only assessment cards, shared by the live screen and saved history

struct AssessmentTitleCard: View {
    let assessment: Assessment
    /// When set, a pencil button takes the user back to correct the label.
    var onEdit: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(assessment.label.productName)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let onEdit {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit the label")
                }
            }
            if assessment.label.isSample { SampleBadge() }
            PrototypeBanner(text: "Draft assessment. Not clinically reviewed advice.")
        }
        .card()
    }
}

/// Energy and the other nutrients as tiles. Shows portion figures when they can be worked out,
/// otherwise the label's own figures. An unknown value is a dash, never a zero.
struct AssessmentNutrition: View {
    let assessment: Assessment
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var page: Int? = 0

    private var showsPortion: Bool { assessment.calculation.blocked == nil }
    private var basisCaption: String {
        showsPortion ? "for your portion: \(assessment.calculation.portion.text)"
                     : "as printed on the label, \(assessment.label.basis.title)"
    }

    private func shown(_ fact: FactLine) -> NutrientValue? {
        showsPortion ? fact.portionValue : fact.labelValue
    }

    /// Three tiles per page. Nutrients in the user's focus come first, then protein, carbohydrate and fat.
    private var pages: [[FactLine]] {
        let order: [Nutrient] = [.protein, .carbohydrate, .fat, .totalSugars, .addedSugars, .fibre, .saturatedFat, .salt]
        let facts = order.compactMap { nutrient in assessment.facts.first { $0.nutrient == nutrient } }
        let sorted = facts.filter(\.isFocus) + facts.filter { !$0.isFocus }
        return stride(from: 0, to: sorted.count, by: 3).map { Array(sorted[$0..<min($0 + 3, sorted.count)]) }
    }

    var body: some View {
        let energy = assessment.facts.first { $0.nutrient == .energy }
        let energyValue = energy.flatMap(shown)
        HStack(spacing: 14) {
            Image(systemName: "flame.fill")
                .font(.title2)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Energy, \(basisCaption)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(energyValue.map { Fmt.number($0.amount) } ?? "–")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    if let energyValue {
                        Text(energyValue.unit.rawValue)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("not stated on the label")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .card(padding: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Energy \(basisCaption): \(energyValue?.text ?? "not stated on the label")")

        let pages = pages
        if typeSize.isAccessibilitySize {
            // At accessibility text sizes three tiles do not fit side by side, so every nutrient gets its own row.
            ForEach(pages.flatMap { $0 }) { fact in
                MetricTile(nutrient: fact.nutrient,
                           value: shown(fact)?.text,
                           caption: fact.labelValue == nil ? "not stated" : nil,
                           emphasised: fact.isFocus)
            }
        } else {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, facts in
                    HStack(spacing: 10) {
                        ForEach(facts) { fact in
                            MetricTile(nutrient: fact.nutrient,
                                       value: shown(fact)?.text,
                                       caption: fact.labelValue == nil ? "not stated" : nil,
                                       emphasised: fact.isFocus)
                        }
                        ForEach(0..<(3 - facts.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                    .containerRelativeFrame(.horizontal)
                    .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $page)
        .scrollIndicators(.hidden)

        HStack(spacing: 6) {
            ForEach(pages.indices, id: \.self) { index in
                Circle()
                    .fill(index == (page ?? 0) ? Color.primary : Color.clear)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(index == (page ?? 0) ? 1 : 0.4)))
                    .frame(width: 7, height: 7)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
        }

        if let block = assessment.calculation.blocked {
            Footnote("Portion figures are not shown. \(block.explanation)").padding(.horizontal, 4)
        } else {
            Footnote("\(typeSize.isAccessibilitySize ? "" : "Swipe for more nutrients. ")Portion figures are the label values multiplied for the portion you chose. Outlined tiles are in your current focus.")
                .padding(.horizontal, 4)
        }
    }
}

struct AssessmentDetails: View {
    let assessment: Assessment

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(assessment.goal.map { "Summary for: \($0.title)" } ?? "Summary")
            ForEach(assessment.summary, id: \.self) { line in
                Text(line).font(.subheadline)
            }
        }
        .card()

        let allergen = assessment.allergen
        VStack(alignment: .leading, spacing: 10) {
            CardTitle("Allergy check")
            Label(allergen.headline, systemImage: allergen.status == .matchFound ? "exclamationmark.triangle.fill" : "info.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(allergen.status == .matchFound ? Color.red : Color.primary)
            ForEach(allergen.matches) { match in
                Text("\(match.allergen.title): found \"\(match.term)\" in \(match.source == .ingredients ? "the ingredients" : "the precautionary statement").")
                    .font(.subheadline)
            }
            ForEach(allergen.gaps, id: \.self) { gap in
                Text(gap).font(.subheadline)
            }
            Footnote(allergen.detail)
        }
        .card()
        .overlay {
            if allergen.status == .matchFound {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Color.red.opacity(0.6), lineWidth: 1.5)
            }
        }

        VStack(alignment: .leading, spacing: 10) {
            CardTitle("Confirmed label facts")
            ForEach(assessment.facts) { fact in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: fact.nutrient.symbol)
                        .font(.footnote)
                        .foregroundStyle(fact.nutrient.tint)
                        .frame(width: 20)
                    Text(fact.nutrient.title)
                        .fontWeight(fact.isFocus ? .semibold : .regular)
                    Spacer(minLength: 8)
                    Text(fact.labelValue?.text ?? "not stated")
                        .foregroundStyle(fact.labelValue == nil ? .secondary : .primary)
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
            }
            Footnote("Values as you confirmed them, \(assessment.label.basis.title).")
        }
        .card()

        if !assessment.missing.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle("Missing or uncertain")
                ForEach(assessment.missing, id: \.self) { item in
                    Label(item, systemImage: "questionmark.circle").font(.subheadline)
                }
            }
            .card()
        }

        VStack(alignment: .leading, spacing: 10) {
            CardTitle(assessment.nextStep.evidenceCardID == nil ? "A practical next step" : "Suggested next step")
            Text(assessment.nextStep.text).font(.subheadline)
            Footnote(assessment.guidanceNote)
        }
        .card()

        VStack(alignment: .leading, spacing: 10) {
            CardTitle("Sources and review status")
            if assessment.evidenceCards.isEmpty {
                Text("No evidence card applies.").font(.subheadline)
            }
            ForEach(assessment.evidenceCards) { card in
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.claim).font(.subheadline)
                    Footnote("Status: \(card.state.title) · version \(card.version)")
                    ForEach(card.sources) { source in
                        Footnote("\(source.title). \(source.dateDescription)")
                    }
                }
            }
            InfoRow(title: "Rule version", value: assessment.ruleVersion)
            InfoRow(title: "Label confirmed", value: Fmt.date(assessment.label.confirmedAt))
            Footnote("Draft cards are listed for transparency and are not used to give advice.")
        }
        .card()
    }
}
