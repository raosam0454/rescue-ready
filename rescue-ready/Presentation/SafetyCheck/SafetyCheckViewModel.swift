import Foundation
import Observation

/// State and actions for recording a safety check on one batch.
@MainActor
@Observable
final class SafetyCheckViewModel {
    enum State: Equatable {
        case editing
        case saving
        /// The batch passed and is ready for handover. Carries the expiry alert message.
        case passed(String)
        /// The batch failed and can only be discarded. Carries the reason.
        case blocked(String)
        /// The check could not be saved. The volunteer can try again.
        case failed(String)
    }

    private(set) var batch: FoodBatch
    var temperatureText = ""
    var allergensConfirmed: Bool
    /// True when allergens were confirmed when the batch was logged, so the toggle is locked on.
    let allergensConfirmedAtPickup: Bool
    private(set) var state: State = .editing

    private let recordCheck: RecordSafetyCheckUseCase
    private let now: () -> Date

    init(batch: FoodBatch, recordCheck: RecordSafetyCheckUseCase, now: @escaping () -> Date) {
        self.batch = batch
        self.recordCheck = recordCheck
        self.now = now
        allergensConfirmed = batch.allergensDeclared
        allergensConfirmedAtPickup = batch.allergensDeclared
    }

    // MARK: - Derived state

    /// Accepts "72", "4.5", "4,5" and negative readings for frozen food.
    var temperatureCelsius: Double? {
        Double(temperatureText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    /// A live warning while typing, using the same rule as the use case.
    var temperatureWarning: String? {
        guard let celsius = temperatureCelsius else { return nil }
        guard let temperature = try? Temperature(celsius: celsius) else {
            return DomainError.invalidTemperatureReading.errorDescription
        }
        return temperature.isInDangerZone ? DomainError.temperatureOutOfRange.errorDescription : nil
    }

    var canSubmit: Bool {
        guard temperatureCelsius != nil, allergensConfirmed else { return false }
        switch state {
        case .editing, .failed: return true
        case .saving, .passed, .blocked: return false
        }
    }

    var isFinished: Bool {
        switch state {
        case .passed, .blocked: return true
        case .editing, .saving, .failed: return false
        }
    }

    var timeRemaining: TimeInterval {
        batch.holdWindow.remaining(at: now())
    }

    // MARK: - Actions

    func submit() async {
        guard let celsius = temperatureCelsius, canSubmit else { return }
        state = .saving
        do {
            let result = try await recordCheck.execute(batchID: batch.id, temperatureCelsius: celsius,
                                                       allergensConfirmed: allergensConfirmed)
            batch = result.batch
            if let violation = result.violation {
                state = .blocked(violation.errorDescription ?? "")
            } else {
                state = .passed(Self.alertMessage(for: result.alert))
            }
        } catch {
            let domainError = (error as? DomainError) ?? .storageFailure
            state = .failed(domainError.errorDescription ?? "")
        }
    }

    func dismissError() {
        if case .failed = state { state = .editing }
    }

    static func alertMessage(for alert: ExpiryAlertResult?) -> String {
        switch alert {
        case .scheduled(let date):
            return "We'll remind you at \(date.formatted(date: .omitted, time: .shortened)), 15 minutes before its safe hold time ends."
        case .notificationsDenied:
            return "Expiry alerts are off, so keep an eye on the time left in the batch list."
        case .tooLateToAlert:
            return "Less than 15 minutes of safe hold time is left. Hand it over now."
        case .failed, .none:
            return "Hand it over before its safe hold time ends."
        }
    }
}
