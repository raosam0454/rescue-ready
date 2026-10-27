import SwiftUI

/// Record a temperature and allergen check for one batch.
///
/// Opened from the batch list for a batch awaiting its check. Calls `onFinished`
/// when the volunteer is done, so the list can refresh.
struct SafetyCheckView: View {
    @State private var viewModel: SafetyCheckViewModel
    @FocusState private var isTemperatureFocused: Bool
    @Environment(\.dismiss) private var dismiss
    private let onFinished: () -> Void

    init(viewModel: SafetyCheckViewModel, onFinished: @escaping () -> Void = {}) {
        _viewModel = State(initialValue: viewModel)
        self.onFinished = onFinished
    }

    var body: some View {
        Form {
            BatchSection(batch: viewModel.batch)

            switch viewModel.state {
            case .passed(let message):
                ResultSection(passed: true, title: "Passed safety check", message: message)
                doneSection
            case .blocked(let reason):
                ResultSection(passed: false, title: "Not safe to hand over",
                              message: "\(reason) Discard it from the batch list with a reason.")
                doneSection
            case .editing, .saving, .failed:
                temperatureSection
                allergenSection
                submitSection
            }
        }
        .navigationTitle("Safety Check")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isTemperatureFocused = false }
            }
        }
        .alert("Couldn't save check", isPresented: isShowingError) {
            Button("OK") { viewModel.dismissError() }
        } message: {
            Text(errorMessage)
        }
        .sensoryFeedback(trigger: viewModel.state) { _, newState in
            switch newState {
            case .passed: return .success
            case .blocked: return .error
            default: return nil
            }
        }
        .onAppear {
            if viewModel.state == .editing { isTemperatureFocused = true }
        }
    }

    // MARK: - Sections

    private var temperatureSection: some View {
        Section {
            HStack {
                TextField("Probe reading", text: $viewModel.temperatureText)
                    .keyboardType(.numbersAndPunctuation)
                    .focused($isTemperatureFocused)
                    .accessibilityLabel("Temperature in degrees Celsius")
                Text("°C")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            if let warning = viewModel.temperatureWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Temperature")
        } footer: {
            Text("Hot food must be 60°C or above. Cold food must be 5°C or below.")
        }
    }

    private var allergenSection: some View {
        Section {
            Toggle("Allergens confirmed with the venue", isOn: $viewModel.allergensConfirmed)
                .disabled(viewModel.allergensConfirmedAtPickup)
        } footer: {
            Text(viewModel.allergensConfirmedAtPickup
                 ? "Allergens were confirmed when this batch was logged."
                 : "Check the allergens with the venue before recording the check.")
        }
    }

    private var submitSection: some View {
        Section {
            Button {
                isTemperatureFocused = false
                Task { await viewModel.submit() }
            } label: {
                if viewModel.state == .saving {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Record Check")
                }
            }
            .buttonStyle(.primary)
            .disabled(!viewModel.canSubmit)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    private var doneSection: some View {
        Section {
            Button("Done") {
                onFinished()
                dismiss()
            }
            .buttonStyle(.primary)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Error alert

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { if case .failed = viewModel.state { return true } else { return false } },
            set: { if !$0 { viewModel.dismissError() } }
        )
    }

    private var errorMessage: String {
        if case .failed(let message) = viewModel.state { return message }
        return ""
    }
}

// MARK: - Sections

private struct BatchSection: View {
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

private struct ResultSection: View {
    let passed: Bool
    let title: String
    let message: String

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: passed ? "checkmark.seal.fill" : "xmark.octagon.fill")
                    .font(.headline)
                    .foregroundStyle(passed ? Color.statusSuccess : Color.statusDanger)
                Text(message)
                    .font(.subheadline)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Previews

#Preview("Awaiting check") {
    NavigationStack {
        if let viewModel = SafetyCheckViewModel.preview() {
            SafetyCheckView(viewModel: viewModel)
        }
    }
}

#Preview("Dark") {
    NavigationStack {
        if let viewModel = SafetyCheckViewModel.preview() {
            SafetyCheckView(viewModel: viewModel)
        }
    }
    .preferredColorScheme(.dark)
}

extension SafetyCheckViewModel {
    /// A view model for a sample batch awaiting its check, for SwiftUI previews.
    static func preview() -> SafetyCheckViewModel? {
        let now = Date()
        let store = SampleData.makeStore(now: now)
        guard let batch = store.batches.values.first(where: { $0.status == .awaitingCheck }) else { return nil }
        let batches = InMemoryBatchRepository(store: store)
        let clock = { now }
        let alerts = ScheduleExpiryAlertUseCase(batches: batches, notifications: InMemoryNotificationScheduler(), now: clock)
        return SafetyCheckViewModel(
            batch: batch,
            recordCheck: RecordSafetyCheckUseCase(batches: batches, scheduleExpiryAlert: alerts, now: clock),
            now: clock
        )
    }
}
