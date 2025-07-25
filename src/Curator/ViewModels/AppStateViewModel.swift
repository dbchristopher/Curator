import SwiftUI
import Photos
import Combine

@MainActor
class AppStateViewModel: ObservableObject {
    @Published var photoLibraryPermission: PHAuthorizationStatus = .notDetermined
    @Published var currentPhotoIndex: Int = 0
    @Published var sessionProgress: SessionProgress = SessionProgress()
    @Published var currentFilter: PhotoFilter = .all
    @Published var isProcessing: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Monitor photo library changes
        NotificationCenter.default.publisher(for: .PHPhotoLibraryDidChange)
            .sink { [weak self] _ in
                self?.handlePhotoLibraryChange()
            }
            .store(in: &cancellables)
    }
    
    private func handlePhotoLibraryChange() {
        // Handle photo library changes (photos added/removed)
        // This will be implemented when we add photo management features
    }
}

// MARK: - Supporting Models
struct SessionProgress {
    var totalPhotos: Int = 0
    var processedPhotos: Int = 0
    var keptPhotos: Int = 0
    var trashedPhotos: Int = 0
    
    var progressPercentage: Double {
        guard totalPhotos > 0 else { return 0 }
        return Double(processedPhotos) / Double(totalPhotos)
    }
}

enum PhotoFilter {
    case all
    case favorites
    case recent
    case album(String)
} 