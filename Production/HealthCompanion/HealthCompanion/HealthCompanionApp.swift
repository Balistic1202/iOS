import SwiftUI

@main
struct HealthCompanionApp: App {
    @State private var store = AppStore(persistence: FilePersistence.standard)

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(Theme.accent)
        }
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if store.profile == nil {
            OnboardingView()
        } else {
            MainTabs()
        }
    }
}

// MARK: - Shared pieces

/// Shown wherever content could be mistaken for reviewed advice.
struct PrototypeBanner: View {
    var text = "Prototype. Nothing here is clinically reviewed advice."

    var body: some View {
        Label(text, systemImage: "hammer")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityLabel(text)
    }
}

struct SampleBadge: View {
    var body: some View {
        Label("Sample product, invented for testing", systemImage: "testtube.2")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.orange)
    }
}

/// Editable copy of the profile, shared by onboarding and the You tab.
struct ProfileDraft: Equatable {
    enum AllergyMode: String, CaseIterable, Identifiable {
        case notProvided, none, has
        var id: String { rawValue }

        var title: String {
            switch self {
            case .notProvided: "Prefer not to say"
            case .none: "No allergies"
            case .has: "I have allergies"
            }
        }
    }

    var goals: [Goal] = []
    var preferences: Set<DietaryPreference> = []
    var allergyMode: AllergyMode = .notProvided
    var allergens: Set<Allergen> = []

    init() {}

    init(profile: Profile) {
        goals = profile.goals
        preferences = Set(profile.dietaryPreferences)
        switch profile.allergies {
        case .notProvided: allergyMode = .notProvided
        case .noneReported: allergyMode = .none
        case .confirmed(let list):
            allergyMode = .has
            allergens = Set(list)
        }
    }

    var orderedPreferences: [DietaryPreference] { DietaryPreference.allCases.filter(preferences.contains) }

    var allergyRecord: AllergyRecord {
        switch allergyMode {
        case .notProvided: return .notProvided
        case .none: return .noneReported
        case .has:
            let list = Allergen.allCases.filter(allergens.contains)
            return list.isEmpty ? .notProvided : .confirmed(list)
        }
    }
}

struct GoalsEditor: View {
    @Binding var goals: [Goal]

    var body: some View {
        Section {
            ForEach(Goal.allCases) { goal in
                Toggle(isOn: Binding(
                    get: { goals.contains(goal) },
                    set: { isOn in
                        if isOn { if !goals.contains(goal) { goals.append(goal) } } else { goals.removeAll { $0 == goal } }
                    })) {
                    Label(goal.title, systemImage: goal.symbol)
                }
            }
        } header: {
            Text("Goals")
        } footer: {
            Text("A goal is a preference for what the app shows first. It is not a prescription.")
        }

        if goals.count > 1 {
            Section {
                ForEach(Array(goals.enumerated()), id: \.element) { index, goal in
                    HStack {
                        Text("\(index + 1). \(goal.title)")
                        Spacer()
                        if index > 0 {
                            Button {
                                goals.swapAt(index, index - 1)
                            } label: {
                                Image(systemName: "arrow.up.circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Move \(goal.title) up")
                        }
                    }
                }
            } header: {
                Text("Priority order")
            } footer: {
                Text("The first goal is your current focus.")
            }
        }
    }
}

struct DietEditor: View {
    @Binding var draft: ProfileDraft

    var body: some View {
        Section("Dietary preferences (optional)") {
            ForEach(DietaryPreference.allCases) { preference in
                Toggle(preference.title, isOn: Binding(
                    get: { draft.preferences.contains(preference) },
                    set: { isOn in
                        if isOn { draft.preferences.insert(preference) } else { draft.preferences.remove(preference) }
                    }))
            }
        }

        Section {
            Picker("Allergies", selection: $draft.allergyMode) {
                ForEach(ProfileDraft.AllergyMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            if draft.allergyMode == .has {
                ForEach(Allergen.allCases) { allergen in
                    Toggle(allergen.title, isOn: Binding(
                        get: { draft.allergens.contains(allergen) },
                        set: { isOn in
                            if isOn { draft.allergens.insert(allergen) } else { draft.allergens.remove(allergen) }
                        }))
                }
            }
        } header: {
            Text("Allergies (optional)")
        } footer: {
            Text("Saved allergies are compared with label text you confirm. A label check can warn about a match. It can never confirm that a product is free from an allergen.")
        }
    }
}
