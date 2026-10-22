import Charts
import SwiftUI

/// Shows how much food the group has rescued and where it went.
struct ImpactDashboardView: View {
    @State private var viewModel: ImpactViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(viewModel: ImpactViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Impact")
                .background(Color.screenBackground)
                .task { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView("Adding up your impact")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't load impact", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await viewModel.load() } }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: Theme.minimumTouchTarget)
            }
        case .loaded(let stats) where stats.isEmpty:
            ContentUnavailableView(
                "No food rescued yet",
                systemImage: "leaf",
                description: Text("Hand over your first batch and the food you've saved will show up here.")
            )
        case .loaded(let stats):
            dashboard(stats)
        }
    }

    // MARK: - Dashboard

    private func dashboard(_ stats: ImpactStats) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                heroCard(stats)

                LazyVGrid(columns: columns, spacing: Theme.Spacing.medium) {
                    StatTile(title: "Estimated meals", value: stats.estimatedMeals.formatted(),
                             systemImage: "fork.knife", tint: .statusSuccess,
                             caption: "About \(ImpactStats.mealsPerKilogram.formatted()) meals per kg")
                    StatTile(title: "Batches delivered", value: stats.batchesHandedOver.formatted(),
                             systemImage: "shippingbox", tint: .statusInfo,
                             caption: viewModel.rescueRateText.map { "\($0) of closed batches" })
                    StatTile(title: "Discarded", value: stats.batchesDiscarded.formatted(),
                             systemImage: "trash", tint: .secondary,
                             caption: "\(stats.kilogramsDiscarded.kilogramsText), not counted in totals")
                }

                if !stats.dropPoints.isEmpty {
                    dropPointSection(stats.dropPoints)
                }

                Text("Totals only include batches that passed a safety check and were handed over to a drop point.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Spacing.xSmall)
            }
            .padding(Theme.Spacing.medium)
            .animation(.default, value: stats)
        }
        .refreshable { await viewModel.load() }
    }

    /// Two columns normally, one column at accessibility text sizes so numbers never clip.
    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.medium, alignment: .top), count: count)
    }

    private func heroCard(_ stats: ImpactStats) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Label("Food saved", systemImage: "leaf.fill")
                .font(.headline)
                .foregroundStyle(Color.accentColor)
            Text(stats.kilogramsSaved.kilogramsText)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("rescued and delivered to community pantries")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Food saved")
        .accessibilityValue("\(stats.kilogramsSaved.kilogramsText), rescued and delivered to community pantries")
    }

    private func dropPointSection(_ dropPoints: [DropPointImpact]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            Text("Where it went")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Chart(dropPoints) { dropPoint in
                BarMark(
                    x: .value("Kilograms", dropPoint.kilograms),
                    y: .value("Drop point", dropPoint.name)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .cornerRadius(6)
                .accessibilityLabel(dropPoint.name)
                .accessibilityValue("\(dropPoint.kilograms.kilogramsText), \(batchCount(dropPoint.batches))")
            }
            .chartXAxisLabel("kg")
            .frame(height: CGFloat(max(dropPoints.count, 1)) * 56)

            ForEach(dropPoints) { dropPoint in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dropPoint.name)
                            .font(.body.weight(.medium))
                        Text(batchCount(dropPoint.batches))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: Theme.Spacing.small)
                    Text(dropPoint.kilograms.kilogramsText)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }

    private func batchCount(_ count: Int) -> String {
        count == 1 ? "1 batch" : "\(count) batches"
    }
}

#Preview("Light") {
    ImpactDashboardView(viewModel: AppContainer.preview().makeImpactViewModel())
}

#Preview("Dark, large text") {
    ImpactDashboardView(viewModel: AppContainer.preview().makeImpactViewModel())
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility2)
}
