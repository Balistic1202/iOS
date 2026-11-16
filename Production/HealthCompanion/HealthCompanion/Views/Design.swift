import SwiftUI

// MARK: - Colours

enum Theme {
    static let background = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemGroupedBackground)
    static let hairline = Color.primary.opacity(0.07)
    static let chip = Color.primary.opacity(0.07)
    /// The strong fill for primary buttons: near-black in light mode, near-white in dark mode.
    static let ink = Color.primary
    static let onInk = Color(.systemBackground)
    static let accent = Color(red: 0.24, green: 0.66, blue: 0.44)
    static let cardRadius: CGFloat = 24
}

/// Soft page background with a faint warm wash at the top.
struct AppBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            Theme.background
            LinearGradient(colors: [Color.orange.opacity(0.10), Color.pink.opacity(0.05), .clear],
                           startPoint: .topTrailing, endPoint: .bottomLeading)
                .frame(height: 320)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Cards

private struct CardModifier: ViewModifier {
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.hairline))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
    }
}

extension View {
    func card(padding: CGFloat = 18) -> some View { modifier(CardModifier(padding: padding)) }

    /// Gives a Form or List the app background instead of the system grouped look.
    func themedForm() -> some View {
        scrollContentBackground(.hidden).background(AppBackground())
    }
}

/// A scrolling page of cards on the app background.
struct CardPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(AppBackground())
    }
}

/// Side by side at ordinary text sizes, stacked when the user has chosen an accessibility text size.
struct AdaptiveStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var alignment: VerticalAlignment = .center
    var spacing: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: spacing) { content }
        } else {
            HStack(alignment: alignment, spacing: spacing) { content }
        }
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.title3.weight(.semibold))
            .padding(.top, 10)
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

struct CardTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
    }
}

struct Footnote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A title on the left and a value on the right, for rows inside a card.
struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        AdaptiveStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.onInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.ink.opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.3), in: Capsule())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.chip.opacity(configuration.isPressed ? 0.6 : 1), in: Capsule())
    }
}

// MARK: - Nutrient look

extension Nutrient {
    var symbol: String {
        switch self {
        case .energy: "flame.fill"
        case .protein: "dumbbell.fill"
        case .carbohydrate: "leaf.fill"
        case .fat: "drop.fill"
        case .saturatedFat: "drop.halffull"
        case .totalSugars: "cube.fill"
        case .addedSugars: "plus.circle.fill"
        case .fibre: "carrot.fill"
        case .salt: "circle.dotted"
        }
    }

    var tint: Color {
        switch self {
        case .energy: .primary
        case .protein: Color(red: 0.86, green: 0.36, blue: 0.36)
        case .carbohydrate: Color(red: 0.87, green: 0.58, blue: 0.33)
        case .fat: Color(red: 0.36, green: 0.56, blue: 0.86)
        case .saturatedFat: .indigo
        case .totalSugars: .pink
        case .addedSugars: .purple
        case .fibre: Theme.accent
        case .salt: .teal
        }
    }

    var shortTitle: String {
        switch self {
        case .carbohydrate: "Carbs"
        case .saturatedFat: "Saturates"
        case .totalSugars: "Sugars"
        case .addedSugars: "Added sugars"
        default: title
        }
    }
}

/// A small rounded tile: icon and name on top, a bold value underneath.
struct MetricTile: View {
    let nutrient: Nutrient
    /// `nil` means unknown, which is shown as a dash and never as zero.
    let value: String?
    var caption: String?
    var emphasised = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: nutrient.symbol)
                    .font(.caption)
                    .foregroundStyle(nutrient.tint)
                Text(nutrient.shortTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(value ?? "–")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(emphasised ? nutrient.tint.opacity(0.6) : Theme.hairline, lineWidth: emphasised ? 1.5 : 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(nutrient.title): \(value ?? "not known")\(caption.map { ", \($0)" } ?? "")\(emphasised ? ", in your focus" : "")")
    }
}

/// The large energy card: a small caption, a big number, and a flame badge.
struct EnergyCard: View {
    /// `nil` means unknown.
    let value: String?
    let unit: String
    let caption: String

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value ?? "–")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    if value != nil {
                        Text(unit)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "flame.fill")
                .font(.title2)
                .frame(width: 64, height: 64)
                .background(Theme.chip, in: Circle())
                .accessibilityHidden(true)
        }
        .card(padding: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Energy: \(value.map { "\($0) \(unit)" } ?? "not known"). \(caption)")
    }
}

// MARK: - Floating tab bar

enum AppTab: String, CaseIterable, Identifiable {
    case today, history, you
    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .history: "History"
        case .you: "You"
        }
    }

    func symbol(selected: Bool) -> String {
        switch self {
        case .today: selected ? "house.fill" : "house"
        case .history: selected ? "chart.bar.fill" : "chart.bar"
        case .you: selected ? "person.fill" : "person"
        }
    }
}

struct FloatingTabBar: View {
    @Binding var selection: AppTab
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 2) {
                ForEach(AppTab.allCases) { tab in
                    let selected = selection == tab
                    Button {
                        selection = tab
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.symbol(selected: selected))
                                .font(.body.weight(.semibold))
                            Text(tab.title)
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selected ? Theme.chip : Color.clear, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }
            .padding(6)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.hairline))
            .shadow(color: .black.opacity(0.08), radius: 14, y: 6)

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.onInk)
                    .frame(width: 58, height: 58)
                    .background(Theme.ink, in: Circle())
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Scan a label")
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 2)
        // Like the system tab bar, this stays compact; labels are still read out in full.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}
