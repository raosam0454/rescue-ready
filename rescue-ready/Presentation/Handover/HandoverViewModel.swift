import Foundation
import Observation

/// State and actions for handing over or discarding one batch.
@MainActor
@Observable
final class HandoverViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    enum ActionState: Equatable {
        case idle
        case working
        case handedOver
        case discarded
        case failed(String)
    }

    private(set) var batch: FoodBatch
    private(set) var dropPoints: [DropPointOption] = []
    var selectedDropPointID: Identifier<DropPoint>?
    var discardReason = ""
    private(set) var loadState: LoadState = .loading
    private(set) var actionState: ActionState = .idle

    private let handOver: HandOverBatchUseCase
    private let discard: DiscardBatchUseCase
    private let fetchDropPoints: FetchDropPointsUseCase
    private let now: () -> Date

    init(batch: FoodBatch, handOver: HandOverBatchUseCase, discard: DiscardBatchUseCase,
         fetchDropPoints: FetchDropPointsUseCase, now: @escaping () -> Date) {
        self.batch = batch
        self.handOver = handOver
        self.discard = discard
        self.fetchDropPoints = fetchDropPoints
        self.now = now
    }

    // MARK: - Derived state

    /// True once the batch has been handed over or discarded on this screen.
    var isFinished: Bool {
        actionState == .handedOver || actionState == .discarded
    }

    var isWorking: Bool { actionState == .working }

    var selectedDropPoint: DropPointOption? {
        dropPoints.first { $0.id == selectedDropPointID }
    }

    /// Why this batch can't be handed over, or nil if it can.
    /// The use case enforces the same rules; this lets the screen explain them up front.
    var handoverBlockedReason: String? {
        switch batch.status {
        case .cleared:
            return batch.holdWindow.hasExpired(at: now())
                ? "This batch has been out for more than 4 hours and must be discarded."
                : nil
        case .awaitingCheck:
            return "This batch needs to pass a safety check before it can be handed over."
        case .failedCheck:
            return "This batch failed its safety check, so it can only be discarded."
        case .handedOver, .discarded:
            return "This batch is already \(batch.status.displayName.lowercased())."
        }
    }

    var canHandOver: Bool {
        handoverBlockedReason == nil && selectedDropPoint?.isOpen == true && !isWorking && !isFinished
    }

    var canDiscard: Bool {
        batch.status.isOpen
            && !discardReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isWorking && !isFinished
    }

    // MARK: - Actions

    func load() async {
        loadState = .loading
        do {
            dropPoints = try await fetchDropPoints.execute()
            if selectedDropPoint == nil {
                selectedDropPointID = dropPoints.first(where: \.isOpen)?.id
            }
            loadState = .loaded
        } catch {
            loadState = .failed(Self.message(for: error))
        }
    }

    func handOverBatch() async {
        guard let selectedDropPointID, canHandOver else { return }
        actionState = .working
        do {
            batch = try await handOver.execute(batchID: batch.id, dropPointID: selectedDropPointID)
            actionState = .handedOver
        } catch {
            actionState = .failed(Self.message(for: error))
        }
    }

    func discardBatch() async {
        guard canDiscard else { return }
        actionState = .working
        do {
            batch = try await discard.execute(batchID: batch.id, reason: discardReason)
            actionState = .discarded
        } catch {
            actionState = .failed(Self.message(for: error))
        }
    }

    func dismissError() {
        if case .failed = actionState { actionState = .idle }
    }

    private static func message(for error: Error) -> String {
        let domainError = (error as? DomainError) ?? .storageFailure
        return domainError.errorDescription ?? ""
    }
}
