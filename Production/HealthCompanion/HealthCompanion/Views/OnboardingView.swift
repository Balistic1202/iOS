import SwiftUI

struct OnboardingView: View {
    enum Step: Int { case intro, age, notEligible, goals, diet, guidance, review }

    @Environment(AppStore.self) private var store
    @State private var step: Step = .intro
    @State private var draft = ProfileDraft()

    var body: some View {
        NavigationStack {
            Form {
                switch step {
                case .intro: intro
                case .age: age
                case .notEligible: notEligible
                case .goals: GoalsEditor(goals: $draft.goals)
                case .diet: DietEditor(draft: $draft)
                case .guidance: guidance
                case .review: review
                }
            }
            .themedForm()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let previous {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back") { step = previous }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { footer }
        }
    }

    private var title: String {
        switch step {
        case .intro: "Welcome"
        case .age, .notEligible: "Before you start"
        case .goals: "Your goals"
        case .diet: "Preferences"
        case .guidance: "Good to know"
        case .review: "What will be saved"
        }
    }

    private var previous: Step? {
        switch step {
        case .intro, .age: nil
        case .notEligible: .age
        case .goals: .age
        case .diet: .goals
        case .guidance: .diet
        case .review: .guidance
        }
    }

    // MARK: Steps

    @ViewBuilder private var intro: some View {
        Section {
            Text("Health Companion helps you understand a packaged food in the context of your goals: clear facts from the label, what is missing or uncertain, and a useful next step.")
            Text("It remembers only what you choose to save.")
        }
        Section("This is a prototype") {
            Label("Sample products are invented and clearly marked.", systemImage: "testtube.2")
            Label("Nothing here is clinically reviewed advice.", systemImage: "exclamationmark.bubble")
            Label("Everything stays on this device. No account, no network.", systemImage: "iphone")
        }
    }

    @ViewBuilder private var age: some View {
        Section {
            Text("This prototype is designed for adults.")
            Button("I am 18 or older") { step = .goals }
            Button("I am under 18") { step = .notEligible }
        } footer: {
            Text("Your answer is not stored.")
        }
    }

    @ViewBuilder private var notEligible: some View {
        Section {
            Text("Thanks for being honest. This prototype is only for adults, so setup stops here.")
            Text("Nothing about your answer has been saved. For questions about food and health, a parent, carer or health professional is the right person to ask.")
        }
    }

    @ViewBuilder private var guidance: some View {
        Section {
            Text("If you are pregnant or breastfeeding, manage a health condition through diet, take medicine affected by food, or have a history of disordered eating, please rely on guidance from a qualified professional who knows your situation.")
            Text("This prototype does not ask about medical history, because none of its features use it.")
        }
    }

    @ViewBuilder private var review: some View {
        Section {
            LabeledContent("Goals, in order") {
                Text(draft.goals.map(\.title).joined(separator: ", "))
            }
            LabeledContent("Dietary preferences") {
                Text(draft.orderedPreferences.isEmpty ? "None selected" : draft.orderedPreferences.map(\.title).joined(separator: ", "))
            }
            LabeledContent("Allergies") {
                Text(draft.allergyRecord.summary)
            }
        } header: {
            Text("Saved on this device")
        } footer: {
            Text("That is everything. Photos, label scans and check-ins are saved only when you ask. You can change, export or erase all of this under You.")
        }
    }

    // MARK: Footer button

    @ViewBuilder private var footer: some View {
        switch step {
        case .intro: primary("Continue") { step = .age }
        case .age, .notEligible: EmptyView()
        case .goals: primary("Continue", disabled: draft.goals.isEmpty) { step = .diet }
        case .diet: primary("Continue") { step = .guidance }
        case .guidance: primary("Continue") { step = .review }
        case .review:
            primary("Save and start") {
                store.saveProfile(goals: draft.goals, dietaryPreferences: draft.orderedPreferences, allergies: draft.allergyRecord)
            }
        }
    }

    private func primary(_ title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(disabled)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}
