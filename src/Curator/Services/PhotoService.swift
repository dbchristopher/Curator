import Photos
import UIKit
import Combine

protocol PhotoServiceProtocol {
    func requestPhotoLibraryAccess() async -> PHAuthorizationStatus
    func fetchPhotos() async -> [PHAsset]
    func loadImage(for asset: PHAsset, targetSize: CGSize) async -> UIImage?
    func processActions(_ actions: [PhotoAction]) async
}

class PhotoService: PhotoServiceProtocol {
    private let imageManager = PHImageManager.default()
    private let imageCache = NSCache<NSString, UIImage>()
    
    init() {
        // Configure cache
        imageCache.countLimit = 50
        imageCache.totalCostLimit = 50 * 1024 * 1024 // 50MB
    }
    
    func requestPhotoLibraryAccess() async -> PHAuthorizationStatus {
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }
    
    func fetchPhotos() async -> [PHAsset] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
        
        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        
        var photos: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            photos.append(asset)
        }
        
        return photos
    }
    
    func loadImage(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        let cacheKey = "\(asset.localIdentifier)_\(Int(targetSize.width))x\(Int(targetSize.height))" as NSString
        
        // Check cache first
        if let cachedImage = imageCache.object(forKey: cacheKey) {
            return cachedImage
        }
        
        return await withCheckedContinuation { continuation in
            let requestOptions = PHImageRequestOptions()
            requestOptions.deliveryMode = .highQualityFormat
            requestOptions.isNetworkAccessAllowed = true
            requestOptions.isSynchronous = false
            
            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: requestOptions
            ) { image, info in
                if let image = image {
                    self.imageCache.setObject(image, forKey: cacheKey)
                }
                continuation.resume(returning: image)
            }
        }
    }
    
    func processActions(_ actions: [PhotoAction]) async {
        // Group actions by type for batch processing
        let keepActions = actions.filter { $0.direction == .right }
        let trashActions = actions.filter { $0.direction == .left }
        
        // Process keep actions (add to favorites album)
        if !keepActions.isEmpty {
            await addPhotosToFavorites(keepActions.map { $0.photo })
        }
        
        // Process trash actions (move to recently deleted)
        if !trashActions.isEmpty {
            await movePhotosToTrash(trashActions.map { $0.photo })
        }
    }
    
    private func addPhotosToFavorites(_ photos: [PHAsset]) async {
        // Create or find favorites album
        let favoritesAlbum = await getOrCreateFavoritesAlbum()
        
        await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest(for: favoritesAlbum)
            request?.addAssets(photos as NSFastEnumeration)
        }
    }
    
    private func movePhotosToTrash(_ photos: [PHAsset]) async {
        await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(photos as NSFastEnumeration)
        }
    }
    
    private func getOrCreateFavoritesAlbum() async -> PHAssetCollection {
        // First try to find existing favorites album
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", "Curator Favorites")
        let fetchResult = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
        
        if let existingAlbum = fetchResult.firstObject {
            return existingAlbum
        }
        
        // Create new favorites album
        var createdAlbum: PHAssetCollection?
        await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: "Curator Favorites")
            createdAlbum = request.placeholderForCreatedAssetCollection
        }
        
        // Fetch the created album
        if let placeholder = createdAlbum {
            let fetchResult = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [placeholder.localIdentifier], options: nil)
            return fetchResult.firstObject ?? PHAssetCollection()
        }
        
        return PHAssetCollection()
    }
}

// MARK: - Extensions
extension PHAsset {
    var isFavorite: Bool {
        get { return self.isFavorite }
        set {
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetChangeRequest(for: self)
                request.isFavorite = newValue
            }
        }
    }
} 