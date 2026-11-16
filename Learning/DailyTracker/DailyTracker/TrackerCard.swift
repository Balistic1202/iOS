
import SwiftUI

struct TrackerCard: View {

    let title: String
    let icon: String
    let value: String
    let color: Color

    var body: some View {

        VStack(alignment: .leading, spacing: 16) {

            Label(title, systemImage: icon)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)

            Text(value)
                .font(.largeTitle)
                .fontWeight(.semibold)

        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding()
        .background(color.opacity(0.08))
        .clipShape(
            RoundedRectangle(cornerRadius: 20)
        )

    }
}

#Preview {

    TrackerCard(
        title: "Water",
        icon: "drop.fill",
        value: "750 ml",
        color: .blue
    )
    .padding()

}
