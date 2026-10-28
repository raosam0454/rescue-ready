import Foundation

/// Food rescued and delivered to one drop point.
struct DropPointImpact: Identifiable, Equatable {
    let id: Identifier<DropPoint>
    let name: String
    let kilograms: Double
    let batches: Int
}

/// A summary of how much food the group has rescued.
struct ImpactStats: Equatable {
    /// Assumed conversion for the meals estimate: 1 kg of rescued food is about 2 meals.
    static let mealsPerKilogram: Double = 2

    /// Total weight of handed-over batches. Discarded food is never included.
    let kilogramsSaved: Double
    /// Meals estimate, rounded down so the app never overstates impact.
    let estimatedMeals: Int
    let batchesHandedOver: Int
    let batchesDiscarded: Int
    let kilogramsDiscarded: Double
    /// Drop points that received food, most kilograms first.
    let dropPoints: [DropPointImpact]

    /// Share of closed batches that reached a drop point, from 0 to 1.
    /// Nil until at least one batch has been handed over or discarded.
    var rescueRate: Double? {
        let closed = batchesHandedOver + batchesDiscarded
        guard closed > 0 else { return nil }
        return Double(batchesHandedOver) / Double(closed)
    }

    /// True when nothing has been handed over or discarded yet.
    var isEmpty: Bool {
        batchesHandedOver == 0 && batchesDiscarded == 0
    }

    static let empty = ImpactStats(kilogramsSaved: 0, estimatedMeals: 0, batchesHandedOver: 0,
                                   batchesDiscarded: 0, kilogramsDiscarded: 0, dropPoints: [])
}

/// Totals the food the group has rescued.
///
/// Rules:
/// - only handed-over batches count towards kilograms saved and meals
/// - discarded batches are reported separately and never added to the totals
/// - open batches (awaiting check, cleared, failed check) are ignored
/// - meals are estimated at `ImpactStats.mealsPerKilogram` and rounded down
struct ComputeImpactStatsUseCase {
    let batches: BatchRepository
    let dropPoints: DropPointRepository

    func execute() async throws -> ImpactStats {
        let handedOver: [FoodBatch]
        let discarded: [FoodBatch]
        let knownDropPoints: [DropPoint]
        do {
            handedOver = try await batches.batches(withStatus: .handedOver)
            discarded = try await batches.batches(withStatus: .discarded)
            knownDropPoints = try await dropPoints.all()
        } catch {
            throw DomainError.storageFailure
        }

        let kilogramsSaved = handedOver.reduce(0) { $0 + $1.weight.kilograms }

        return ImpactStats(
            kilogramsSaved: kilogramsSaved,
            estimatedMeals: Int((kilogramsSaved * ImpactStats.mealsPerKilogram).rounded(.down)),
            batchesHandedOver: handedOver.count,
            batchesDiscarded: discarded.count,
            kilogramsDiscarded: discarded.reduce(0) { $0 + $1.weight.kilograms },
            dropPoints: breakdown(of: handedOver, names: knownDropPoints)
        )
    }

    private func breakdown(of handedOver: [FoodBatch], names knownDropPoints: [DropPoint]) -> [DropPointImpact] {
        var namesByID: [Identifier<DropPoint>: String] = [:]
        for dropPoint in knownDropPoints {
            namesByID[dropPoint.id] = dropPoint.name
        }

        var kilogramsByID: [Identifier<DropPoint>: Double] = [:]
        var batchesByID: [Identifier<DropPoint>: Int] = [:]
        for batch in handedOver {
            guard let dropPointID = batch.dropPointID else { continue }
            kilogramsByID[dropPointID, default: 0] += batch.weight.kilograms
            batchesByID[dropPointID, default: 0] += 1
        }

        return kilogramsByID
            .map { dropPointID, kilograms in
                DropPointImpact(
                    id: dropPointID,
                    name: namesByID[dropPointID] ?? "Removed drop point",
                    kilograms: kilograms,
                    batches: batchesByID[dropPointID, default: 0]
                )
            }
            .sorted { lhs, rhs in
                lhs.kilograms == rhs.kilograms ? lhs.name < rhs.name : lhs.kilograms > rhs.kilograms
            }
    }
}
