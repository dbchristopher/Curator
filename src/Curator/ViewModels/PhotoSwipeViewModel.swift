import SwiftUI
import Photos
import Combine

@MainActor
class PhotoSwipeViewModel: ObservableObject {
    @Published var currentPhoto: PHAsset?
    @Published var actionQueue: [PhotoAction] = []
    @Published var undoStack: [PhotoAction] = []
    @Published var isProcessing: Bool = false
    @Published var photos: [PHAsset] = []
    @Published var currentIndex: Int = 0
    
    private let photoService = PhotoService()
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Initialize with empty state
    }
    
    func loadPhotos() {
        Task {
            await photoService.requestPhotoLibraryAccess()
            let fetchedPhotos = await photoService.fetchPhotos()
            
            await MainActor.run {
                self.photos = fetchedPhotos
                self.currentPhoto = fetchedPhotos.first
                self.currentIndex = 0
            }
        }
    }
    
    func swipeLeft() {
        guard let photo = currentPhoto else { return }
        
        let action = PhotoAction(
            photo: photo,
            direction: .left,
            timestamp: Date()
        )
        
        actionQueue.append(action)
        moveToNextPhoto()
    }
    
    func swipeRight() {
        guard let photo = currentPhoto else { return }
        
        let action = PhotoAction(
            photo: photo,
            direction: .right,
            timestamp: Date()
        )
        
        actionQueue.append(action)
        moveToNextPhoto()
    }
    
    func undo() {
        guard let lastAction = actionQueue.popLast() else { return }
        undoStack.append(lastAction)
        
        // Move back to previous photo
        if currentIndex > 0 {
            currentIndex -= 1
            currentPhoto = photos[currentIndex]
        }
    }
    
    func redo() {
        guard let lastUndo = undoStack.popLast() else { return }
        actionQueue.append(lastUndo)
        
        // Move to next photo
        moveToNextPhoto()
    }
    
    private func moveToNextPhoto() {
        if currentIndex < photos.count - 1 {
            currentIndex += 1
            currentPhoto = photos[currentIndex]
        } else {
            // End of photos - could trigger session completion
            handleSessionCompletion()
        }
    }
    
    private func handleSessionCompletion() {
        // Process all pending actions
        Task {
            await processPendingActions()
        }
    }
    
    private func processPendingActions() async {
        isProcessing = true
        
        // Process actions in background
        await photoService.processActions(actionQueue)
        
        await MainActor.run {
            actionQueue.removeAll()
            isProcessing = false
        }
    }
}

// MARK: - Supporting Models
struct PhotoAction {
    let photo: PHAsset
    let direction: SwipeDirection
    let timestamp: Date
}

enum SwipeDirection {
    case left  // Trash
    case right // Keep
    case up    // Keep (alternative)
} 