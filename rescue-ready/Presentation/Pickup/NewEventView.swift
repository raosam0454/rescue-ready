import SwiftUI

/// Sheet for creating the event a volunteer is collecting from.
struct NewEventView: View {
    @State private var viewModel: NewEventViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    private let onCreated: (Event) -> Void

    private enum Field {
        case name
        case venue
    }

    init(viewModel: NewEventViewModel, onCreated: @escaping (Event) -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    TextField("Name, for example Harbour Food Festival", text: $viewModel.name)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .venue }
                    TextField("Venue", text: $viewModel.venue)
                        .focused($focusedField, equals: .venue)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                }

                Section {
                    DatePicker("Starts", selection: $viewModel.startsAt)
                    DatePicker("Ends", selection: $viewModel.endsAt, in: viewModel.startsAt...)
                } header: {
                    Text("Time")
                } footer: {
                    Text("Pickups can be logged from the start of the event until 3 hours after it ends.")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.state == .saving {
                        ProgressView()
                    } else {
                        Button("Save") { save() }
                            .disabled(!viewModel.canSave)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .alert("Couldn't create event", isPresented: isShowingError) {
                Button("OK") { viewModel.dismissError() }
            } message: {
                Text(errorMessage)
            }
            .onAppear { focusedField = .name }
        }
    }

    private func save() {
        focusedField = nil
        Task {
            if let event = await viewModel.save() {
                onCreated(event)
                dismiss()
            }
        }
    }

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

#Preview {
    NewEventView(viewModel: AppContainer.preview().makeNewEventViewModel()) { _ in }
}
