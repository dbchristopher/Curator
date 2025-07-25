# Feature Specification: Photo Swiping Interface

**Feature:** Core Swipe Interaction  
**Version:** 1.0  
**Status:** Ready for Implementation  
**Related ADR:** [adr-001-swipe-vs-buttons.md](../decisions/adr-001-swipe-vs-buttons.md)

## Overview

The core interaction pattern that allows users to quickly categorize photos using familiar swipe gestures. This is the primary value driver of the application.

## Requirements

### Functional Requirements

**FR-1: Basic Swipe Detection**

- Detect horizontal swipe gestures on photo cards
- Left swipe = Trash (delete)
- Right swipe = Favorite (keep and mark as favorite)
- Vertical swipe up = Keep (neutral positive)

**FR-2: Visual Feedback**

- Real-time visual indicators during swipe
- Color-coded feedback: Red (trash), Green (favorite), Blue (keep)
- Card translation follows finger movement
- Overlay icons appear based on swipe direction

**FR-3: Action Confirmation**

- Actions execute when swipe crosses threshold (50% of screen width)
- Smooth animation completes the card movement
- Next photo automatically appears
- Provide undo option for last 5 actions

**FR-4: Batch Processing**

- Queue actions in memory during session
- Apply changes in batches for performance
- Show progress indicator for current session
- Allow review before committing changes

### Non-Functional Requirements

**NFR-1: Performance**

- Swipe response latency < 50ms
- Smooth 60fps animations
- Preload next 3 photos for instant display
- Handle libraries with 10,000+ photos without degradation

**NFR-2: Accessibility**

- VoiceOver support for swipe actions
- Alternative button interface for users who can't swipe
- High contrast mode support
- Dynamic Type support for text overlays

**NFR-3: Reliability**

- Never lose user decisions due to crashes
- Graceful handling of photo access permission changes
- Proper memory management for large photo libraries

## Technical Design

### SwipeablePhotoCard Component

```swift
struct SwipeablePhotoCard: View {
    @State private var offset = CGSize.zero
    @State private var rotation: Double = 0

    let photo: PHAsset
    let onSwipe: (SwipeDirection) -> Void

    var body: some View {
        // Photo display with gesture handling
    }
}

enum SwipeDirection {
    case trash      // Left swipe
    case favorite   // Right swipe
    case keep       // Up swipe
}
```

### State Management

```swift
class PhotoSwipeViewModel: ObservableObject {
    @Published var currentPhoto: PHAsset?
    @Published var photoQueue: [PHAsset] = []
    @Published var actionHistory: [PhotoAction] = []

    func processSwipe(_ direction: SwipeDirection, for photo: PHAsset)
    func undoLastAction()
    func commitPendingActions()
}

struct PhotoAction {
    let photo: PHAsset
    let action: SwipeDirection
    let timestamp: Date
}
```

### Animation System

**Swipe Animation Curve:**

- Duration: 0.3 seconds
- Easing: `easeOut` for natural feel
- Card exits screen completely before next appears
- Rotation: Slight tilt during swipe (max 15 degrees)

**Visual Feedback:**

- Threshold indicators at 25%, 50%, 75% of swipe
- Color intensity increases with swipe distance
- Haptic feedback at decision threshold (50%)

## User Interface Specification

### Photo Card Layout

```
┌─────────────────────────┐
│  [Undo] [Session: 23]   │  <- Header with undo and progress
│                         │
│  ┌─────────────────────┐│
│  │                     ││  <- Photo display area
│  │       Photo         ││     (maintains aspect ratio)
│  │                     ││
│  └─────────────────────┘│
│                         │
│  ←[Trash] [Keep]↑ [❤]→  │  <- Action hints
└─────────────────────────┘
```

### Swipe Visual States

**Default State:**

- Photo centered, no overlay
- Subtle drop shadow
- Action hints visible at bottom

**During Swipe (Left - Trash):**

- Card translates and rotates slightly left
- Red overlay with trash icon appears
- Intensity increases with swipe distance

**During Swipe (Right - Favorite):**

- Card translates and rotates slightly right
- Green overlay with heart icon appears
- Intensity increases with swipe distance

**During Swipe (Up - Keep):**

- Card translates up with slight scale
- Blue overlay with checkmark appears
- Less dramatic than left/right swipes

## Implementation Plan

### Phase 1: Basic Swipe Detection (Week 1)

- [ ] Create SwipeablePhotoCard view
- [ ] Implement pan gesture recognition
- [ ] Add basic card translation
- [ ] Test with sample photos

### Phase 2: Visual Feedback (Week 2)

- [ ] Add color overlays during swipe
- [ ] Implement rotation and scale effects
- [ ] Add action icons (trash, heart, check)
- [ ] Polish animation timing

### Phase 3: Action Processing (Week 3)

- [ ] Integrate with PhotoKit for real photos
- [ ] Implement action queueing system
- [ ] Add undo functionality
- [ ] Create batch processing logic

### Phase 4: Polish & Accessibility (Week 4)

- [ ] Add haptic feedback
- [ ] Implement VoiceOver support
- [ ] Add alternative button interface
- [ ] Performance optimization and testing

## Testing Strategy

### Unit Tests

- Swipe gesture recognition accuracy
- Action queueing and undo logic
- Edge cases (quick swipes, direction changes)

### Integration Tests

- PhotoKit integration
- Memory management with large libraries
- Action persistence across app lifecycle

### User Testing

- Swipe gesture discoverability
- Decision-making speed vs accuracy
- Fatigue testing (100+ swipes in session)

## Acceptance Criteria

- [ ] User can swipe left to mark photo for trash
- [ ] User can swipe right to mark photo as favorite
- [ ] User can swipe up to mark photo as keep
- [ ] Visual feedback clearly indicates intended action
- [ ] Actions can be undone within same session
- [ ] Animations feel smooth and responsive
- [ ] Works with photos of all aspect ratios
- [ ] Accessible via VoiceOver and alternative controls
- [ ] Handles edge cases gracefully (permission changes, etc.)

## Open Questions

1. Should we allow diagonal swipes or force cardinal directions?
2. What happens when user reaches end of photo library?
3. Should we show confirmation dialog before committing batch actions?
4. How do we handle very large photo libraries (20k+ photos)?

---

**Dependencies:**

- PhotoKit access granted
- SwiftUI navigation system
- Photo loading and caching system

**Related Specifications:**

- [photo-import.md](./photo-import.md) - Photo library access
- [organization-system.md](./organization-system.md) - Action processing
