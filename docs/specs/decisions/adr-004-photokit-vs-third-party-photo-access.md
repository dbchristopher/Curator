# ADR-004: PhotoKit vs Third-Party for Photo Access

**Status:** Accepted  
**Date:** 2025-01-XX  
**Participants:** [Development Team]  
**Related:** [technical-architecture.md](../specs/technical-architecture.md)

## Context

The app needs reliable access to the user's photo library with permissions handling, photo loading, modification capabilities, and batch operations. We need to choose between Apple's PhotoKit framework and third-party alternatives for photo library integration.

## Decision

We will use **PhotoKit** as the exclusive framework for photo library access.

## Rationale

### PhotoKit Advantages

- **Native Integration:** First-party Apple framework with optimal performance and deep system integration
- **Full Access:** Complete photo library access including metadata, locations, albums, and Live Photos
- **Privacy Compliance:** Built-in privacy controls and permission management aligned with iOS guidelines
- **Modification Support:** Can create albums, mark favorites, move photos to trash, and modify metadata
- **Live Updates:** Automatic notifications when photo library changes via PHPhotoLibraryChangeObserver
- **Future Compatibility:** Guaranteed updates with new iOS versions and features
- **Performance Optimization:** Efficient thumbnail generation, background loading, and memory management
- **Rich Metadata:** Access to EXIF data, creation dates, location information, and photo analysis

### Third-Party Alternatives Evaluated

#### Custom UIImagePickerController

**Pros:** Simple implementation, familiar API
**Cons:**

- Limited to selecting individual photos (not suitable for bulk organization)
- No batch operations or library browsing capabilities
- Cannot access existing photo metadata or relationships
- No ability to modify photo library or create albums
- Poor user experience for photo organization workflows

#### Direct Photos.app URL Schemes

**Pros:** No permission requirements, uses system apps
**Cons:**

- No programmatic access to photo library
- Cannot implement custom swiping interface
- Limited to system-provided sharing mechanisms
- No control over user experience or workflow

#### Third-Party SDKs (Filestack, Cloudinary, etc.)

**Pros:** Additional cloud features, cross-platform support
**Cons:**

- Still require PhotoKit for local photo access
- Add unnecessary complexity and dependencies
- Privacy concerns with third-party photo processing
- Additional licensing costs and vendor lock-in

## Technical Implementation

### Core PhotoKit Integration

```swift
import PhotoKit
import Combine

class PhotoLibraryService: NSObject, ObservableObject {
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var photoAssets: [PHAsset] = []

    private let imageManager = PHImageManager.default()
    private var changeObserver: AnyCancellable?

    override init() {
        super.init()
        setupPhotoLibraryObserver()
    }

    // MARK: - Permission Handling
    func requestPhotoLibraryAccess() async -> PHAuthorizationStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)

        await MainActor.run {
            self.authorizationStatus = status
        }

        if status == .authorized || status == .limited {
            await loadPhotoAssets()
        }

        return status
    }

    func checkAuthorizationStatus() -> PHAuthorizationStatus {
        return PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    // MARK: - Photo Loading
    private func loadPhotoAssets() async {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: false)
        ]
        fetchOptions.includeHiddenAssets = false
        fetchOptions.includeAllBurstPhotos = false

        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        var photoAssets: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in
            photoAssets.append(asset)
        }

        await MainActor.run {
            self.photoAssets = photoAssets
        }
    }
}
```

### High-Performance Image Loading

```swift
extension PhotoLibraryService {
    func loadImage(
        asset: PHAsset,
        targetSize: CGSize,
        deliveryMode: PHImageRequestOptionsDeliveryMode = .highQualityFormat
    ) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = deliveryMode
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                // Check if this is the final, high-quality image
                let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false

                if !isDegraded {
                    continuation.resume(returning: image)
                }
            }
        }
    }

    func loadThumbnail(asset: PHAsset) async -> UIImage? {
        return await loadImage(
            asset: asset,
            targetSize: CGSize(width: 200, height: 200),
            deliveryMode: .fastFormat
        )
    }

    func loadFullResolutionImage(asset: PHAsset) async -> UIImage? {
        return await loadImage(
            asset: asset,
            targetSize: PHImageManagerMaximumSize,
            deliveryMode: .highQualityFormat
        )
    }
}
```

### Batch Photo Operations

```swift
extension PhotoLibraryService {
    func movePhotosToTrash(_ assets: [PHAsset]) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
    }

    func addPhotosToFavorites(_ assets: [PHAsset]) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            for asset in assets {
                let request = PHAssetChangeRequest(for: asset)
                request.isFavorite = true
            }
        }
    }

    func createAlbumWithPhotos(title: String, assets: [PHAsset]) async throws -> PHAssetCollection {
        var albumPlaceholder: PHObjectPlaceholder?

        try await PHPhotoLibrary.shared().performChanges {
            let createRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            albumPlaceholder = createRequest.placeholderForCreatedAssetCollection

            if let placeholder = albumPlaceholder {
                let albumChangeRequest = PHAssetCollectionChangeRequest(for: placeholder)
                albumChangeRequest?.addAssets(assets as NSArray)
            }
        }

        guard let placeholder = albumPlaceholder,
              let album = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [placeholder.localIdentifier],
                options: nil
              ).firstObject else {
            throw PhotoLibraryError.albumCreationFailed
        }

        return album
    }
}

enum PhotoLibraryError: Error, LocalizedError {
    case permissionDenied
    case albumCreationFailed
    case assetModificationFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Photo library access is required to organize your photos"
        case .albumCreationFailed:
            return "Failed to create photo album"
        case .assetModificationFailed:
            return "Failed to modify photo"
        }
    }
}
```

### Live Photo Library Updates

```swift
extension PhotoLibraryService: PHPhotoLibraryChangeObserver {
    private func setupPhotoLibraryObserver() {
        PHPhotoLibrary.shared().register(self)
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async {
            // Handle changes to photo library
            if let assets = self.currentFetchResult,
               let changes = changeInstance.changeDetails(for: assets) {

                self.currentFetchResult = changes.fetchResultAfterChanges

                if changes.hasIncrementalChanges {
                    // Handle incremental changes
                    self.handleIncrementalChanges(changes)
                } else {
                    // Reload entire collection
                    Task {
                        await self.loadPhotoAssets()
                    }
                }
            }
        }
    }

    private func handleIncrementalChanges(_ changes: PHFetchResultChangeDetails<PHAsset>) {
        var updatedAssets = photoAssets

        // Remove deleted assets
        if let removedIndexes = changes.removedIndexes {
            for index in removedIndexes.reversed() {
                updatedAssets.remove(at: index)
            }
        }

        // Insert new assets
        if let insertedIndexes = changes.insertedIndexes {
            let insertedAssets = changes.insertedObjects
            for (index, insertedIndex) in insertedIndexes.enumerated() {
                updatedAssets.insert(insertedAssets[index], at: insertedIndex)
            }
        }

        // Handle moved assets
        changes.enumerateMoves { fromIndex, toIndex in
            let asset = updatedAssets.remove(at: fromIndex)
            updatedAssets.insert(asset, at: toIndex)
        }

        photoAssets = updatedAssets
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
}
```

## Privacy and Permissions Strategy

### Minimal Access Approach

```swift
class PhotoPermissionManager: ObservableObject {
    @Published var currentStatus: PHAuthorizationStatus = .notDetermined
    @Published var shouldShowPermissionRationale = false

    func requestPermissionWithContext() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)

        await MainActor.run {
            self.currentStatus = status
            self.handlePermissionResponse(status)
        }
    }

    private func handlePermissionResponse(_ status: PHAuthorizationStatus) {
        switch status {
        case .notDetermined:
            shouldShowPermissionRationale = true

        case .restricted, .denied:
            // Show settings redirect
            showSettingsAlert()

        case .authorized:
            // Full access granted
            break

        case .limited:
            // iOS 14+ limited access
            handleLimitedAccess()

        @unknown default:
            break
        }
    }

    private func handleLimitedAccess() {
        // Gracefully handle limited photo access
        // Show UI to let user manage photo selection
    }

    private func showSettingsAlert() {
        // Present alert to redirect user to Settings app
    }
}
```

### Privacy-First Implementation

```swift
extension PhotoLibraryService {
    var privacyCompliantDescription: String {
        """
        This app organizes your photos by letting you quickly swipe through them.

        • Photos stay on your device
        • No photo data is sent to external servers
        • You control which photos the app can access
        • You can revoke access anytime in Settings
        """
    }

    func requestMinimalAccess() async -> PHAuthorizationStatus {
        // Request only what's needed for core functionality
        return await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }
}
```

## Performance Optimization

### Efficient Thumbnail Generation

```swift
class PhotoThumbnailCache {
    private let cache = NSCache<NSString, UIImage>()
    private let thumbnailSize = CGSize(width: 200, height: 200)

    init() {
        // Configure cache limits
        cache.countLimit = 100 // Maximum 100 thumbnails
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB memory limit
    }

    func thumbnail(for asset: PHAsset) async -> UIImage? {
        let cacheKey = asset.localIdentifier as NSString

        // Check cache first
        if let cachedImage = cache.object(forKey: cacheKey) {
            return cachedImage
        }

        // Generate thumbnail
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.isSynchronous = false
        options.isNetworkAccessAllowed = false // Prefer local content

        let image = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: thumbnailSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }

        // Cache the result
        if let image = image {
            let cost = Int(image.size.width * image.size.height * 4) // Estimated memory cost
            cache.setObject(image, forKey: cacheKey, cost: cost)
        }

        return image
    }
}
```

### Background Photo Prefetching

```swift
actor PhotoPrefetcher {
    private var prefetchTasks: [String: Task<UIImage?, Never>] = [:]

    func prefetchPhotos(_ assets: [PHAsset]) {
        for asset in assets {
            guard prefetchTasks[asset.localIdentifier] == nil else { continue }

            let task = Task {
                await PhotoThumbnailCache.shared.thumbnail(for: asset)
            }

            prefetchTasks[asset.localIdentifier] = task
        }
    }

    func cancelPrefetching(for assets: [PHAsset]) {
        for asset in assets {
            prefetchTasks[asset.localIdentifier]?.cancel()
            prefetchTasks.removeValue(forKey: asset.localIdentifier)
        }
    }

    func cleanupCompletedTasks() {
        prefetchTasks = prefetchTasks.filter { _, task in
            !task.isCancelled
        }
    }
}
```

## Testing Strategy

### Unit Testing PhotoKit Integration

```swift
import XCTest
import PhotoKit
@testable import PhotoApp

class PhotoLibraryServiceTests: XCTestCase {
    var photoService: PhotoLibraryService!

    override func setUp() {
        super.setUp()
        photoService = PhotoLibraryService()
    }

    func testPermissionRequest() async {
        // Test permission flow
        let status = await photoService.requestPhotoLibraryAccess()

        // Verify status is handled correctly
        XCTAssertTrue([.authorized, .limited, .denied, .restricted].contains(status))
    }

    func testImageLoading() async throws {
        // Create test asset (requires test photos in simulator)
        let fetchOptions = PHFetchOptions()
        fetchOptions.fetchLimit = 1
        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        guard let testAsset = assets.firstObject else {
            throw XCTSkip("No test photos available in simulator")
        }

        // Test image loading
        let image = await photoService.loadThumbnail(asset: testAsset)
        XCTAssertNotNil(image)
    }

    func testBatchOperations() async throws {
        // Test batch photo operations
        let assets = createTestAssets()

        do {
            try await photoService.addPhotosToFavorites(assets)
            // Verify favorites were set
        } catch {
            XCTFail("Failed to add photos to favorites: \(error)")
        }
    }
}

// Mock PHAsset for testing
class MockPHAsset: PHAsset {
    private let mockIdentifier: String

    init(localIdentifier: String) {
        self.mockIdentifier = localIdentifier
        super.init()
    }

    override var localIdentifier: String {
        return mockIdentifier
    }
}
```

### Integration Testing

```swift
class PhotoLibraryIntegrationTests: XCTestCase {
    func testFullPhotoWorkflow() async throws {
        let service = PhotoLibraryService()

        // Test complete workflow
        let status = await service.requestPhotoLibraryAccess()
        guard status == .authorized else {
            throw XCTSkip("Photo library access required for integration test")
        }

        // Load photos
        await service.loadPhotoAssets()
        XCTAssertGreaterThan(service.photoAssets.count, 0)

        // Test image loading
        if let firstAsset = service.photoAssets.first {
            let image = await service.loadThumbnail(asset: firstAsset)
            XCTAssertNotNil(image)
        }
    }
}
```

## Consequences

### Positive

- **Native Performance:** Optimal performance and memory usage with first-party framework
- **Complete Feature Access:** Full photo library capabilities including metadata and modifications
- **Privacy Compliance:** Built-in privacy controls aligned with iOS guidelines
- **Future Compatibility:** Guaranteed support for new iOS features and devices
- **Rich Functionality:** Access to Live Photos, Portrait mode, HEIF images, and other iOS photo features
- **Reliable Updates:** Automatic library change notifications and state synchronization

### Negative

- **iOS Platform Lock-in:** Solution is iOS-specific (not relevant for this project)
- **Complexity Management:** Must handle all PhotoKit edge cases and permission states
- **Learning Curve:** Team needs PhotoKit expertise for advanced features
- **Testing Challenges:** Requires device testing and photo library setup

### Risk Mitigation

- **Comprehensive Error Handling:** Implement robust error handling for all PhotoKit operations
- **Abstraction Layer:** Create service layer to isolate PhotoKit dependencies from business logic
- **Extensive Testing:** Test across different permission states, library sizes, and device configurations
- **Performance Monitoring:** Monitor memory usage and loading performance with large photo libraries
- **Graceful Degradation:** Handle limited access and permission changes appropriately

## Migration Considerations

### Future Cloud Integration

PhotoKit provides excellent foundation for future cloud features:

```swift
// Future cloud sync integration
extension PhotoLibraryService {
    func syncWithCloudService() async {
        // PhotoKit assets can be referenced for cloud backup
        // Metadata can be synchronized across devices
        // Changes can be tracked and merged
    }
}
```

### Cross-Platform Considerations

If cross-platform support becomes required in the future:

- PhotoKit logic can be isolated behind protocol interfaces
- Core business logic remains platform-agnostic
- Platform-specific implementations can be swapped out

## References

- [PhotoKit Framework Documentation](https://developer.apple.com/documentation/photokit)
- [Photo Library Access Best Practices](https://developer.apple.com/documentation/photokit/requesting_authorization_to_access_photos)
- [Privacy and Photo Access Guidelines](https://developer.apple.com/app-store/user-privacy-and-data-use/)
- [PhotoKit Performance Guidelines](https://developer.apple.com/documentation/photokit/browsing_and_modifying_photo_albums)

---

**Next Steps:**

1. Implement core PhotoLibraryService with permission handling
2. Create high-performance image loading and caching system
3. Add batch operation support for photo organization
4. Implement photo library change observer
5. Create comprehensive test suite with mock assets
