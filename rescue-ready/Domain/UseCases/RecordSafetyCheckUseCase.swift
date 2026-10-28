import Foundation

/// The outcome of a recorded safety check.
struct SafetyCheckResult: Equatable {
    let batch: FoodBatch
    let check: SafetyCheck
    /// The food safety rule the batch broke, or nil if it passed.
    let violation: DomainError?
    /// What happened to the expiry alert after a pass. Nil when the check failed
    /// or the alert could not be set up; a missing alert never blocks the check.
    let alert: ExpiryAlertResult?

    var passed: Bool { violation == nil }
}

/// Records a temperature and allergen check for a batch that is awaiting one.
///
/// Rules:
/// - the reading must be a plausible temperature
/// - only a batch awaiting its check can be checked; closed batches cannot
/// - allergens must be confirmed before a check can be recorded
/// - the batch fails if its safe hold time has run out, or if the food is in the
///   5°C to 60°C danger zone. A failed check is still recorded, so there is a safety record
/// - a passed batch is cleared for handover and gets an expiry alert
struct RecordSafetyCheckUseCase {
    let batches: BatchRepository
    let scheduleExpiryAlert: ScheduleExpiryAlertUseCase
    /// Injected so tests control time. Never call `Date()` directly in a use case.
    let now: () -> Date

    func execute(
        batchID: Identifier<FoodBatch>,
        temperatureCelsius: Double,
        allergensConfirmed: Bool
    ) async throws -> SafetyCheckResult {
        let temperature = try Temperature(celsius: temperatureCelsius)

        let stored: FoodBatch?
        do {
            stored = try await batches.batch(id: batchID)
        } catch {
            throw DomainError.storageFailure
        }
        guard var batch = stored else { throw DomainError.batchNotFound }

        switch batch.status {
        case .awaitingCheck:
            break
        case .cleared, .failedCheck:
            throw DomainError.alreadyChecked
        case .handedOver, .discarded:
            throw DomainError.batchAlreadyClosed
        }

        // Missing allergen information is incomplete input, not unsafe food,
        // so it blocks the check instead of failing the batch.
        guard batch.allergensDeclared || allergensConfirmed else { throw DomainError.allergensUndeclared }
        batch.allergensDeclared = true

        let timestamp = now()
        let violation = Self.violation(for: batch, temperature: temperature, at: timestamp)
        let outcome: SafetyOutcome = violation.map { .failed(reason: $0.errorDescription ?? "") } ?? .passed
        let check = SafetyCheck(id: Identifier(), batchID: batch.id, temperature: temperature,
                                checkedAt: timestamp, outcome: outcome)
        batch.status = violation == nil ? .cleared : .failedCheck

        do {
            try await batches.record(check, updating: batch)
        } catch {
            throw DomainError.storageFailure
        }

        var alert: ExpiryAlertResult?
        if violation == nil {
            alert = try? await scheduleExpiryAlert.execute(batchID: batch.id)
        }
        return SafetyCheckResult(batch: batch, check: check, violation: violation, alert: alert)
    }

    /// The first food safety rule the batch breaks, checked by severity: time out, then temperature.
    static func violation(for batch: FoodBatch, temperature: Temperature, at date: Date) -> DomainError? {
        if batch.holdWindow.hasExpired(at: date) { return .exceededSafeHoldTime }
        if temperature.isInDangerZone { return .temperatureOutOfRange }
        return nil
    }
}
