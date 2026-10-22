import CoreData
import Foundation

final class CoreDataDropPointRepository: DropPointRepository {
    private let container: NSPersistentContainer

    init(container: NSPersistentContainer) {
        self.container = container
    }

    func all() async throws -> [DropPoint] {
        try await container.performBackground(failure: .fetchFailed) { context in
            let request = NSFetchRequest<DropPointEntity>(entityName: "DropPointEntity")
            request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
            return try context.fetch(request).map { try $0.toDomain() }
        }
    }

    func dropPoint(id: Identifier<DropPoint>) async throws -> DropPoint? {
        try await container.performBackground(failure: .fetchFailed) { context in
            try context.fetchOne(DropPointEntity.self, id: id.rawValue)?.toDomain()
        }
    }
}
