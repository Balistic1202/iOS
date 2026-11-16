
import SwiftUI

struct ContentView: View {

    // MARK: - State

    @State private var waterIntake = 0
    @State private var coffeeCups = 0

    private let waterGoal = 2000
    private let glassSize = 300

    // MARK: - Interface

    var body: some View {

        NavigationStack {

            ScrollView {

                VStack(spacing: 24) {

                    // Water section

                    VStack(alignment: .leading, spacing: 16) {

                        TrackerCard(
                            title: "Water",
                            icon: "drop.fill",
                            value: "\(waterIntake) / \(waterGoal) ml",
                            color: .blue
                        )

                        ProgressView(
                            value: Double(waterIntake),
                            total: Double(waterGoal)
                        )
                        .tint(.blue)

                        HStack {

                            Button("Remove \(glassSize)") {
                                removeWater()
                            }
                            .buttonStyle(.bordered)
                            .disabled(waterIntake == 0)

                            Spacer()

                            Button("Add \(glassSize) ml") {
                                addWater()
                            }
                            .buttonStyle(.borderedProminent)

                        }

                        if waterIntake >= waterGoal {

                            Label(
                                "Daily goal reached!",
                                systemImage: "checkmark.circle.fill"
                            )
                            .foregroundStyle(.green)

                        }

                    }
                    .padding()
                    .background(
                        Color.blue.opacity(0.08)
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: 20)
                    )

                    // Coffee section

                    VStack(alignment: .leading, spacing: 16) {

                        Label("Coffee", systemImage: "cup.and.saucer.fill")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.brown)

                        Text("\(coffeeCups) cups")
                            .font(.title)
                            .fontWeight(.semibold)

                        HStack {

                            Button("Remove cup") {
                                removeCoffee()
                            }
                            .buttonStyle(.bordered)
                            .disabled(coffeeCups == 0)

                            Spacer()

                            Button("Add cup") {
                                addCoffee()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.brown)

                        }

                    }
                    .padding()
                    .background(
                        Color.brown.opacity(0.08)
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: 20)
                    )

                    // Reset button

                    Button("Reset daily counters") {
                        resetCounters()
                    }
                    .foregroundStyle(.red)

                }
                .padding()

            }
            .navigationTitle("Daily Tracker")

        }

    }

    // MARK: - Functions

    private func addWater() {
        waterIntake += glassSize
    }

    private func removeWater() {
        waterIntake = max(0, waterIntake - glassSize)
    }

    private func addCoffee() {
        coffeeCups += 1
    }

    private func removeCoffee() {
        coffeeCups = max(0, coffeeCups - 1)
    }

    private func resetCounters() {
        waterIntake = 0
        coffeeCups = 0
    }

}

#Preview {
    ContentView()
}
