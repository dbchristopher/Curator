import SwiftUI
import Photos

@main
struct CuratorApp: App {
    @StateObject private var appStateViewModel = AppStateViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appStateViewModel)
                .onAppear {
                    // Request photo library permission on app launch
                    requestPhotoLibraryPermission()
                }
        }
    }
    
    private func requestPhotoLibraryPermission() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                appStateViewModel.photoLibraryPermission = status
            }
        }
    }
} 