import SwiftUI

/// Open batches, soonest safe hold deadline first, with the time left on each.
struct BatchListView: View {
    @State private var viewModel: BatchListViewModel
    private let makeHandoverViewModel: (FoodBatch) -> HandoverViewModel

    init(viewModel: BatchListViewModel, makeHandoverViewModel: @escaping (FoodBatch) -> HandoverViewModel) {
        _viewModel = State(initialValue: viewModel)
        self.makeHandoverViewModel = makeHandoverViewModel
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Batches")
                .task { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .loading:
            ProgressView("Loading batches")
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't load batches", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await viewModel.load() } }
            }
        case .loaded:
            list
        }
    }

    private var list: some View {
        List {
            if viewModel.notificationsDenied {
                NotificationsDeniedBanner()
            }

            if viewModel.batches.isEmpty {
                ContentUnavailableView(
                    "No open batches",
                    systemImage: "tray",
                    description: Text("Batches from your pickups will appear here until they are handed over or discarded.")
                )
                .listRowBackground(Color.clear)
            } else {
                let expired = viewModel.batches.filter(\.hasExpired)
                let active = viewModel.batches.filter { !$0.hasExpired }

                if !expired.isEmpty {
                    Section {
                        rows(expired)
                    } header: {
                        Text("Expired")
                    } footer: {
                        Text("These are past their safe hold time. Discard them.")
                    }
                }
                if !active.isEmpty {
                    Section("Open") {
                        rows(active)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await viewModel.load() }
    }

    private func rows(_ items: [ExpiringBatch]) -> some View {
        ForEach(items) { item in
            NavigationLink {
                // Reload when done so the handed over or discarded batch leaves the list.
                HandoverView(viewModel: makeHandoverViewModel(item.batch)) {
                    Task { await viewModel.load() }
                }
            } label: {
                // Redraws every minute so the time left stays current while the screen is open.
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    BatchRow(batch: item.batch, timeRemaining: item.batch.holdWindow.remaining(at: context.date))
                }
            }
        }
    }
}

// MARK: - Rows

private struct BatchRow: View {
    let batch: FoodBatch
    let timeRemaining: TimeInterval

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: timeSymbol)
                .font(.title3)
                .foregroundStyle(timeColor)
                .frame(width: 40, height: 40)
                .background(timeColor.opacity(0.15), in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(batch.foodDescription)
                        .font(.headline)
                    Spacer()
                    Text(batch.weight.kilograms.kilogramsText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    StatusBadge(status: batch.status)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Spacer()
                    // Text stays in the primary colour so it keeps enough contrast in Light Mode.
                    Text(timeText)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private var isUrgent: Bool { timeRemaining < 30 * 60 }

    private var timeText: String {
        guard timeRemaining > 0 else { return "Expired" }
        let left = Duration.seconds(timeRemaining)
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
        return "\(left) left"
    }

    private var timeSymbol: String {
        if timeRemaining <= 0 { return "xmark.circle" }
        return isUrgent ? "exclamationmark.triangle" : "timer"
    }

    private var timeColor: Color {
        if timeRemaining <= 0 { return .red }
        return isUrgent ? .orange : .secondary
    }
}

/// Explains that expiry alerts are off, with a shortcut to turn them back on.
private struct NotificationsDeniedBanner: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Expiry alerts are off", systemImage: "bell.slash")
                .font(.headline)
            Text("You won't be warned before a batch runs out of safe hold time. Keep an eye on this list, or turn notifications on in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .frame(minHeight: 44)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Previews

#Preview("Batches") {
    let container = AppContainer.preview()
    BatchListView(viewModel: .preview(), makeHandoverViewModel: container.makeHandoverViewModel)
}

#Preview("Alerts off") {
    let container = AppContainer.preview()
    BatchListView(viewModel: .preview(permission: .denied), makeHandoverViewModel: container.makeHandoverViewModel)
        .preferredColorScheme(.dark)
}

extension BatchListViewModel {
    /// A view model backed by sample data, for SwiftUI previews.
    static func preview(permission: NotificationPermission = .authorized) -> BatchListViewModel {
        let now = Date()
        let store = SampleData.makeStore(now: now)
        return BatchListViewModel(
            fetchExpiringBatches: FetchExpiringBatchesUseCase(batches: InMemoryBatchRepository(store: store),
                                                              now: { now }),
            notifications: InMemoryNotificationScheduler(permission: permission)
        )
    }
}
