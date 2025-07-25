import XCTest
import Photos
@testable import Curator

final class CuratorTests: XCTestCase {
    
    var appStateViewModel: AppStateViewModel!
    var photoSwipeViewModel: PhotoSwipeViewModel!
    
    override func setUpWithError() throws {
        appStateViewModel = AppStateViewModel()
        photoSwipeViewModel = PhotoSwipeViewModel()
    }
    
    override func tearDownWithError() throws {
        appStateViewModel = nil
        photoSwipeViewModel = nil
    }
    
    func testAppStateViewModelInitialization() throws {
        XCTAssertEqual(appStateViewModel.photoLibraryPermission, .notDetermined)
        XCTAssertEqual(appStateViewModel.currentPhotoIndex, 0)
        XCTAssertFalse(appStateViewModel.isProcessing)
    }
    
    func testPhotoSwipeViewModelInitialization() throws {
        XCTAssertNil(photoSwipeViewModel.currentPhoto)
        XCTAssertTrue(photoSwipeViewModel.actionQueue.isEmpty)
        XCTAssertTrue(photoSwipeViewModel.undoStack.isEmpty)
        XCTAssertFalse(photoSwipeViewModel.isProcessing)
        XCTAssertEqual(photoSwipeViewModel.currentIndex, 0)
    }
    
    func testSessionProgressCalculation() throws {
        let progress = SessionProgress()
        XCTAssertEqual(progress.progressPercentage, 0)
        
        var progressWithPhotos = SessionProgress()
        progressWithPhotos.totalPhotos = 10
        progressWithPhotos.processedPhotos = 5
        XCTAssertEqual(progressWithPhotos.progressPercentage, 0.5)
    }
    
    func testPhotoActionCreation() throws {
        // Create a mock PHAsset for testing
        let mockAsset = PHAsset()
        let action = PhotoAction(
            photo: mockAsset,
            direction: .right,
            timestamp: Date()
        )
        
        XCTAssertEqual(action.direction, .right)
        XCTAssertNotNil(action.timestamp)
    }
    
    func testSwipeDirectionEnum() throws {
        XCTAssertEqual(SwipeDirection.left.rawValue, "left")
        XCTAssertEqual(SwipeDirection.right.rawValue, "right")
        XCTAssertEqual(SwipeDirection.up.rawValue, "up")
    }
}

// MARK: - Mock Extensions for Testing
extension SwipeDirection: RawRepresentable {
    public typealias RawValue = String
    
    public init?(rawValue: String) {
        switch rawValue {
        case "left": self = .left
        case "right": self = .right
        case "up": self = .up
        default: return nil
        }
    }
    
    public var rawValue: String {
        switch self {
        case .left: return "left"
        case .right: return "right"
        case .up: return "up"
        }
    }
} 