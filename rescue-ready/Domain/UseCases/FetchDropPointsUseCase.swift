import Foundation

/// A drop point and whether it can take a delivery right now.
struct DropPointOption: Identifiable, Equatable {
    let dropPoint: DropPoint
    let isOpen: Bool

    var id: Identifier<DropPoint> { dropPoint.id }
}

/// Lists drop points for a handover, open ones first, then by name.
struct FetchDropPointsUseCase {
    let dropPoints: DropPointRepository
    let now: () -> Date

    func execute() async throws -> [DropPointOption] {
        let all: [DropPoint]
        do {
            all = try await dropPoints.all()
        } catch {
            throw DomainError.storageFailure
        }

        let timestamp = now()
        return all
            .map { DropPointOption(dropPoint: $0, isOpen: $0.isOpen(at: timestamp)) }
            .sorted { lhs, rhs in
                if lhs.isOpen != rhs.isOpen { return lhs.isOpen }
                return lhs.dropPoint.name < rhs.dropPoint.name
            }
    }
}
