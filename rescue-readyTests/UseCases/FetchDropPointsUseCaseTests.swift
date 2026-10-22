import Foundation
import Testing
@testable import rescue_ready

struct FetchDropPointsUseCaseTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let store = InMemoryDataStore()

    private func addDropPoint(_ name: String, open: Bool) {
        let currentHour = Calendar.current.component(.hour, from: now)
        let closedHours = currentHour == 23 ? 0...22 : (currentHour + 1)...23
        let dropPoint = DropPoint(id: Identifier(), name: name, address: "1 Test St",
                                  openingHours: open ? 0...23 : closedHours)
        store.dropPoints[dropPoint.id] = dropPoint
    }

    private func makeUseCase(fail: Bool = false) -> FetchDropPointsUseCase {
        let dropPoints = InMemoryDropPointRepository(store: store)
        dropPoints.shouldFail = fail
        let fixedNow = now
        return FetchDropPointsUseCase(dropPoints: dropPoints, now: { fixedNow })
    }

    @Test func listsOpenDropPointsFirstThenByName() async throws {
        addDropPoint("Alpha Pantry", open: false)
        addDropPoint("Zeta Kitchen", open: true)
        addDropPoint("Beta Meals", open: true)

        let options = try await makeUseCase().execute()

        #expect(options.map(\.dropPoint.name) == ["Beta Meals", "Zeta Kitchen", "Alpha Pantry"])
        #expect(options.map(\.isOpen) == [true, true, false])
    }

    @Test func mapsRepositoryFailureToStorageFailure() async {
        await #expect(throws: DomainError.storageFailure) {
            try await makeUseCase(fail: true).execute()
        }
    }
}
