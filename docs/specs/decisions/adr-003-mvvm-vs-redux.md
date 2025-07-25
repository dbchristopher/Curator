# ADR-003: MVVM vs Redux for State Management

**Status:** Accepted  
**Date:** 2025-01-XX  
**Participants:** [Development Team]  
**Related:** [technical-architecture.md](../specs/technical-architecture.md), [ADR-001](./adr-001-swiftui-vs-uikit.md)

## Context

The app requires coordinated state management across multiple screens (photo swiping, library browsing, settings) with complex user interactions and photo loading operations. We need a pattern that supports reactive UI updates, testability, and maintainable code.

## Decision

We will use **MVVM (Model-View-ViewModel)** pattern with **Combine** for reactive state management.

## Rationale

### MVVM Advantages

- **SwiftUI Integration:** Natural fit with @ObservedObject and @Published properties
- **Simplicity:** Straightforward pattern with clear responsibilities
- **Testability:** ViewModels can be unit tested independently of UI
- **Apple Ecosystem:** Recommended pattern in Apple documentation and examples
- **Learning Curve:** Familiar pattern for iOS developers
- **Debugging:** Clear data flow and state mutations

### Redux/TCA Disadvantages for This Project

- **Complexity Overhead:** Significant boilerplate for simple state changes
- **Learning Curve:** Additional architectural concepts beyond standard iOS development
- **Debugging Complexity:** More complex state flow tracing for simple operations
- **Team Velocity:** Slower initial development due to setup overhead

## Architecture Implementation

### MVVM Structure

```
┌─────────────────────────────────────────┐
│                 Views                   │  ← SwiftUI Views
│         (Declarative UI)                │
└─────────────────────────────────────────┘
                    ↕ @ObservedObject/@Published
┌─────────────────────────────────────────┐
│              ViewModels                 │  ← Business Logic & State
│         (@ObservableObject)             │
└─────────────────────────────────────────┘
                    ↕ Protocol Interfaces
┌─────────────────────────────────────────┐
│              Services                   │  ← Data Access Layer
│    (Repository Pattern)                 │
└─────────────────────────────────────────┘
```

### Core ViewModel Implementation

```swift
import Combine
import SwiftUI

class PhotoSwipeViewModel: ObservableObject {
    // MARK: - Published Properties (State)
    @Published var currentPhoto: PHAsset?
    @Published var actionQueue: [PhotoAction] = []
    @Published var isProcessing: Bool = false
    @Published var sessionProgress: SessionProgress = SessionProgress()
    @Published var canUndo: Bool = false

    // MARK: - Dependencies
    private let photoService: PhotoServiceProtocol
    private let storageService: StorageServiceProtocol
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties
    var canSwipe: Bool {
        !isProcessing && currentPhoto != nil
    }

    init(photoService: PhotoServiceProtocol, storageService: StorageServiceProtocol) {
        self.photoService = photoService
        self.storageService = storageService
        setupSubscriptions()
        loadInitialPhoto()
    }

    // MARK: - Public Actions
    func processSwipe(_ direction: SwipeDirection) {
        guard let photo = currentPhoto, canSwipe else { return }

        let action = PhotoAction(
            photoIdentifier: photo.localIdentifier,
            action: direction.rawValue,
            timestamp: Date(),
            isProcessed: false
        )

        actionQueue.append(action)
        sessionProgress.incrementProcessed()
        canUndo = true

        loadNextPhoto()
    }

    func undoLastAction() {
        guard let lastAction = actionQueue.popLast() else { return }

        // Restore previous photo
        Task {
            if let previousPhoto = await photoService.getPhoto(by: lastAction.photoIdentifier) {
                await MainActor.run {
                    self.currentPhoto = previousPhoto
                    self.sessionProgress.decrementProcessed()
                    self.canUndo = !actionQueue.isEmpty
                }
            }
        }
    }

    func commitPendingActions() async {
        isProcessing = true

        do {
            try await storageService.saveActions(actionQueue)
            try await photoService.processActions(actionQueue)

            await MainActor.run {
                self.actionQueue.removeAll()
                self.canUndo = false
                self.isProcessing = false
            }
        } catch {
            await MainActor.run {
                self.isProcessing = false
                // Handle error state
            }
        }
    }

    // MARK: - Private Methods
    private func setupSubscriptions() {
        // React to action queue changes
        $actionQueue
            .map { !$0.isEmpty }
            .assign(to: \.canUndo, on: self)
            .store(in: &cancellables)

        // Auto-commit actions when queue reaches threshold
        $actionQueue
            .filter { $0.count >= 10 }
            .sink { [weak self] _ in
                Task {
                    await self?.commitPendingActions()
                }
            }
            .store(in: &cancellables)
    }

    private func loadNextPhoto() {
        Task {
            let nextPhoto = await photoService.getNextPhoto()
            await MainActor.run {
                self.currentPhoto = nextPhoto
            }
        }
    }

    private func loadInitialPhoto() {
        loadNextPhoto()
    }
}
```

### Session Progress State

```swift
struct SessionProgress {
    private(set) var photosProcessed: Int = 0
    private(set) var startTime: Date = Date()

    mutating func incrementProcessed() {
        photosProcessed += 1
    }

    mutating func decrementProcessed() {
        photosProcessed = max(0, photosProcessed - 1)
    }

    var processingRate: Double {
        let timeElapsed = Date().timeIntervalSince(startTime)
        guard timeElapsed > 0 else { return 0 }
        return Double(photosProcessed) / timeElapsed
    }
}
```

### View Integration

```swift
struct PhotoSwipeView: View {
    @StateObject private var viewModel: PhotoSwipeViewModel

    init(photoService: PhotoServiceProtocol, storageService: StorageServiceProtocol) {
        _viewModel = StateObject(wrappedValue: PhotoSwipeViewModel(
            photoService: photoService,
            storageService: storageService
        ))
    }

    var body: some View {
        VStack {
            // Progress indicator
            ProgressView("Processed: \(viewModel.sessionProgress.photosProcessed)")
                .padding()

            // Main photo area
            if let photo = viewModel.currentPhoto {
                SwipeablePhotoCard(
                    photo: photo,
                    onSwipe: viewModel.processSwipe,
                    isEnabled: viewModel.canSwipe
                )
            } else {
                Text("No more photos")
                    .foregroundColor(.secondary)
            }

            // Action buttons
            HStack {
                Button("Undo") {
                    viewModel.undoLastAction()
                }
                .disabled(!viewModel.canUndo)

                Button("Commit Changes") {
                    Task {
                        await viewModel.commitPendingActions()
                    }
                }
                .disabled(viewModel.actionQueue.isEmpty || viewModel.isProcessing)
            }
            .padding()
        }
        .overlay(
            Group {
                if viewModel.isProcessing {
                    ProgressView("Processing...")
                        .background(Color.black.opacity(0.3))
                }
            }
        )
    }
}
```

## State Flow Pattern

### Unidirectional Data Flow

```
User Action → ViewModel Method → Service Call → State Update → UI Re-render
    ↓              ↓                ↓             ↓            ↓
  Swipe         processSwipe()   photoService   @Published   SwiftUI
```

### Error Handling Pattern

```swift
extension PhotoSwipeViewModel {
    enum ViewModelError: Error, LocalizedError {
        case photoLoadingFailed
        case actionProcessingFailed
        case permissionDenied

        var errorDescription: String? {
            switch self {
            case .photoLoadingFailed:
                return "Failed to load photo"
            case .actionProcessingFailed:
                return "Failed to process photo action"
            case .permissionDenied:
                return "Photo library access required"
            }
        }
    }

    @Published var errorMessage: String?

    private func handleError(_ error: Error) {
        DispatchQueue.main.async {
            self.errorMessage = error.localizedDescription
        }
    }
}
```

## Alternative Considered: The Composable Architecture (TCA)

### TCA Analysis

**Pros:**

- Excellent for complex state management and side effects
- Built-in testing infrastructure with test stores
- Time-travel debugging capabilities
- Enforced unidirectional data flow
- Comprehensive effect management

**Cons:**

- Significant learning curve and setup overhead
- Extensive boilerplate for simple operations
- May be over-engineered for this app's complexity
- Less familiarity within the team
- Slower initial development velocity

### TCA Implementation Example (Not Chosen)

```swift
// What TCA would look like (for comparison)
struct PhotoSwipeState: Equatable {
    var currentPhoto: PHAsset?
    var actionQueue: [PhotoAction] = []
    var isProcessing = false
}

enum PhotoSwipeAction: Equatable {
    case swipePhoto(SwipeDirection)
    case photoLoaded(PHAsset)
    case undoLastAction
    case commitActions
}

struct PhotoSwipeEnvironment {
    let photoService: PhotoServiceProtocol
    let storageService: StorageServiceProtocol
    let mainQueue: AnySchedulerOf<DispatchQueue>
}

let photoSwipeReducer = Reducer<PhotoSwipeState, PhotoSwipeAction, PhotoSwipeEnvironment> { state, action, environment in
    switch action {
    case let .swipePhoto(direction):
        // Complex action handling with effects
        return .none
    }
}
```

**Decision Factors:**

1. **App Complexity:** Current requirements fit well within MVVM capabilities
2. **Team Expertise:** Faster development with familiar patterns
3. **Maintenance:** Simpler codebase for future modifications
4. **Performance:** MVVM with Combine provides sufficient reactive capabilities

## Testing Strategy

### ViewModel Unit Testing

```swift
import XCTest
import Combine
@testable import PhotoApp

class PhotoSwipeViewModelTests: XCTestCase {
    private var viewModel: PhotoSwipeViewModel!
    private var mockPhotoService: MockPhotoService!
    private var mockStorageService: MockStorageService!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        mockPhotoService = MockPhotoService()
        mockStorageService = MockStorageService()
        viewModel = PhotoSwipeViewModel(
            photoService: mockPhotoService,
            storageService: mockStorageService
        )
        cancellables = Set<AnyCancellable>()
    }

    func testSwipeRightAddsToActionQueue() {
        // Given
        let testPhoto = MockPHAsset(localIdentifier: "test-123")
        viewModel.currentPhoto = testPhoto

        // When
        viewModel.processSwipe(.favorite)

        // Then
        XCTAssertEqual(viewModel.actionQueue.count, 1)
        XCTAssertEqual(viewModel.actionQueue.first?.action, "favorite")
        XCTAssertEqual(viewModel.sessionProgress.photosProcessed, 1)
    }

    func testUndoRemovesLastAction() {
        // Given
        viewModel.processSwipe(.favorite)
        let initialCount = viewModel.actionQueue.count

        // When
        viewModel.undoLastAction()

        // Then
        XCTAssertEqual(viewModel.actionQueue.count, initialCount - 1)
    }

    func testCommitPendingActionsCallsServices() async {
        // Given
        viewModel.processSwipe(.favorite)

        // When
        await viewModel.commitPendingActions()

        // Then
        XCTAssertTrue(mockStorageService.saveActionsCalled)
        XCTAssertTrue(mockPhotoService.processActionsCalled)
        XCTAssertTrue(viewModel.actionQueue.isEmpty)
    }
}
```

### Mock Services for Testing

```swift
class MockPhotoService: PhotoServiceProtocol {
    var processActionsCalled = false
    var nextPhotoToReturn: PHAsset?

    func getNextPhoto() async -> PHAsset? {
        return nextPhotoToReturn
    }

    func processActions(_ actions: [PhotoAction]) async throws {
        processActionsCalled = true
    }
}

class MockStorageService: StorageServiceProtocol {
    var saveActionsCalled = false

    func saveActions(_ actions: [PhotoAction]) async throws {
        saveActionsCalled = true
    }
}
```

## Communication Between ViewModels

### Shared State Pattern

```swift
class AppStateViewModel: ObservableObject {
    @Published var photoLibraryPermission: PHAuthorizationStatus = .notDetermined
    @Published var currentFilter: PhotoFilter = .all
    @Published var totalPhotosInLibrary: Int = 0

    // Shared across multiple ViewModels
    static let shared = AppStateViewModel()
}

// Usage in ViewModels
class PhotoSwipeViewModel
```
