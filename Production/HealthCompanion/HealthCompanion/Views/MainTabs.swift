import SwiftUI

struct MainTabs: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }
            YouView()
                .tabItem { Label("You", systemImage: "person") }
        }
    }
}

// MARK: - Today

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @State private var showScan = false
    @State private var showCheckIn = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showScan = true
                    } label: {
                        Label("Scan a label", systemImage: "camera.viewfinder")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    PrototypeBanner()
                }

                Section("Your current focus") {
                    if let goal = store.profile?.primaryGoal {
                        Label(goal.title, systemImage: goal.symbol)
                    } else {
                        Text("No goal selected")
                    }
                }

                Section("Recent saved decisions") {
                    let recent = Array(store.decisionsNewestFirst.prefix(3))
                    if recent.isEmpty {
                        Text("Nothing saved yet. A scan is only kept if you choose to save it.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(recent) { decision in
                            DecisionRow(decision: decision)
                        }
                    }
                }

                Section {
                    Button {
                        showCheckIn = true
                    } label: {
                        Label("Weekly check-in", systemImage: "square.and.pencil")
                    }
                } footer: {
                    Text("Optional. Skipping a week is fine and is never counted against you.")
                }
            }
            .navigationTitle("Today")
            .fullScreenCover(isPresented: $showScan) { ScanFlow() }
            .sheet(isPresented: $showCheckIn) { CheckInView() }
        }
    }
}

struct DecisionRow: View {
    @Environment(AppStore.self) private var store
    let decision: SavedDecision

    var body: some View {
        if let assessment = store.assessment(for: decision) {
            NavigationLink {
                SavedAssessmentView(assessment: assessment, decision: decision)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(assessment.label.productName)
                    Text("\(decision.action.title) · \(Fmt.date(decision.timestamp))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - History

struct HistoryView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                Section("Saved decisions") {
                    let decisions = store.decisionsNewestFirst
                    if decisions.isEmpty {
                        Text("No saved decisions.").foregroundStyle(.secondary)
                    }
                    ForEach(decisions) { decision in
                        DecisionRow(decision: decision)
                    }
                    .onDelete { offsets in
                        offsets.map { decisions[$0] }.forEach(store.deleteDecision)
                    }
                }

                Section {
                    let checkIns = store.checkInsNewestFirst
                    if checkIns.isEmpty {
                        Text("No check-ins.").foregroundStyle(.secondary)
                    }
                    ForEach(checkIns) { checkIn in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Fmt.date(checkIn.timestamp))
                            Text("Energy \(checkIn.energy) of 5 · Focus felt manageable \(checkIn.manageability) of 5")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            if let note = checkIn.note {
                                Text(note).font(.footnote)
                            }
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { checkIns[$0] }.forEach(store.deleteCheckIn)
                    }
                } header: {
                    Text("Check-ins")
                } footer: {
                    Text(CheckInReflection.text(for: store.checkInsNewestFirst))
                }
            }
            .navigationTitle("History")
            .toolbar { EditButton() }
        }
    }
}

/// Describes what was recorded. Never infers causes and never treats gaps as failures.
enum CheckInReflection {
    static func text(for checkIns: [CheckIn]) -> String {
        guard let latest = checkIns.first else {
            return "Check-ins are your own notes. Swipe a row to delete it."
        }
        let count = checkIns.count
        return "You have recorded \(count) check-in\(count == 1 ? "" : "s"). The most recent reported energy \(latest.energy) of 5. These are your own observations and do not show what caused them."
    }
}

struct SavedAssessmentView: View {
    let assessment: Assessment
    let decision: SavedDecision

    var body: some View {
        List {
            Section {
                LabeledContent("Saved as", value: decision.action.title)
                LabeledContent("Saved on", value: Fmt.date(decision.timestamp))
            } footer: {
                Text("This is a snapshot from when you saved it. Later changes to your profile do not alter it.")
            }
            AssessmentSections(assessment: assessment)
        }
        .navigationTitle(assessment.label.productName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - You

struct YouView: View {
    @Environment(AppStore.self) private var store
    @State private var showEditor = false
    @State private var confirmErase = false

    var body: some View {
        NavigationStack {
            List {
                if let profile = store.profile {
                    Section("Profile") {
                        LabeledContent("Goals, in order") {
                            Text(profile.goals.map(\.title).joined(separator: ", "))
                        }
                        LabeledContent("Dietary preferences") {
                            Text(profile.dietaryPreferences.isEmpty ? "None selected" : profile.dietaryPreferences.map(\.title).joined(separator: ", "))
                        }
                        LabeledContent("Allergies", value: profile.allergies.summary)
                        LabeledContent("Last updated", value: Fmt.date(profile.updatedAt))
                        Button("Edit profile") { showEditor = true }
                    }
                }

                Section {
                    LabeledContent("Saved decisions", value: "\(store.data.decisions.count)")
                    LabeledContent("Check-ins", value: "\(store.data.checkIns.count)")
                    LabeledContent("Photos", value: "None kept")
                } header: {
                    Text("What is remembered")
                } footer: {
                    Text("Everything is stored in one file inside this app on this device. Nothing is sent anywhere. Photos are not kept.")
                }

                Section("Your data") {
                    NavigationLink("Export stored data") { ExportView() }
                    Button("Erase all data", role: .destructive) { confirmErase = true }
                }

                if let error = store.lastError {
                    Section { Label(error, systemImage: "exclamationmark.triangle") }
                }

                Section { PrototypeBanner() }
            }
            .navigationTitle("You")
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
        .navigationTitle("Stored data")
        .navigationBarTitleDisplayMode(.inline)
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
