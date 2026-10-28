import Foundation

/// Business rule violations, shown to the user through `errorDescription`.
enum DomainError: Error, Equatable, LocalizedError {
    // Pickup
    case eventNotFound
    case eventNotActive
    case missingEventName
    case missingVenue
    case invalidEventTimes
    case eventAlreadyFinished
    case noBatches
    case missingFoodDescription
    case invalidWeight

    // Safety check
    case invalidTemperatureReading
    case temperatureOutOfRange
    case exceededSafeHoldTime
    case allergensUndeclared
    case alreadyChecked

    // Handover and discard
    case batchNotFound
    case batchNotCleared
    case dropPointNotFound
    case dropPointClosed
    case alreadyHandedOver
    case reasonRequired

    // Alerts
    case batchAlreadyClosed

    // Storage
    case storageFailure

    var errorDescription: String? {
        switch self {
        case .eventNotFound:
            return "This event could not be found."
        case .eventNotActive:
            return "This event isn't accepting pickups right now."
        case .missingEventName:
            return "Enter the event's name."
        case .missingVenue:
            return "Enter where the event is."
        case .invalidEventTimes:
            return "The event must end after it starts and last no more than 24 hours."
        case .eventAlreadyFinished:
            return "This event finished more than 3 hours ago, so pickups can no longer be logged for it."
        case .noBatches:
            return "Add at least one batch before saving the pickup."
        case .missingFoodDescription:
            return "Describe the food in each batch."
        case .invalidWeight:
            return "Enter a weight between 0 and 500 kg."
        case .invalidTemperatureReading:
            return "That temperature reading doesn't look right. Check the probe and try again."
        case .temperatureOutOfRange:
            return "This food is in the temperature danger zone (5°C to 60°C)."
        case .exceededSafeHoldTime:
            return "This batch has been out for more than 4 hours and must be discarded."
        case .allergensUndeclared:
            return "Confirm the allergens for this batch before it can be cleared."
        case .alreadyChecked:
            return "This batch has already been checked."
        case .batchNotFound:
            return "This batch could not be found."
        case .batchNotCleared:
            return "This batch hasn't passed a safety check yet."
        case .dropPointNotFound:
            return "This drop point could not be found."
        case .dropPointClosed:
            return "This drop point is closed right now."
        case .alreadyHandedOver:
            return "This batch has already been handed over."
        case .reasonRequired:
            return "Enter a reason for discarding this batch."
        case .batchAlreadyClosed:
            return "This batch is already handed over or discarded."
        case .storageFailure:
            return "Something went wrong saving your data. Please try again."
        }
    }
}
