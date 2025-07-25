# ADR-002: Core Data vs CloudKit for Local Storage

**Status:** Accepted  
**Date:** 2025-01-XX  
**Participants:** [Development Team]  
**Related:** [technical-architecture.md](../specs/technical-architecture.md)

## Context

We need local data persistence for user preferences, photo action history, session state, and future synchronization capabilities. The choice affects data modeling, offline functionality, and future cloud sync features.

## Decision

We will use **Core Data** for local storage with **CloudKit integration** planned for Phase 2.

## Rationale

### Core Data Advantages

- **Mature Framework:** Proven reliability for complex data relationships
- **Performance:** Optimized for large datasets with proper fetching strategies
- **Offline-First:** Complete functionality without network dependency
- **Migration Support:** Built-in schema migration for app updates
- **Memory Management:** Automatic object lifecycle and memory optimization
- **CloudKit Integration:** NSPersistentCloudKitContainer provides seamless sync when ready

### Alternative Analysis

#### Pure CloudKit

**Pros:** Built-in cloud synchronization, Apple ecosystem integration
**Cons:**

- Requires network connectivity for basic operations
- Limited offline querying capabilities
- Less mature relationship modeling
- Complex conflict resolution

#### SQLite/FMDB

**Pros:** Lightweight, direct SQL control, cross-platform
**Cons:**

- Manual migration and relationship management
- No built-in CloudKit sync path
- More boilerplate code for CRUD operations
- Manual memory management

#### UserDefaults/Property Lists

**Pros:** Simple implementation, automatic persistence
**Cons:**

- Not suitable for complex data relationships
- Poor performance with large datasets
- No synchronization capabilities
- Limited querying options

## Implementation Strategy

### Phase 1 (MVP): Core Data Only

```swift
import CoreData

class PersistenceController {
    static let shared = PersistenceController()

    lazy var container: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "PhotoApp")

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }()

    func save() {
        let context = container.viewContext

        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}
```

### Phase 2 (Cloud Sync): CloudKit Integration

```swift
import CoreData
import CloudKit

class CloudPersistenceController {
    static let shared = CloudPersistenceController()

    lazy var container: NSPersistentCloudKitContainer = {
        let container = NSPersistentCloudKitContainer(name: "PhotoApp")

        // Configure for CloudKit
        guard let storeDescription = container.persistentStoreDescriptions.first else {
            fatalError("Failed to retrieve store description")
        }

        storeDescription.setOption(true as NSNumber,
                                 forKey: NSPersistentHistoryTrackingKey)
        storeDescription.setOption(true as NSNumber,
                                 forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Failed to load store: \(error)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }()
}
```

## Data Model Design

### Core Entities

```swift
// PhotoAction.swift
@objc(PhotoAction)
public class PhotoAction: NSManagedObject {
    @NSManaged public var photoIdentifier: String
    @NSManaged public var action: String // "favorite", "trash", "keep"
    @NSManaged public var timestamp: Date
    @NSManaged public var isProcessed: Bool
    @NSManaged public var session: SwipeSession?
}

// SwipeSession.swift
@objc(SwipeSession)
public class SwipeSession: NSManagedObject {
    @NSManaged public var sessionID: UUID
    @NSManaged public var startTime: Date
    @NSManaged public var endTime: Date?
    @NSManaged public var photosProcessed: Int32
    @NSManaged public var actions: NSSet?
}

// UserPreferences.swift
@objc(UserPreferences)
public class UserPreferences: NSManagedObject {
    @NSManaged public var swipeThreshold: Float
    @NSManaged public var enableHapticFeedback: Bool
    @NSManaged public var autoProcessActions: Bool
    @NSManaged public var lastSyncDate: Date?
}
```

### CloudKit Compatibility

```swift
// Ensure CloudKit-compatible data types
extension PhotoAction {
    static func cloudKitCompatibleEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "PhotoAction"
        entity.managedObjectClassName = "PhotoAction"

        // Use CloudKit-supported types only
        let photoID = NSAttributeDescription()
        photoID.name = "photoIdentifier"
        photoID.attributeType = .stringAttributeType
        photoID.isOptional = false

        let action = NSAttributeDescription()
        action.name = "action"
        action.attributeType = .stringAttributeType
        action.isOptional = false

        let timestamp = NSAttributeDescription()
        timestamp.name = "timestamp"
        timestamp.attributeType = .dateAttributeType
        timestamp.isOptional = false

        entity.properties = [photoID, action, timestamp]
        return entity
    }
}
```

## Data Access Patterns

### Repository Pattern Implementation

```swift
protocol PhotoActionRepositoryProtocol {
    func save(_ action: PhotoAction) async throws
    func fetchPendingActions() async throws -> [PhotoAction]
    func markAsProcessed(_ actions: [PhotoAction]) async throws
    func deleteOldActions(olderThan date: Date) async throws
}

class CoreDataPhotoActionRepository: PhotoActionRepositoryProtocol {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func save(_ action: PhotoAction) async throws {
        try await context.perform {
            try self.context.save()
        }
    }

    func fetchPendingActions() async throws -> [PhotoAction] {
        try await context.perform {
            let request: NSFetchRequest<PhotoAction> = PhotoAction.fetchRequest()
            request.predicate = NSPredicate(format: "isProcessed == NO")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \PhotoAction.timestamp, ascending: true)]

            return try self.context.fetch(request)
        }
    }
}
```

## Migration Strategy

### Schema Versioning

```swift
// PhotoApp.xcdatamodeld versions:
// Version 1: Initial schema (local only)
// Version 2: CloudKit-compatible schema
// Version 3: Enhanced relationships

class MigrationManager {
    static func migrateIfNeeded() {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: managedObjectModel)

        // Check if migration needed
        let storeURL = applicationDocumentsDirectory.appendingPathComponent("PhotoApp.sqlite")

        if requiresMigration(storeURL: storeURL) {
            performMigration(coordinator: coordinator, storeURL: storeURL)
        }
    }

    private static func performMigration(coordinator: NSPersistentStoreCoordinator, storeURL: URL) {
        // Implement progressive migration strategy
    }
}
```

## Consequences

### Positive

- Robust local data persistence with excellent performance
- Clear migration path to cloud synchronization
- Mature debugging and development tools (Core Data Instruments)
- Automatic memory management and optimization
- Rich querying capabilities with NSFetchRequest
- Built-in relationship management and cascading deletes

### Negative

- Additional complexity compared to simpler storage solutions
- Core Data learning curve for team members unfamiliar with framework
- Need to design schema with future CloudKit compatibility in mind
- Potential performance issues if not properly configured

### Risk Mitigation

- Establish Core Data best practices and coding standards early
- Design simple, CloudKit-compatible entity relationships from start
- Use Core Data migration tools and testing for schema evolution
- Implement repository pattern to abstract Core Data complexity
- Comprehensive unit testing of data layer

## Performance Considerations

### Optimization Strategies

```swift
// Efficient fetching with batch limits
extension CoreDataPhotoActionRepository {
    func fetchActionsInBatches(batchSize: Int = 100) -> AsyncThrowingStream<[PhotoAction], Error> {
        AsyncThrowingStream { continuation in
            Task {
                var offset = 0

                while true {
                    let batch = try await fetchActionsBatch(offset: offset, limit: batchSize)

                    if batch.isEmpty {
                        continuation.finish()
                        break
                    }

                    continuation.yield(batch)
                    offset += batchSize
                }
            }
        }
    }
}

// Memory management for large datasets
class DataController {
    func configureContext(_ context: NSManagedObjectContext) {
        context.stalenessInterval = 0.0
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.undoManager = nil // Disable undo for performance
    }
}
```

## Testing Strategy

### Unit Testing Data Layer

```swift
class CoreDataTestCase: XCTestCase {
    var testContainer: NSPersistentContainer!
    var testContext: NSManagedObjectContext!

    override func setUp() {
        super.setUp()

        testContainer = NSPersistentContainer(name: "PhotoApp")
        testContainer.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")

        testContainer.loadPersistentStores { _, error in
            XCTAssertNil(error)
        }

        testContext = testContainer.viewContext
    }

    func testPhotoActionCreation() throws {
        let action = PhotoAction(context: testContext)
        action.photoIdentifier = "test-photo-123"
        action.action = "favorite"
        action.timestamp = Date()
        action.isProcessed = false

        try testContext.save()

        XCTAssertFalse(action.objectID.isTemporaryID)
    }
}
```

## References

- [Core Data Programming Guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreData/)
- [Using Core Data with CloudKit](https://developer.apple.com/documentation/coredata/mirroring_a_core_data_store_with_cloudkit)
- [Core Data Performance Best Practices](https://developer.apple.com/documentation/coredata/improving_performance)

---

**Next Steps:**

1. Create initial Core Data model with CloudKit compatibility
2. Implement repository pattern for data access
3. Set up migration infrastructure
4. Create comprehensive test suite for data layer
5. Plan CloudKit integration timeline for Phase 2
