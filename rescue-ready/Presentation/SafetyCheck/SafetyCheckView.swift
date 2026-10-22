//
//  SafetyCheckView.swift
//  rescue-ready
//
//  Created by Lam Nguyen on 21/10/2026.
//


import SwiftUI

/// Displays the safety checklist for a selected food batch.
struct SafetyCheckView: View {

    @State private var viewModel: SafetyCheckViewModel

    init(viewModel: SafetyCheckViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        content
            .navigationTitle("Safety Check")
            .task {
                await viewModel.load()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            ProgressView("Loading batch")

        case .failed(let message):
            ContentUnavailableView {
                Label(
                    "Couldn't load batch",
                    systemImage: "exclamationmark.triangle"
                )
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await viewModel.load() }
                }
            }

        case .loaded:
            if let batch = viewModel.batch {
                safetyForm(for: batch)
            } else {
                ContentUnavailableView(
                    "Batch unavailable",
                    systemImage: "shippingbox"
                )
            }
        }
    }

    private func safetyForm(for batch: FoodBatch) -> some View {
        Form {
            
            Section("Food Batch") {
                LabeledContent(
                    "Food",
                    value: batch.foodDescription
                )
                
                LabeledContent(
                    "Weight",
                    value: "\(batch.weight.kilograms.formatted()) kg"
                )
                
                StatusBadge(status: batch.status)
            }
            
            Section {
                TextField(
                    "Temperature (°C)",
                    text: $viewModel.temperatureInput
                )
                .keyboardType(.decimalPad)
                .accessibilityLabel(
                    "Measured food temperature in Celsius"
                )
            } header: {
                Text("Temperature Check")
            } footer: {
                Text("Enter the measured temperature using a food thermometer.")
            }
            
            Section {
                Text(allergenSummary(for: batch))
                    .foregroundStyle(.secondary)
                
                Toggle(
                    "Confirm allergen information",
                    isOn: $viewModel.allergensConfirmed
                )
                .accessibilityHint(
                    "Confirm the available allergen information has been reviewed."
                )
            } header: {
                Text("Allergen Check")
            }
            
            Section {
                LabeledContent(
                    "Pickup time",
                    value: batch.holdWindow.startedAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                
                TextField(
                    "Total danger-zone time (minutes)",
                    text: $viewModel.dangerZoneMinutesInput
                )
                .keyboardType(.decimalPad)
                .accessibilityLabel(
                    "Cumulative time in the temperature danger zone, in minutes"
                )
                
                Toggle(
                    "I have verified the complete handling history",
                    isOn: $viewModel.handlingHistoryConfirmed
                )
                
            } header: {
                Text("Handling Information")
            } footer: {
                Text(
                    "Enter the total time food has spent between 5°C and 60°C, including preparation, storage, display and transport. Pickup time alone does not establish the complete handling history."
                )
            }
            
            Section {
                // Keep your existing Submit button
                // and saveState switch here.
                
                Section {
                    
                    Button {
                        Task {
                            await viewModel.submit()
                        }
                    } label: {
                        if viewModel.saveState == .saving {
                            ProgressView("Saving Safety Check...")
                        } else {
                            Text("Record Safety Check")
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(
                        !viewModel.canSubmit ||
                        viewModel.saveState == .saving
                    )
                    
                    // Display the result of the safety check.
                    switch viewModel.saveState {
                        
                    case .idle:
                        EmptyView()
                        
                    case .saving:
                        Text("Recording safety information...")
                            .foregroundStyle(.secondary)
                        
                    case .saved:
                        Label(
                            "Safety check recorded successfully.",
                            systemImage: "checkmark.circle"
                        )
                        
                    case .requiresReview(let reason):
                        Label(
                            "Review required: \(reason)",
                            systemImage: "exclamationmark.triangle"
                        )
                        
                    case .failed(let message):
                        Label(
                            message,
                            systemImage: "exclamationmark.circle"
                        )
                    }
                    
                } footer: {
                    
                    Text(
                        "Record a check only after verifying the food's temperature, allergens and complete handling history."
                    )
                }
            }
        }
    }
    
    private func allergenSummary(
        for batch: FoodBatch
    ) -> String {
        guard batch.allergensDeclared else {
            return "Allergen information has not been declared."
        }

        guard !batch.allergens.isEmpty else {
            return "No allergens declared."
        }

        let names = batch.allergens
            .map(\.displayName)
            .sorted()
            .joined(separator: ", ")

        return "Declared allergens: \(names)"
    }
}
