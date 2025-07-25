# Curator iOS App

A SwiftUI-based iOS app for intuitive photo organization through swipe interactions.

## Overview

Curator is a photo management app that makes organizing your photo library easy, fun, and fast through Tinder-like swipe interactions. Users can quickly sort through their photos by swiping left (trash) or right (keep).

## Features

- **Photo Library Access**: Secure access to user's photo library using PhotoKit
- **Swipe Interface**: Intuitive left/right swipe gestures for photo organization
- **Permission Handling**: Graceful handling of photo library permissions
- **Batch Processing**: Efficient processing of photo actions
- **Undo/Redo**: Support for undoing and redoing photo actions
- **Modern UI**: SwiftUI-based interface with smooth animations

## Architecture

The app follows MVVM (Model-View-ViewModel) architecture with clean separation of concerns:

### View Layer (SwiftUI)

- `ContentView.swift`: Main app interface
- `PhotoSwipeView.swift`: Photo swiping interface
- `SwipeablePhotoCard.swift`: Individual photo card component

### ViewModel Layer

- `AppStateViewModel.swift`: Global app state management
- `PhotoSwipeViewModel.swift`: Photo swiping business logic

### Service Layer

- `PhotoService.swift`: PhotoKit interactions and photo management

### Models

- `PhotoAction.swift`: Photo action data structures
- `SessionProgress.swift`: Session tracking models

## Requirements

- iOS 15.0+
- Xcode 14.0+
- Swift 5.7+

## Setup

1. Open `Curator.xcodeproj` in Xcode
2. Select your development team in project settings
3. Build and run on device or simulator

## Privacy

- All photo processing happens on-device
- No photo data is transmitted externally
- Photo library access is requested with clear explanation
- Supports iOS 14+ limited photo access

## Development

### Project Structure

```
src/Curator/
├── CuratorApp.swift          # App entry point
├── ContentView.swift         # Main content view
├── ViewModels/              # ViewModels
│   ├── AppStateViewModel.swift
│   └── PhotoSwipeViewModel.swift
├── Services/                # Service layer
│   └── PhotoService.swift
├── Assets.xcassets/         # App assets
└── Preview Content/         # SwiftUI previews
```

### Key Components

#### PhotoService

Handles all PhotoKit interactions:

- Photo library access requests
- Photo fetching and loading
- Image caching
- Batch action processing

#### PhotoSwipeViewModel

Manages the photo swiping session:

- Current photo state
- Action queue management
- Undo/redo functionality
- Session progress tracking

#### AppStateViewModel

Global app state:

- Photo library permissions
- Session progress
- Current filters and settings

## Future Enhancements

- Smart suggestions for duplicate detection
- Advanced filtering options
- Cloud sync capabilities
- Social sharing features
- AI-powered categorization

## Testing

The app includes comprehensive unit tests for:

- ViewModel business logic
- Service layer operations
- Photo action processing
- Permission handling

## Performance

- Optimized image loading with caching
- Background processing for batch operations
- Memory-efficient photo handling
- Smooth 60fps animations

## License

See LICENSE file for details.
