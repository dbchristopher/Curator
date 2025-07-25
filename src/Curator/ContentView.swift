import SwiftUI
import Photos

struct ContentView: View {
    @EnvironmentObject var appStateViewModel: AppStateViewModel
    @StateObject private var photoSwipeViewModel = PhotoSwipeViewModel()
    
    var body: some View {
        NavigationView {
            Group {
                switch appStateViewModel.photoLibraryPermission {
                case .authorized, .limited:
                    PhotoSwipeView()
                        .environmentObject(photoSwipeViewModel)
                case .denied, .restricted:
                    PermissionDeniedView()
                case .notDetermined:
                    PermissionRequestView()
                @unknown default:
                    PermissionRequestView()
                }
            }
            .navigationTitle("Curator")
            .navigationBarTitleDisplayMode(.large)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

// MARK: - Photo Swipe View
struct PhotoSwipeView: View {
    @EnvironmentObject var photoSwipeViewModel: PhotoSwipeViewModel
    @State private var dragOffset = CGSize.zero
    @State private var isDragging = false
    
    var body: some View {
        VStack {
            if let currentPhoto = photoSwipeViewModel.currentPhoto {
                SwipeablePhotoCard(
                    photo: currentPhoto,
                    dragOffset: $dragOffset,
                    isDragging: $isDragging
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation
                            isDragging = true
                        }
                        .onEnded { value in
                            handleSwipe(value)
                        }
                )
            } else {
                LoadingView()
            }
            
            // Action buttons
            HStack(spacing: 40) {
                ActionButton(
                    title: "Trash",
                    icon: "trash",
                    color: .red
                ) {
                    photoSwipeViewModel.swipeLeft()
                }
                
                ActionButton(
                    title: "Keep",
                    icon: "heart",
                    color: .green
                ) {
                    photoSwipeViewModel.swipeRight()
                }
            }
            .padding(.bottom, 50)
        }
        .onAppear {
            photoSwipeViewModel.loadPhotos()
        }
    }
    
    private func handleSwipe(_ value: DragGesture.Value) {
        let threshold: CGFloat = 100
        let velocity = value.predictedEndTranslation.x - value.translation.x
        
        if abs(value.translation.x) > threshold || abs(velocity) > 500 {
            if value.translation.x > 0 {
                photoSwipeViewModel.swipeRight()
            } else {
                photoSwipeViewModel.swipeLeft()
            }
        }
        
        withAnimation(.spring()) {
            dragOffset = .zero
            isDragging = false
        }
    }
}

// MARK: - Swipeable Photo Card
struct SwipeablePhotoCard: View {
    let photo: PHAsset
    @Binding var dragOffset: CGSize
    @Binding var isDragging: Bool
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AsyncImage(url: nil) { // Will be implemented with PhotoKit
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        )
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        )
                }
                .frame(width: geometry.size.width * 0.9, height: geometry.size.height * 0.8)
                .cornerRadius(20)
                .shadow(radius: 10)
                .offset(dragOffset)
                .scaleEffect(isDragging ? 1.05 : 1.0)
                .rotationEffect(.degrees(Double(dragOffset.x / 20)))
                
                // Swipe direction indicators
                if isDragging {
                    HStack {
                        if dragOffset.x < -50 {
                            Spacer()
                            VStack {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(.red)
                                Text("Trash")
                                    .font(.headline)
                                    .foregroundColor(.red)
                            }
                            .padding(.trailing, 50)
                        }
                        
                        if dragOffset.x > 50 {
                            VStack {
                                Image(systemName: "heart.circle.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(.green)
                                Text("Keep")
                                    .font(.headline)
                                    .foregroundColor(.green)
                            }
                            .padding(.leading, 50)
                            Spacer()
                        }
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Action Button
struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack {
                Image(systemName: icon)
                    .font(.system(size: 30))
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(color)
            }
            .frame(width: 80, height: 80)
            .background(Color.white)
            .cornerRadius(40)
            .shadow(radius: 5)
        }
    }
}

// MARK: - Loading View
struct LoadingView: View {
    var body: some View {
        VStack {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                .scaleEffect(1.5)
            Text("Loading photos...")
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.top)
        }
    }
}

// MARK: - Permission Views
struct PermissionRequestView: View {
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            Text("Welcome to Curator")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Curator helps you organize your photos through an intuitive swipe interface. We need access to your photo library to get started.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Text("Your photos stay on your device and are never shared.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}

struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 80))
                .foregroundColor(.red)
            
            Text("Photo Access Required")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Curator needs access to your photo library to help you organize your photos. Please enable photo access in Settings.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Open Settings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppStateViewModel())
    }
} 