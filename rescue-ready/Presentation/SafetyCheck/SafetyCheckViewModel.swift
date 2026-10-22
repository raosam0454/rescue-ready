//
//  SafetyCheckViewModel.swift
//  rescue-ready
//
//  Created by Lam Nguyen on 21/10/2026.
//


import Foundation
import Observation

/// State and actions for the Safety Check screen.
@MainActor
@Observable
final class SafetyCheckViewModel {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case requiresReview(String)
        case failed(String)
    }

    private(set) var batch: FoodBatch?
    private(set) var loadState: LoadState = .idle
    private(set) var saveState: SaveState = .idle

    // User inputs
    var temperatureInput: String = ""
    var allergensConfirmed: Bool = false
    
    
    // Total cumulative time spent in the temperature danger zone.
    var dangerZoneMinutesInput: String = ""

    // Volunteer confirms the complete handling history.
    var handlingHistoryConfirmed: Bool = false


    private let recordSafetyCheck: RecordSafetyCheckUseCase
    private let batchID: Identifier<FoodBatch>

    init(
        recordSafetyCheck: RecordSafetyCheckUseCase,
        batchID: Identifier<FoodBatch>
    ) {
        self.recordSafetyCheck = recordSafetyCheck
        self.batchID = batchID
    }

    var canSubmit: Bool {

        // 1. Batch must be loaded and awaiting check.
        guard loadState == .loaded,
              let batch,
              batch.status == .awaitingCheck else {
            return false
        }

        // 2. Allergen information must be confirmed.
        guard batch.allergensDeclared,
              allergensConfirmed else {
            return false
        }

        // 3. A safety assessor must be configured.
        guard recordSafetyCheck.assessor != nil else {
            return false
        }

        // 4. Prevent duplicate submissions.
        guard saveState != .saving,
              saveState != .saved else {
            return false
        }

        // 5. Validate temperature input.
        let temperatureText = temperatureInput
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let temperature = Double(temperatureText),
              temperature.isFinite,
              Temperature.plausibleRange.contains(temperature) else {
            return false
        }

        // 6. Validate cumulative danger-zone duration.
        let minutesText = dangerZoneMinutesInput
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let minutes = Double(minutesText),
              minutes.isFinite,
              minutes >= 0,
              minutes <= Double.greatestFiniteMagnitude / 60 else {
            return false
        }

        // 7. Complete handling history must be verified.
        guard handlingHistoryConfirmed else {
            return false
        }

        return true
    }

    func load() async {
        loadState = .loading

        do {
            batch = try await recordSafetyCheck.loadBatch(id: batchID)

            // Restore existing allergen declaration information.
            allergensConfirmed = false
            
            loadState = .loaded
        } catch {
            loadState = .failed(Self.message(for: error))
        }
    }

    func submit() async {

        // Prevent duplicate submissions.
        guard saveState != .saving else {
            return
        }

        // Ensure a batch has been loaded.
        guard let batch else {
            saveState = .failed(
                "Food batch has not been loaded."
            )
            return
        }

        // Convert temperature input into a number.
        let temperatureText = temperatureInput
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let temperature = Double(temperatureText) else {
            saveState = .failed(
                "Enter a valid temperature in °C."
            )
            return
        }

        saveState = .saving

        do {
            let minutes = Double(
                dangerZoneMinutesInput.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            )

            let input = SafetyCheckInput(
                batchID: batch.id,
                temperatureCelsius: temperature,
                allergensConfirmed: allergensConfirmed,
                cumulativeDangerZoneSeconds: minutes.map { $0 * 60 },
                handlingHistoryConfirmed: handlingHistoryConfirmed
            )

            let result = try await recordSafetyCheck.execute(input)

            switch result {

            case .recorded(let check):
                // Repository has already saved the result.
                var updatedBatch = batch

                updatedBatch.status = check.outcome.isPassed
                    ? .cleared
                    : .failedCheck

                self.batch = updatedBatch
                saveState = .saved

            case .requiresReview(let reason):
                // Do not mark the batch as cleared.
                saveState = .requiresReview(reason)
            }

        } catch {
            saveState = .failed(
                Self.message(for: error)
            )
        }
    }
    
    func dismissSaveResult() {
        saveState = .idle
    }

    private static func message(for error: Error) -> String {

        if let domainError = error as? DomainError {
            return domainError.errorDescription
                ?? "An unexpected error occurred."
        }

        if let eligibilityError = error as? SafetyCheckEligibilityError {
            return eligibilityError.errorDescription
                ?? "This batch cannot be checked again."
        }

        return "An unexpected error occurred."
    }
}
