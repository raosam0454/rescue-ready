import SwiftUI

/// Hand a batch over to a drop point, or discard it with a reason.
///
/// Opened for one batch, for example from the batch list. Calls `onFinished`
/// after the volunteer acknowledges a successful handover or discard.
struct HandoverView: View {
    @State private var viewModel: HandoverViewModel
    @State private var isConfirmingDiscard = false
    @State private var hasAcknowledgedResult = false
    @FocusState private var isReasonFocused: Bool
    @Environment(\.dismiss) private var dismiss
    private let onFinished: () -> Void

    init(viewModel: HandoverViewModel, onFinished: @escaping () -> Void = {}) {
        _viewModel = State(initialValue: viewModel)
        self.onFinished = onFinished
    }

    var body: some View {
        content
            .navigationTitle("Hand Over")
            .navigationBarTitleDisplayMode(.inline)
            .task { await viewModel.load() }
            .alert(resultTitle, isPresented: isShowingResult) {
                Button("Done") { finish() }
            } message: {
                Text(resultMessage)
            }
            .alert("Couldn't update batch", isPresented: isShowingError) {
                Button("OK") { viewModel.dismissError() }
            } message: {
                Text(errorMessage)
            }
            .sensoryFeedback(.success, trigger: viewModel.isFinished)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .loading:
            ProgressView("Loading drop points")
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't load drop points", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await viewModel.load() } }
            }
        case .loaded:
            form
        }
    }

    private var form: some View {
        Form {
            BatchSummarySection(batch: viewModel.batch)

            if let reason = viewModel.handoverBlockedReason {
                Section {
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            } else {
                handoverSection
            }

            if viewModel.batch.status.isOpen {
                discardSection
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isReasonFocused = false }
            }
        }
        .confirmationDialog("Discard this batch?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
            Button("Discard Batch", role: .destructive) {
                Task { await viewModel.discardBatch() }
            }
        } message: {
            Text("It will be removed from open batches. This can't be undone.")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var handoverSection: some View {
        Section {
            if viewModel.dropPoints.isEmpty {
                Text("No drop points set up yet")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Drop point", selection: $viewModel.selectedDropPointID) {
                    ForEach(viewModel.dropPoints) { option in
                        DropPointRow(option: option)
                            .tag(Optional(option.id))
                    }
                }
                .pickerStyle(.navigationLink)
            }
        } header: {
            Text("Deliver to")
        } footer: {
            if let selected = viewModel.selectedDropPoint, !selected.isOpen {
                Text("\(selected.dropPoint.name) is closed right now. Choose an open drop point.")
            }
        }

        Section {
            Button {
                Task { await viewModel.handOverBatch() }
            } label: {
                if viewModel.isWorking {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Confirm Handover")
                }
            }
            .buttonStyle(.primary)
            .disabled(!viewModel.canHandOver)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    private var discardSection: some View {
        Section {
            TextField("Reason, for example Lid came off in transit",
                      text: $viewModel.discardReason, axis: .vertical)
                .lineLimit(2...4)
                .focused($isReasonFocused)

            Button(role: .destructive) {
                isReasonFocused = false
                isConfirmingDiscard = true
            } label: {
                Label("Discard Batch", systemImage: "trash")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .disabled(!viewModel.canDiscard)
        } header: {
            Text("Discard")
        } footer: {
            Text("A reason is required so the group keeps an accurate safety record.")
        }
    }

    // MARK: - Alerts

    private var isShowingResult: Binding<Bool> {
        Binding(
            get: { viewModel.isFinished && !hasAcknowledgedResult },
            set: { if !$0 { hasAcknowledgedResult = true } }
        )
    }

    private var resultTitle: String {
        viewModel.actionState == .handedOver ? "Batch handed over" : "Batch discarded"
    }

    private var resultMessage: String {
        guard viewModel.actionState == .handedOver,
              let name = viewModel.selectedDropPoint?.dropPoint.name else {
            return "The batch has been removed from open batches."
        }
        return "\(viewModel.batch.foodDescription) was delivered to \(name)."
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { if case .failed = viewModel.actionState { return true } else { return false } },
            set: { if !$0 { viewModel.dismissError() } }
        )
    }

    private var errorMessage: String {
        if case .failed(let message) = viewModel.actionState { return message }
        return ""
    }

    private func finish() {
        hasAcknowledgedResult = true
        onFinished()
        dismiss()
    }
}

// MARK: - Rows

private struct BatchSummarySection: View {
    let batch: FoodBatch

    var body: some View {
        Section("Batch") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(batch.foodDescription)
                        .font(.headline)
                    Spacer()
                    Text(batch.weight.kilograms.kilogramsText)
                        .foregroundStyle(.secondary)
                }
                StatusBadge(status: batch.status)
            }
            .accessibilityElement(children: .combine)

            if batch.status.isOpen {
                // Redraws every minute so the countdown stays current while the screen is open.
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let remaining = batch.holdWindow.remaining(at: context.date)
                    LabeledContent("Safe hold time left") {
                        Text(Self.timeRemainingText(remaining))
                            .foregroundStyle(remaining > 0 ? Color.secondary : Color.red)
                    }
                }
            }

            LabeledContent("Allergens", value: allergenSummary)
        }
    }

    private static func timeRemainingText(_ remaining: TimeInterval) -> String {
        guard remaining > 0 else { return "Expired" }
        return Duration.seconds(remaining)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    private var allergenSummary: String {
        guard batch.allergensDeclared else { return "Not confirmed" }
        guard !batch.allergens.isEmpty else { return "None" }
        return batch.allergens.map(\.displayName).sorted().joined(separator: ", ")
    }
}

private struct DropPointRow: View {
    let option: DropPointOption

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(option.dropPoint.name)
            Text(option.dropPoint.address)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !option.isOpen {
                Label("Closed now", systemImage: "moon.zzz")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#Preview("Cleared batch") {
    NavigationStack {
        if let viewModel = HandoverViewModel.preview(status: .cleared) {
            HandoverView(viewModel: viewModel)
        }
    }
}

#Preview("Failed check") {
    NavigationStack {
        if let viewModel = HandoverViewModel.preview(status: .failedCheck) {
            HandoverView(viewModel: viewModel)
        }
    }
    .preferredColorScheme(.dark)
}

extension HandoverViewModel {
    /// A view model backed by sample data, for SwiftUI previews.
    /// The sample batch is shown with the given status.
    static func preview(status: BatchStatus) -> HandoverViewModel? {
        let now = Date()
        let store = SampleData.makeStore(now: now)
        guard var batch = store.batches.values.first(where: { $0.status == .cleared }) else { return nil }
        batch.status = status
        store.batches[batch.id] = batch

        let batches = InMemoryBatchRepository(store: store)
        let dropPoints = InMemoryDropPointRepository(store: store)
        let notifications = InMemoryNotificationScheduler()
        let clock = { now }
        return HandoverViewModel(
            batch: batch,
            handOver: HandOverBatchUseCase(batches: batches, dropPoints: dropPoints,
                                           notifications: notifications, now: clock),
            discard: DiscardBatchUseCase(batches: batches, notifications: notifications),
            fetchDropPoints: FetchDropPointsUseCase(dropPoints: dropPoints, now: clock),
            now: clock
        )
    }
}
