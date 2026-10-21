import SwiftUI

/// A single headline number with an icon and label, for example "16 meals".
/// VoiceOver reads it as one element: "Estimated meals, 16".
struct StatTile: View {
    let title: String
    let value: String
    let systemImage: String
    var tint: Color = .accentColor
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)

            Text(value)
                .font(.title.bold())
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.primary)

            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(caption.map { "\(value). \($0)" } ?? value)
    }
}

#Preview {
    VStack {
        StatTile(title: "Estimated meals", value: "16", systemImage: "fork.knife", caption: "About 2 meals per kg")
        StatTile(title: "Discarded", value: "3", systemImage: "trash", tint: .secondary)
    }
    .padding()
    .background(Color.screenBackground)
}
