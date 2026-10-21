import Foundation
import Observation

/// State and actions for the Impact dashboard.
@MainActor
@Observable
final class ImpactViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded(ImpactStats)
        case failed(String)
    }

    private(set) var state: LoadState = .loading

    private let computeImpactStats: ComputeImpactStatsUseCase

    init(computeImpactStats: ComputeImpactStatsUseCase) {
        self.computeImpactStats = computeImpactStats
    }

    /// Loads the latest totals. Keeps showing the previous totals while refreshing,
    /// so the numbers don't flash away each time the tab opens.
    func load() async {
        if case .loaded = state {} else { state = .loading }
        do {
            state = .loaded(try await computeImpactStats.execute())
        } catch {
            let domainError = (error as? DomainError) ?? .storageFailure
            state = .failed(domainError.errorDescription ?? "")
        }
    }

    /// For example "92%". Nil when there is nothing to compare yet.
    var rescueRateText: String? {
        guard case .loaded(let stats) = state, let rate = stats.rescueRate else { return nil }
        return rate.formatted(.percent.precision(.fractionLength(0)))
    }
}
