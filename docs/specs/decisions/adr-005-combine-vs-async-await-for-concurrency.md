# ADR-005: Combine vs Async/Await for Concurrency

**Status:** Accepted  
**Date:** 2025-01-XX  
**Participants:** [Development Team]  
**Related:** [technical-architecture.md](../specs/technical-architecture.md), [ADR-003](./adr-003-mvvm-vs-redux.md)

## Context

The app requires concurrent operations for photo loading, batch processing, UI updates, and PhotoKit interactions. We need to choose between Combine framework and Swift's modern async/await concurrency model, or determine how to use both effectively.

## Decision

We will use **Async/Await** for business logic and data operations with **Combine** for reactive UI updates and state management.

## Rationale

### Hybrid Approach Benefits

**Async/Await Strengths:**

- Cleaner, more readable code for sequential operations
- Excellent error handling with try/catch patterns
- Natural handling of complex asynchronous workflows
- Better debugging experience with linear code flow
- Structured concurrency prevents common concurrency bugs

**Combine Strengths:**

- Excellent integration with SwiftUI's reactive UI updates
- Powerful operators for data transformation and filtering
- Natural fit with @Published properties and ObservableObject
- Efficient handling of continuous data streams
- Built-in backpressure and cancellation support

### Use Case Breakdown

#### Async/Await for:

- Photo loading operations
- Core Data persistence operations
- Batch photo processing
- PhotoKit API interactions
- Network requests (future features)
- Complex business logic workflows

#### Combine for:

- ViewModel @Published properties
- UI state reactivity and binding
- Chaining UI-related operations
- Timer-based operations
- Event streams and notifications

## Implementation Patterns

### Photo Loading with Async/Await

```swift
actor PhotoLoader {
    private var loadingTasks: [PHAsset.LocalIdentifier: Task<UIImage?, Error>] = [:]
    private let imageManager = PHImageManager.default()

    func loadImage(for asset: PHAsset, size: CGSize) async throws -> UIImage? {
        // Prevent duplicate loading requests
        if let existingTask = loadingTasks[asset.localIdentifier] {
            return try await existingTask.value
        }

        let task = Task {
            try await requestImageFromPhotoKit(asset: asset, targetSize: size)
        }

        loadingTasks[asset.localIdentifier] = task

        defer {
            loadingTasks.removeValue(forKey: asset.localIdentifier)
        }

        return try await task.value
    }

    private func requestImageFromPhotoKit(asset: PHAsset, targetSize: CGSize) async throws -> UIImage? {
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: image)
                }
            }
        }
    }

    func preloadImages(assets: [PHAsset], size: CGSize) async {
        await withTaskGroup(of: Void.self) { group in
            for asset in assets.prefix(5) { // Preload first 5
                group.addTask {
                    do {
                        _ = try await self.loadImage(for: asset, size: size)
                    } catch {
                        // Log error but don't fail entire preload
                        print("Failed to preload image: \(error)")
                    }
                }
            }
        }
    }
}
```

### Batch Processing with Structured Concurrency

```swift
class PhotoBatchProcessor {
    func processBatchActions(_ actions: [PhotoAction]) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            // Group actions by type for efficient processing
            let groupedActions = Dictionary(grouping: actions) { $0.action }

            for (actionType, actionGroup) in groupedActions {
                group.addTask {
                    try await self.processActionGroup(actionType, actions: actionGroup)
                }
            }

            // Wait for all action groups to complete
            for try await _ in group {}
        }
    }

    private func processActionGroup(_ actionType: String, actions: [PhotoAction]) async throws {
        switch actionType {
        case "favorite":
            try await addPhotosToFavorites(actions)
        case "trash":
            try await movePhotosToTrash(actions)
        case "keep":
            // No-op for keep actions
            break
        default:
            throw PhotoProcessingError.unknownActionType(actionType)
        }
    }

    private func addPhotosToFavorites(_ actions: [PhotoAction]) async throws {
        let assets = await getAssets(for: actions)

        try await PHPhotoLibrary.shared().performChanges {
            for asset in assets {
                let request = PHAssetChangeRequest(for: asset)
                request.isFavorite = true
            }
        }
    }
}
```

### Reactive UI with Combine

```swift
class PhotoSwipeViewModel: ObservableObject {
    @Published var currentPhoto: PHAsset?
    @Published var isLoading = false
    @Published var actionQueue: [PhotoAction] = []
    @Published var sessionProgress = SessionProgress()
    @Published var errorMessage: String?

    private let photoLoader = PhotoLoader()
    private let batchProcessor = PhotoBatchProcessor()
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupReactiveBindings()
    }

    // MARK: - Async/Await Business Logic
    func loadNextPhoto() {
        isLoading = true

        Task {
            do {
                let nextAsset = try await photoService.getNextPhoto()
                await MainActor.run {
                    self.currentPhoto = nextAsset
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func processSwipe(_ direction: SwipeDirection) {
        guard let photo = currentPhoto else { return }

        let action = PhotoAction(
            photoIdentifier: photo.localIdentifier,
            action: direction.rawValue,
            timestamp: Date()
        )

        actionQueue.append(action)
        sessionProgress.incrementProcessed()

        loadNextPhoto()
    }

    func commitPendingActions() {
        guard !actionQueue.isEmpty else { return }

        isLoading = true

        Task {
            do {
                try await batchProcessor.processBatchActions(actionQueue)
                await MainActor.run {
                    self.actionQueue.removeAll()
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Combine Reactive Bindings
    private func setupReactiveBindings() {
        // Auto-commit when queue reaches threshold
        $actionQueue
            .map { $0.count >= 10 }
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in
                self?.commitPendingActions()
            }
            .store(in: &cancellables)

        // Clear error message after delay
        $errorMessage
            .compactMap { $0 }
            .delay(for: .seconds(5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.errorMessage = nil
            }
            .store(in: &cancellables)

        // Preload next photos when current photo changes
        $currentPhoto
            .compactMap { $0 }
            .sink { [weak self] currentPhoto in
                Task {
                    await self?.preloadNextPhotos(after: currentPhoto)
                }
            }
            .store(in: &cancellables)
    }

    private func preloadNextPhotos(after photo: PHAsset) async {
        do {
            let nextPhotos = try await photoService.getPhotosAfter(photo, limit: 3)
            await photoLoader.preloadImages(
                assets: nextPhotos,
                size: CGSize(width: 400, height: 400)
            )
        } catch {
            print("Failed to preload photos: \(error)")
        }
    }
}
```

### Bridging Async/Await with Combine

```swift
extension PhotoSwipeViewModel {
    // Convert async operations to Combine publishers when needed
    var photoLoadingPublisher: AnyPublisher<PHAsset?, Error> {
        Future { promise in
            Task {
                do {
                    let photo = try await self.photoService.getNextPhoto()
                    promise(.success(photo))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }

    // Combine operators with async/await integration
    func setupAdvancedReactiveBindings() {
        // Debounced batch processing
        $actionQueue
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .filter { $0.count > 0 }
            .sink { [weak self] actions in
                Task {
                    try? await self?.processBatchActions(actions)
                }
            }
            .store(in: &cancellables)

        // Error handling with retry logic
        $errorMessage
            .compactMap { $0 }
            .filter { $0.contains("network") }
            .delay(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.retryLastOperation()
            }
            .store(in: &cancellables)
    }
}
```

## Alternative Considered: Pure Combine

### Pure Combine Analysis

**Pros:**

- Consistent reactive programming model throughout
- Powerful operation chaining and transformation
- Built-in error handling with retry and recovery
- Excellent cancellation support

**Cons:**

- Complex error handling with nested publishers
- Callback-heavy code that's harder to read and debug
- Memory management complexity with AnyCancellable
- Less intuitive for sequential async operations

### Pure Combine Example (Not Chosen)

```swift
// What pure Combine would look like (for comparison)
class PureCombinePhotoViewModel: ObservableObject {
    @Published var currentPhoto: PHAsset?
    @Published var isLoading = false

    private var cancellables = Set<AnyCancellable>()

    func loadNextPhoto() {
        photoService.getNextPhotoPublisher()
            .handleEvents(receiveSubscription: { _ in
                self.isLoading = true
            })
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    self.isLoading = false
                    if case .failure(let error) = completion {
                        // Handle error
                    }
                },
                receiveValue: { photo in
                    self.currentPhoto = photo
                }
            )
            .store(in: &cancellables)
    }
}
```

**Issues with Pure Combine:**

- Nested publisher chains become difficult to follow
- Error handling requires complex completion handlers
- Sequential async operations require flatMap chains
- Less readable than linear async/await code

## Alternative Considered: Pure Async/Await

### Pure Async/Await Analysis

**Pros:**

- Clean, sequential code that's easy to understand
- Excellent error handling with try/catch
- Structured concurrency prevents resource leaks
- Natural debugging flow

**Cons:**

- Less natural integration with SwiftUI reactive updates
- Manual coordination required for UI state updates
- No built-in operators for data transformation
- More boilerplate for reactive patterns

### Pure Async/Await Example (Not Chosen)

```swift
// What pure async/await would look like
class PureAsyncPhotoViewModel: ObservableObject {
    @Published var currentPhoto: PHAsset?
    @Published var isLoading = false

    func loadNextPhoto() async {
        await MainActor.run {
            self.isLoading = true
        }

        do {
            let photo = try await photoService.getNextPhoto()
            await MainActor.run {
                self.currentPhoto = photo
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
                // Handle error
            }
        }
    }
}
```

**Issues with Pure Async/Await:**

- Manual MainActor coordination for every UI update
- No automatic debouncing or throttling
- Less elegant reactive patterns
- More verbose state management code

## Performance Considerations

### Memory Management

```swift
// Async/await with proper resource cleanup
actor ResourceManagedPhotoLoader {
    private var activeRequests: Set<PHImageRequestID> = []

    func loadImage(asset: PHAsset) async throws -> UIImage? {
        return try await withTaskCancellationHandler {
            // Main loading operation
            return try await performImageRequest(asset: asset)
        } onCancel: {
            // Cleanup on cancellation
            Task {
                await self.cancelActiveRequests()
            }
        }
    }

    private func cancelActiveRequests() {
        for requestID in activeRequests {
            PHImageManager.default().cancelImageRequest(requestID)
        }
        activeRequests.removeAll()
    }
}

// Combine with automatic cancellation
extension PhotoSwipeViewModel {
    func setupAutomaticCancellation() {
        // Automatically cancel previous requests
        $currentPhoto
            .compactMap { $0 }
            .flatMap { photo in
                self.loadPhotoPublisher(photo)
                    .catch { _ in Just(nil) }
            }
            .assign(to: \.loadedImage, on: self)
            .store(in: &cancellables)
    }
}
```

### Concurrency Performance

```swift
// Optimized concurrent operations with async/await
class OptimizedPhotoProcessor {
    func processPhotosEfficiently(_ photos: [PHAsset]) async throws {
        // Process in controlled batches to avoid overwhelming the system
        let batchSize = 5

        for batch in photos.chunked(into: batchSize) {
            try await withThrowingTaskGroup(of: UIImage?.self) { group in
                for photo in batch {
                    group.addTask {
                        try await self.photoLoader.loadImage(for: photo, size: .thumbnail)
                    }
                }

                // Collect results without blocking
                var results: [UIImage?] = []
                for try await result in group {
                    results.append(result)
                }

                // Update UI with batch results
                await MainActor.run {
                    self.updateUI(with: results)
                }
            }
        }
    }
}
```

### Reactive Performance with Combine

```swift
extension PhotoSwipeViewModel {
    func setupPerformantReactiveBindings() {
        // Efficient change detection
        $actionQueue
            .removeDuplicates { oldQueue, newQueue in
                oldQueue.count == newQueue.count
            }
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] queue in
                self?.updateQueueDisplay(queue)
            }
            .store(in: &cancellables)

        // Smart preloading with throttling
        $currentPhoto
            .compactMap { $0 }
            .throttle(for: .milliseconds(300), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] photo in
                Task {
                    await self?.smartPreload(around: photo)
                }
            }
            .store(in: &cancellables)
    }
}
```

## Error Handling Strategy

### Async/Await Error Handling

```swift
enum PhotoProcessingError: Error, LocalizedError {
    case permissionDenied
    case assetUnavailable
    case networkRequired
    case processingFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Photo library access is required"
        case .assetUnavailable:
            return "Photo is no longer available"
        case .networkRequired:
            return "Network connection required for this photo"
        case .processingFailed(let error):
            return "Processing failed: \(error.localizedDescription)"
        }
    }
}

extension PhotoLoader {
    func loadImageWithRetry(asset: PHAsset, maxRetries: Int = 3) async throws -> UIImage? {
        var lastError: Error?

        for attempt in 1...maxRetries {
            do {
                return try await loadImage(for: asset, size: .medium)
            } catch {
                lastError = error

                // Exponential backoff
                let delay = TimeInterval(pow(2.0, Double(attempt - 1)))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        throw PhotoProcessingError.processingFailed(underlying: lastError!)
    }
}
```

### Combine Error Handling

```swift
extension PhotoSwipeViewModel {
    func setupRobustErrorHandling() {
        // Automatic retry with exponential backoff
        photoLoadingPublisher
            .retry(3)
            .catch { error -> AnyPublisher<PHAsset?, Never> in
                // Log error and provide fallback
                print("Photo loading failed: \(error)")
                return Just(nil).eraseToAnyPublisher()
            }
            .assign(to: \.currentPhoto, on: self)
            .store(in: &cancellables)

        // Error state management
        $errorMessage
            .compactMap { $0 }
            .delay(for: .seconds(5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.errorMessage = nil
            }
            .store(in: &cancellables)
    }
}
```

## Testing Strategy

### Testing Async/Await Code

```swift
import XCTest
@testable import PhotoApp

class AsyncPhotoLoaderTests: XCTestCase {
    var photoLoader: PhotoLoader!

    override func setUp() {
        super.setUp()
        photoLoader = PhotoLoader()
    }

    func testImageLoadingSuccess() async throws {
        let mockAsset = MockPHAsset(localIdentifier: "test-123")

        let image = try await photoLoader.loadImage(
            for: mockAsset,
            size: CGSize(width: 100, height: 100)
        )

        XCTAssertNotNil(image)
    }

    func testConcurrentLoadingPerformance() async throws {
        let assets = (0..<10).map { MockPHAsset(localIdentifier: "test-\($0)") }

        let startTime = Date()

        try await withThrowingTaskGroup(of: UIImage?.self) { group in
            for asset in assets {
                group.addTask {
                    try await self.photoLoader.loadImage(for: asset, size: .thumbnail)
                }
            }

            for try await _ in group {
                // Collect all results
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        XCTAssertLessThan(duration, 2.0, "Concurrent loading should complete within 2 seconds")
    }

    func testErrorHandlingWithRetry() async {
        let failingAsset = FailingMockPHAsset()

        do {
            _ = try await photoLoader.loadImageWithRetry(asset: failingAsset, maxRetries: 2)
            XCTFail("Should have thrown error")
        } catch {
            XCTAssertTrue(error is PhotoProcessingError)
        }
    }
}
```

### Testing Combine Reactive Code

```swift
class CombinePhotoViewModelTests: XCTestCase {
    var viewModel: PhotoSwipeViewModel!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        viewModel = PhotoSwipeViewModel()
        cancellables = Set<AnyCancellable>()
    }

    func testActionQueueAutoCommit() {
        let expectation = XCTestExpectation(description: "Auto-commit triggered")

        viewModel.$actionQueue
            .filter { $0.isEmpty }
            .dropFirst() // Skip initial empty state
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Add 10 actions to trigger auto-commit
        for i in 0..<10 {
            let action = PhotoAction(photoIdentifier: "test-\(i)", action: "favorite", timestamp: Date())
            viewModel.actionQueue.append(action)
        }

        wait(for: [expectation], timeout: 2.0)
    }

    func testErrorMessageAutoClearing() {
        let expectation = XCTestExpectation(description: "Error message cleared")

        viewModel.$errorMessage
            .dropFirst(2) // Skip initial nil and set value
            .sink { message in
                XCTAssertNil(message)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        viewModel.errorMessage = "Test error"

        wait(for: [expectation], timeout: 6.0)
    }
}
```

## Consequences

### Positive

- **Clean Business Logic:** Async/await provides readable, maintainable code for complex operations
- **Reactive UI:** Combine seamlessly integrates with SwiftUI for responsive user interfaces
- **Optimal Performance:** Each approach used for its strengths results in better overall performance
- **Modern Swift:** Leverages latest Swift concurrency features alongside mature reactive programming
- **Error Handling:** Best error handling patterns for both sequential and reactive scenarios
- **Testing:** Clear testing strategies for both paradigms

### Negative

- **Mixed Paradigms:** Team needs to understand both async/await and Combine patterns
- **Complexity:** Deciding when to use each approach requires architectural judgment
- **Bridge Code:** Occasional need to bridge between async/await and Combine
- **Learning Curve:** Requires expertise in both concurrency models

### Risk Mitigation

- **Clear Guidelines:** Establish explicit rules for when to use async/await vs Combine
- **Utility Functions:** Create helper functions for common async-to-Combine bridges
- **Code Reviews:** Ensure consistent application of patterns across codebase
- **Documentation:** Comprehensive examples and best practices for both approaches
- **Training:** Team education on effective use of both concurrency models

## Implementation Guidelines

### When to Use Async/Await

- Sequential business operations
- Photo loading and processing
- Database operations
- Network requests
- Error-prone operations requiring try/catch
- Complex workflows with multiple steps

### When to Use Combine

- UI state management with @Published
- Reactive data transformations
- Event streams and notifications
- Debouncing and throttling
- Automatic cancellation with UI lifecycle
- Publishers that need operators (map, filter, etc.)

### Bridge Patterns

```swift
// Async/await to Combine
extension Future where Failure == Error {
    convenience init(asyncOperation: @escaping () async throws -> Output) {
        self.init { promise in
            Task {
                do {
                    let result = try await asyncOperation()
                    promise(.success(result))
                } catch {
                    promise(.failure(error))
                }
            }
        }
    }
}

// Combine to Async/await
extension AnyPublisher {
    func asyncValue() async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            var cancellable: AnyCancellable?

            cancellable = self
                .first()
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            continuation.resume(throwing: error)
                        }
                        cancellable?.cancel()
                    },
                    receiveValue: { value in
                        continuation.resume(returning: value)
                        cancellable?.cancel()
                    }
                )
        }
    }
}
```

## References

- [Swift Concurrency Documentation](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)
- [Combine Framework](https://developer.apple.com/documentation/combine)
- [Async/Await Best Practices](https://developer.apple.com/videos/play/wwdc2021/10132/)
- [Structured Concurrency in Swift](https://developer.apple.com/videos/play/wwdc2021/10134/)

## Review Notes

- Hybrid approach leverages strengths of both paradigms
- Clear separation of concerns between business logic and UI reactivity
- Performance optimizations appropriate for photo processing workload
- Comprehensive error handling for both async and reactive scenarios
- Testing strategies cover both concurrency models effectively

---

**Next Steps:**

1. Create async/await photo loading infrastructure
2. Implement Combine-based reactive ViewModels
3. Build bridge utilities for async/Combine integration
4. Establish coding guidelines and best practices
5. Create comprehensive test suites for both paradigms
