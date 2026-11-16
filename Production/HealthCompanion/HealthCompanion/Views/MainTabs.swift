import Charts
import SwiftUI

struct MainTabs: View {
    @State private var tab: AppTab = .today
    @State private var showScan = false

    var body: some View {
        TabView(selection: $tab) {
            TodayView()
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.today)
            HistoryView()
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.history)
            YouView()
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.you)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FloatingTabBar(selection: $tab) { showScan = true }
        }
        .fullScreenCover(isPresented: $showScan) { ScanFlow() }
    }
}

// MARK: - Today

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var showCheckIn = false

    private var calendar: Calendar { .current }

    private var days: [Date] {
        let today = calendar.startOfDay(for: .now)
        return (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    var body: some View {
        NavigationStack {
            CardPage {
                header
                weekStrip

                let summary = IntakeMath.summary(of: store.eaten(on: selectedDay))
                EnergyCard(value: summary.total(.energy).map(Fmt.number),
                           unit: "kcal",
                           caption: energyCaption(summary))

                AdaptiveStack {
                    ForEach([Nutrient.protein, .carbohydrate, .fat]) { nutrient in
                        MetricTile(nutrient: nutrient,
                                   value: summary.total(nutrient).map { "\(Fmt.number($0)) g" },
                                   caption: "eaten")
                    }
                }

                if let note = unknownNote(summary) {
                    Footnote(note).padding(.horizontal, 4)
                }

                SectionTitle("Recently saved")
                let recent = Array(store.decisionsNewestFirst.prefix(3))
                if recent.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nothing saved yet")
                            .font(.headline)
                        Footnote("Tap + to scan a label. A scan is only kept if you choose to save it.")
                    }
                    .card()
                } else {
                    ForEach(recent) { decision in
                        DecisionCard(decision: decision)
                    }
                }

                Button {
                    showCheckIn = true
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "square.and.pencil")
                            .font(.headline)
                            .frame(width: 44, height: 44)
                            .background(Theme.chip, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Weekly check-in")
                                .font(.headline)
                            Footnote("Optional. Skipping a week is fine and is never counted against you.")
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .card()
                }
                .buttonStyle(.plain)

                PrototypeBanner().padding(.horizontal, 4)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showCheckIn) { CheckInView() }
        }
    }

    private var header: some View {
        AdaptiveStack(spacing: 8) {
            Label("Health Companion", systemImage: "leaf.fill")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            if let goal = store.profile?.primaryGoal {
                Label(goal.title, systemImage: goal.symbol)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.hairline))
                    .accessibilityLabel("Your current focus: \(goal.title)")
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    private var weekStrip: some View {
        HStack(spacing: 4) {
            ForEach(days, id: \.self) { day in
                let selected = calendar.isDate(day, inSameDayAs: selectedDay)
                let hasSaved = store.hasSavedDecision(on: day)
                Button {
                    selectedDay = day
                } label: {
                    VStack(spacing: 6) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(selected ? Color.primary : Color.secondary)
                        Text(day.formatted(.dateTime.day()))
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 34, height: 34)
                            .overlay(
                                Circle().strokeBorder(
                                    hasSaved ? Color.primary : Color.secondary.opacity(0.5),
                                    style: StrokeStyle(lineWidth: 1.5, dash: hasSaved ? [] : [3, 3]))
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(selected ? Theme.card : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted))\(hasSaved ? ", has saved items" : "")")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        // Seven days must fit across the screen, so this strip stops growing; each day is read out in full.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private var dayPhrase: String {
        calendar.isDateInToday(selectedDay) ? "today" : "on \(selectedDay.formatted(.dateTime.weekday(.wide)))"
    }

    private func energyCaption(_ summary: IntakeSummary) -> String {
        switch summary.itemCount {
        case 0: "Nothing saved as eaten \(dayPhrase). This is a record, not a target."
        case 1: "From 1 item you saved as eaten \(dayPhrase)"
        default: "From \(summary.itemCount) items you saved as eaten \(dayPhrase)"
        }
    }

    /// Says plainly when a total leaves something out, so a gap is never read as zero.
    private func unknownNote(_ summary: IntakeSummary) -> String? {
        let shown: [Nutrient] = [.energy, .protein, .carbohydrate, .fat]
        let gaps = shown.filter { summary.unknownCount($0) > 0 }
        guard !gaps.isEmpty else { return nil }
        let names = gaps.map { $0.title.lowercased() }.joined(separator: ", ")
        return "Some items have no figure for \(names) for the portion you saved. They are left out of the totals, not counted as zero."
    }
}

/// A saved decision as a card. Opens the stored snapshot.
struct DecisionCard: View {
    @Environment(AppStore.self) private var store
    let decision: SavedDecision
    var onDelete: (() -> Void)?

    var body: some View {
        if let assessment = store.assessment(for: decision) {
            NavigationLink {
                    SavedAssessmentView(assessment: assessment, decision: decision)
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        AdaptiveStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(assessment.label.productName)
                                .font(.subheadline.weight(.medium))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(decision.timestamp.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.trailing, onDelete == nil ? 0 : 36)
                        Label(energyText(assessment), systemImage: "flame.fill")
                            .font(.headline)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        AdaptiveStack(spacing: 12) {
                          HStack(spacing: 12) {
                            ForEach([Nutrient.protein, .carbohydrate, .fat]) { nutrient in
                                HStack(spacing: 4) {
                                    Image(systemName: nutrient.symbol)
                                        .foregroundStyle(nutrient.tint)
                                    Text(assessment.calculation.value(nutrient)?.text ?? "–")
                                }
                                .font(.footnote)
                                .accessibilityElement(children: .ignore)
                                .lineLimit(1)
                                .fixedSize()
                                .accessibilityLabel("\(nutrient.title) \(assessment.calculation.value(nutrient)?.text ?? "not known")")
                            }
                          }
                          .frame(maxWidth: .infinity, alignment: .leading)
                            Text(decision.action.title)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Theme.chip, in: Capsule())
                                .fixedSize()
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            .card(padding: 16)
            .overlay(alignment: .topTrailing) {
                if let onDelete {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                    .accessibilityLabel("Delete \(assessment.label.productName)")
                }
            }
        }
    }

    private func energyText(_ assessment: Assessment) -> String {
        if let energy = assessment.calculation.value(.energy) {
            return "\(energy.text) for \(assessment.calculation.portion.text)"
        }
        return "Energy for this portion not known"
    }
}

// MARK: - History

struct HistoryView: View {
    @Environment(AppStore.self) private var store
    @State private var weeksAgo = 0
    @State private var decisionToDelete: SavedDecision?
    @State private var checkInToDelete: CheckIn?

    var body: some View {
        NavigationStack {
            CardPage {
                Text("History")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .padding(.horizontal, 4)
                    .accessibilityAddTraits(.isHeader)

                WeeklyEnergyCard(weeksAgo: $weeksAgo)

                SectionTitle("Saved decisions")
                let decisions = store.decisionsNewestFirst
                if decisions.isEmpty {
                    Footnote("No saved decisions.").card()
                }
                ForEach(decisions) { decision in
                    DecisionCard(decision: decision) { decisionToDelete = decision }
                }

                SectionTitle("Check-ins")
                let checkIns = store.checkInsNewestFirst
                if checkIns.isEmpty {
                    Footnote("No check-ins.").card()
                }
                ForEach(checkIns) { checkIn in
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Fmt.date(checkIn.timestamp))
                                .font(.subheadline.weight(.medium))
                            Footnote("Energy \(checkIn.energy) of 5 · Focus felt manageable \(checkIn.manageability) of 5")
                            if let note = checkIn.note {
                                Text(note).font(.footnote)
                            }
                        }
                        Spacer(minLength: 0)
                        Button(role: .destructive) {
                            checkInToDelete = checkIn
                        } label: {
                            Image(systemName: "trash")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete check-in from \(Fmt.date(checkIn.timestamp))")
                    }
                    .card(padding: 16)
                }
                Footnote(CheckInReflection.text(for: checkIns)).padding(.horizontal, 4)
            }
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog("Delete this saved decision?", isPresented: Binding(
                get: { decisionToDelete != nil }, set: { if !$0 { decisionToDelete = nil } }), titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let decision = decisionToDelete { store.deleteDecision(decision) }
                    decisionToDelete = nil
                }
                Button("Cancel", role: .cancel) { decisionToDelete = nil }
            }
            .confirmationDialog("Delete this check-in?", isPresented: Binding(
                get: { checkInToDelete != nil }, set: { if !$0 { checkInToDelete = nil } }), titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let checkIn = checkInToDelete { store.deleteCheckIn(checkIn) }
                    checkInToDelete = nil
                }
                Button("Cancel", role: .cancel) { checkInToDelete = nil }
            }
        }
    }
}

/// Energy per day from items saved as "Ate". A record of what was saved, with no target.
struct WeeklyEnergyCard: View {
    @Environment(AppStore.self) private var store
    @Binding var weeksAgo: Int

    private struct Day: Identifiable {
        let date: Date
        let summary: IntakeSummary
        var id: Date { date }
    }

    private var calendar: Calendar { .current }

    private var days: [Day] {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: .now)?.start,
              let start = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: thisWeek) else { return [] }
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start).map { date in
                Day(date: date, summary: IntakeMath.summary(of: store.eaten(on: date)))
            }
        }
    }

    var body: some View {
        let days = days
        let items = days.reduce(0) { $0 + $1.summary.itemCount }
        let energies = days.compactMap { $0.summary.total(.energy) }
        let total = energies.isEmpty ? nil : energies.reduce(0, +)
        let unknown = days.reduce(0) { $0 + $1.summary.unknownCount(.energy) }

        VStack(alignment: .leading, spacing: 16) {
            CardTitle("Weekly energy")

            HStack(alignment: .top, spacing: 28) {
                stat("Items eaten", value: "\(items)", unit: nil)
                stat("Energy", value: total.map(Fmt.number) ?? "–", unit: total == nil ? nil : "kcal")
            }

            if let first = days.first?.date, let last = days.last?.date {
                Chart(days) { day in
                    if let energy = day.summary.total(.energy) {
                        BarMark(x: .value("Day", day.date, unit: .day),
                                y: .value("Energy in kcal", energy),
                                width: .fixed(12))
                            .foregroundStyle(Theme.accent)
                            .cornerRadius(5)
                    }
                }
                .chartXScale(domain: first...(calendar.date(byAdding: .day, value: 1, to: last) ?? last))
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        AxisValueLabel()
                    }
                }
                .frame(height: 170)
                .overlay {
                    if energies.isEmpty {
                        Text("Nothing saved as eaten in this week")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel("Energy per day from items saved as eaten")
            }

            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { index in
                    let selected = weeksAgo == index
                    Button {
                        weeksAgo = index
                    } label: {
                        Text(index == 0 ? "This wk" : index == 1 ? "Last wk" : "\(index) wk ago")
                            .font(.caption.weight(selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Color.primary : Color.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(selected ? Theme.card : Color.clear, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(index == 0 ? "This week" : index == 1 ? "Last week" : "\(index) weeks ago")
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }
            .padding(4)
            .background(Theme.chip, in: Capsule())
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)

            Footnote(unknown > 0
                     ? "Only items you saved as eaten are counted. \(unknown) of them had no energy figure for the saved portion and are left out, not counted as zero."
                     : "Only items you saved as eaten are counted. This is a record of what you saved, not a target.")
        }
        .card()
    }

    private func stat(_ title: String, value: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                if let unit {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Describes what was recorded. Never infers causes and never treats gaps as failures.
enum CheckInReflection {
    static func text(for checkIns: [CheckIn]) -> String {
        guard let latest = checkIns.first else {
            return "Check-ins are your own notes. You can delete any of them here."
        }
        let count = checkIns.count
        return "You have recorded \(count) check-in\(count == 1 ? "" : "s"). The most recent reported energy \(latest.energy) of 5. These are your own observations and do not show what caused them."
    }
}

struct SavedAssessmentView: View {
    let assessment: Assessment
    let decision: SavedDecision

    var body: some View {
        CardPage {
            AssessmentTitleCard(assessment: assessment)
            VStack(alignment: .leading, spacing: 10) {
                InfoRow(title: "Saved as", value: decision.action.title)
                InfoRow(title: "Saved on", value: Fmt.date(decision.timestamp))
                Footnote("This is a snapshot from when you saved it. Later changes to your profile do not alter it.")
            }
            .card()
            AssessmentNutrition(assessment: assessment)
            AssessmentDetails(assessment: assessment)
        }
        .navigationTitle("Saved decision")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

// MARK: - You

struct YouView: View {
    @Environment(AppStore.self) private var store
    @State private var showEditor = false
    @State private var confirmErase = false

    var body: some View {
        NavigationStack {
            CardPage {
                Text("You")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .padding(.horizontal, 4)
                    .accessibilityAddTraits(.isHeader)

                if let profile = store.profile {
                    VStack(alignment: .leading, spacing: 12) {
                        CardTitle("Profile")
                        InfoRow(title: "Goals, in order", value: profile.goals.map(\.title).joined(separator: ", "))
                        InfoRow(title: "Dietary preferences",
                                value: profile.dietaryPreferences.isEmpty ? "None selected" : profile.dietaryPreferences.map(\.title).joined(separator: ", "))
                        InfoRow(title: "Allergies", value: profile.allergies.summary)
                        InfoRow(title: "Last updated", value: Fmt.date(profile.updatedAt))
                        Button("Edit profile") { showEditor = true }
                            .buttonStyle(SecondaryButtonStyle())
                            .padding(.top, 4)
                    }
                    .card()
                }

                VStack(alignment: .leading, spacing: 12) {
                    CardTitle("What is remembered")
                    InfoRow(title: "Saved decisions", value: "\(store.data.decisions.count)")
                    InfoRow(title: "Check-ins", value: "\(store.data.checkIns.count)")
                    InfoRow(title: "Photos", value: "None kept")
                    Footnote("Everything is stored in one file inside this app on this device. Nothing is sent anywhere. Photos are not kept.")
                }
                .card()

                VStack(alignment: .leading, spacing: 12) {
                    CardTitle("Your data")
                    NavigationLink {
                        ExportView()
                    } label: {
                        Label("Export stored data", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Button(role: .destructive) {
                        confirmErase = true
                    } label: {
                        Label("Erase all data", systemImage: "trash")
                            .font(.headline)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.red.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .card()

                if let error = store.lastError {
                    Label(error, systemImage: "exclamationmark.triangle").card()
                }

                PrototypeBanner().padding(.horizontal, 4)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showEditor) {
                if let profile = store.profile {
                    ProfileEditorView(draft: ProfileDraft(profile: profile))
                }
            }
            .confirmationDialog("Erase everything stored by this app?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Erase all data", role: .destructive) { store.eraseAll() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your profile, saved decisions and check-ins will be removed from this device. This cannot be undone.")
            }
        }
    }
}

struct ProfileEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var draft: ProfileDraft

    var body: some View {
        NavigationStack {
            Form {
                GoalsEditor(goals: $draft.goals)
                DietEditor(draft: $draft)
            }
            .themedForm()
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.saveProfile(goals: draft.goals, dietaryPreferences: draft.orderedPreferences, allergies: draft.allergyRecord)
                        dismiss()
                    }
                    .disabled(draft.goals.isEmpty)
                }
            }
        }
    }
}

struct ExportView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let json = store.exportJSON()
        ScrollView {
            Text(json)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .background(AppBackground())
        .navigationTitle("Stored data")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ShareLink(item: json) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }
}

// MARK: - Check-in

struct CheckInView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var energy = 3
    @State private var manageability = 3
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Energy", selection: $energy) {
                        ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("How was your energy this week?")
                } footer: {
                    Text("1 is very low, 5 is very good.")
                }

                Section {
                    Picker("Manageability", selection: $manageability) {
                        ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("How manageable did your focus feel?")
                } footer: {
                    Text("1 is very hard, 5 is very manageable.")
                }

                Section("Note (optional)") {
                    TextField("Anything you want to remember", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Text("Nothing is saved until you tap Save. A check-in never changes your goals.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .themedForm()
            .navigationTitle("Check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.addCheckIn(energy: energy, manageability: manageability, note: note)
                        dismiss()
                    }
                }
            }
        }
    }
}
