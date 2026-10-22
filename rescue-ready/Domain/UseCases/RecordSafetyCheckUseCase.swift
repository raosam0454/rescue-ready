//
//  RecordSafetyCheckUseCase.swift
//  rescue-ready
//
//  Created by Lam Nguyen on 21/10/2026.
//

import Foundation


/// Result of evaluating food handling information.
enum SafetyAssessment: Equatable {
    case passed
    case failed(reason: String)
    case requiresReview(reason: String)
}

/// Contract for evaluating a batch's safety information.
/// Concrete rules must be verified before implementation.
protocol SafetyCheckAssessing {
    func assess(
        batch: FoodBatch,
        temperature: Temperature,
        input: SafetyCheckInput,
        at checkedAt: Date
    ) -> SafetyAssessment
}


/// Handles the domain workflow for recording a food batch safety check.
/// Safety validation rules will be implemented after
/// the team confirms the food handling requirements.
/// Input submitted by a volunteer for a safety check.
struct SafetyCheckInput {

    let batchID: Identifier<FoodBatch>
    let temperatureCelsius: Double
    let allergensConfirmed: Bool

    // Total cumulative time spent between 5°C and 60°C,
    // including preparation, storage, display and transport.
    let cumulativeDangerZoneSeconds: TimeInterval?

    // Volunteer has verified the complete handling history.
    let handlingHistoryConfirmed: Bool

    init(
        batchID: Identifier<FoodBatch>,
        temperatureCelsius: Double,
        allergensConfirmed: Bool,
        cumulativeDangerZoneSeconds: TimeInterval? = nil,
        handlingHistoryConfirmed: Bool = false
    ) {
        self.batchID = batchID
        self.temperatureCelsius = temperatureCelsius
        self.allergensConfirmed = allergensConfirmed
        self.cumulativeDangerZoneSeconds =
            cumulativeDangerZoneSeconds
        self.handlingHistoryConfirmed =
            handlingHistoryConfirmed
    }
}

enum SafetyCheckEligibilityError: LocalizedError, Equatable {
    case alreadyChecked

    var errorDescription: String? {
        switch self {
        case .alreadyChecked:
            return "This batch has already been checked."
        }
    }
}


enum SafetyCheckExecutionResult: Equatable {
    case recorded(SafetyCheck)
    case requiresReview(reason: String)
}


/// Evaluates verified temperature-control history.
///
/// Applies a conservative version of the 2-hour/4-hour
/// rule for potentially hazardous food.
struct FoodSafetyAssessor: SafetyCheckAssessing {

    func assess(
        batch: FoodBatch,
        temperature: Temperature,
        input: SafetyCheckInput,
        at checkedAt: Date
    ) -> SafetyAssessment {

        // Never approve food without verified history.
        guard input.handlingHistoryConfirmed,
              let duration = input.cumulativeDangerZoneSeconds
        else {
            return .requiresReview(
                reason: "Complete handling history must be verified."
            )
        }

        // Reject invalid duration values.
        guard duration.isFinite, duration >= 0 else {
            return .requiresReview(
                reason: "Enter a valid cumulative handling duration."
            )
        }

        let twoHours: TimeInterval = 2 * 60 * 60
        let fourHours: TimeInterval = 4 * 60 * 60

        // Four hours or more: food must not be used.
        if duration >= fourHours {
            return .failed(
                reason: "Cumulative danger-zone time is four hours or more."
            )
        }

        // Two to four hours: immediate use only.
        // Our current app cannot verify immediate-use conditions.
        if duration >= twoHours {
            return .requiresReview(
                reason: "Immediate-use conditions require verification."
            )
        }

        // Conservative handling of a current reading
        // in the temperature danger zone.
        if temperature.isInDangerZone {
            return .requiresReview(
                reason: "Current temperature requires handling review."
            )
        }

        return .passed
    }
}

struct RecordSafetyCheckUseCase {
    
    /// Evaluates food handling information.
    /// Nil until the team approves the safety rules.
    let assessor: (any SafetyCheckAssessing)?

    init(
        batches: any BatchRepository,
        now: @escaping () -> Date,
        assessor: (any SafetyCheckAssessing)? = nil
    ) {
        self.batches = batches
        self.now = now
        self.assessor = assessor
    }


    let batches: any BatchRepository

    /// Injected to make time-dependent behaviour testable.
    let now: () -> Date

    /// Loads a batch before performing its safety check.
    func loadBatch(
        id: Identifier<FoodBatch>
    ) async throws -> FoodBatch {

        let batch: FoodBatch?

        do {
            batch = try await batches.batch(id: id)
        } catch {
            throw DomainError.storageFailure
        }

        guard let batch else {
            throw DomainError.batchNotFound
        }

        return batch
    }
    
    /// Loads a batch and rejects batches that are already closed.
    func loadOpenBatch(
        id: Identifier<FoodBatch>
    ) async throws -> FoodBatch {

        let batch = try await loadBatch(id: id)

        guard batch.status.isOpen else {
            throw DomainError.batchAlreadyClosed
        }

        return batch
    }
    
    /// Validates a temperature reading before recording a safety check.
    ///
    /// This checks input plausibility only.
    /// It does not determine whether food is safe.
    func validateTemperature(
        from input: SafetyCheckInput
    ) throws -> Temperature {

        try Temperature(celsius: input.temperatureCelsius)
    }
    
    /// Only batches awaiting their first safety check
    /// are eligible for validation.
    func loadCheckableBatch(
        id: Identifier<FoodBatch>
    ) async throws -> FoodBatch {

        let batch = try await loadOpenBatch(id: id)

        guard batch.status == .awaitingCheck else {
            throw SafetyCheckEligibilityError.alreadyChecked
        }

        return batch
    }
    
    /// Ensures allergen information has been declared
    /// and reviewed by the volunteer.
    ///
    /// Missing confirmation blocks submission but does
    /// not permanently fail the batch.
    func validateAllergens(
        for batch: FoodBatch,
        input: SafetyCheckInput
    ) throws {

        guard batch.allergensDeclared,
              input.allergensConfirmed else {
            throw DomainError.allergensUndeclared
        }
    }
    
    /// Prepares a batch for safety evaluation.
    ///
    /// Validates batch eligibility, temperature input,
    /// and allergen confirmation.
    ///
    /// Does not determine food safety or save a check.
    func prepareCheck(
        _ input: SafetyCheckInput
    ) async throws -> (
        batch: FoodBatch,
        temperature: Temperature
    ) {

        // 1. Ensure the batch exists and can be checked.
        let batch = try await loadCheckableBatch(
            id: input.batchID
        )

        // 2. Validate the temperature reading.
        let temperature = try validateTemperature(
            from: input
        )

        // 3. Confirm the allergen information.
        try validateAllergens(
            for: batch,
            input: input
        )

        return (batch, temperature)
    }
    
    /// Persists an evaluated safety outcome and updates
    /// the corresponding batch status atomically.
    ///
    /// This method does not evaluate food safety.
    /// It must only be called after domain validation.
    private func persistOutcome(
        for batch: FoodBatch,
        temperature: Temperature,
        outcome: SafetyOutcome
    ) async throws -> SafetyCheck {

        var updatedBatch = batch

        switch outcome {
        case .passed:
            updatedBatch.status = .cleared

        case .failed:
            updatedBatch.status = .failedCheck
        }

        let check = SafetyCheck(
            id: Identifier(),
            batchID: batch.id,
            temperature: temperature,
            checkedAt: now(),
            outcome: outcome
        )

        do {
            try await batches.record(
                check,
                updating: updatedBatch
            )
        } catch {
            throw DomainError.storageFailure
        }

        return check
    }
    
    /// Executes a safety check using the configured assessor.
    ///
    /// Input validation runs first. Only an assessor's passed
    /// or failed decision can produce a recorded outcome.
    func execute(
        _ input: SafetyCheckInput
    ) async throws -> SafetyCheckExecutionResult {

        // 1. Validate input and batch eligibility.
        let prepared = try await prepareCheck(input)

        // 2. Do not approve food without assessment rules.
        guard let assessor else {
            return .requiresReview(
                reason: "Safety assessment rules have not been configured."
            )
        }

        // 3. Evaluate the batch using the injected assessor.
        let assessment = assessor.assess(
            batch: prepared.batch,
            temperature: prepared.temperature,
            input: input,
            at: now()
        )

        // 4. Handle the assessment result.
        switch assessment {

        case .passed:
            let check = try await persistOutcome(
                for: prepared.batch,
                temperature: prepared.temperature,
                outcome: .passed
            )
            return .recorded(check)

        case .failed(let reason):
            let check = try await persistOutcome(
                for: prepared.batch,
                temperature: prepared.temperature,
                outcome: .failed(reason: reason)
            )
            return .recorded(check)

        case .requiresReview(let reason):
            return .requiresReview(reason: reason)
        }
    }
}
