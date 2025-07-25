# ADR-001: SwiftUI vs UIKit for UI Framework

**Status:** Accepted  
**Date:** 2025-01-XX  
**Participants:** [Development Team]  
**Related:** [technical-architecture.md](../specs/technical-architecture.md)

## Context

We need to choose the primary UI framework for building the photo organization app with Tinder-like swipe interactions. The app requires smooth animations, gesture handling, and rapid development iteration.

## Decision

We will use **SwiftUI** as the primary UI framework.

## Rationale

### SwiftUI Advantages

- **Gesture Handling:** Built-in pan, drag, and swipe gesture recognizers perfect for Tinder-like interactions
- **Animation System:** Declarative animations with smooth interpolation and spring physics
- **Development Speed:** Preview canvas enables rapid UI iteration and testing
- **State Management:** @State, @Published, and @ObservedObject provide reactive UI updates
- **Future-Proof:** Apple's recommended framework for new iOS development
- **Code Simplicity:** Significantly less boilerplate code for common UI patterns

### UIKit Disadvantages

- **Gesture Complexity:** Manual gesture recognizer setup and conflict resolution
- **Animation Overhead:** More complex animation code with CALayer and UIView animations
- **Development Friction:** Storyboard/programmatic UI requires more setup time
- **State Synchronization:** Manual UI updates when data changes

### Trade-offs Considered

- **Learning Curve:** SwiftUI has different paradigms, but team is committed to modern iOS development
- **Maturity:** SwiftUI on iOS 15+ is stable enough for production apps
- **Third-Party Libraries:** Some UIKit libraries unavailable, but SwiftUI ecosystem is growing

## Implementation Examples

### Swipe Gesture Implementation

```swift
struct SwipeablePhotoCard: View {
    @State private var offset = CGSize.zero
    @State private var rotation: Double = 0

    var body: some View {
        Image("photo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .offset(offset)
            .rotationEffect(.degrees(rotation))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        offset = value.translation
                        rotation = Double(value.translation.width / 20)
                    }
                    .onEnded { value in
                        handleSwipeEnd(translation: value.translation)
                    }
            )
    }

    private func handleSwipeEnd(translation: CGSize) {
        let threshold: CGFloat = 100

        if translation.x > threshold {
            // Swipe right - favorite
            animateOffScreen(direction: .right)
        } else if translation.x < -threshold {
            // Swipe left - trash
            animateOffScreen(direction: .left)
        } else {
            // Return to center
            withAnimation(.spring()) {
                offset = .zero
                rotation = 0
            }
        }
    }
}
```

### Animation Implementation

```swift
extension SwipeablePhotoCard {
    private func animateOffScreen(direction: SwipeDirection) {
        let exitOffset: CGSize

        switch direction {
        case .left:
            exitOffset = CGSize(width: -1000, height: 200)
        case .right:
            exitOffset = CGSize(width: 1000, height: 200)
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            offset = exitOffset
            rotation = direction == .left ? -45 : 45
        }

        // Trigger next photo load
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onSwipeComplete(direction)
        }
    }
}
```

## Consequences

### Positive

- Faster development of swipe interactions and animations
- Better maintainability with declarative UI code
- Excellent testing support with preview canvas
- Future compatibility with Apple's development direction
- Natural integration with Combine for reactive programming

### Negative

- Some advanced customizations may require UIViewRepresentable bridges
- Debugging UI issues can be different from traditional UIKit approaches
- Team needs to learn SwiftUI best practices

### Mitigation Strategies

- Use UIViewRepresentable for any missing SwiftUI functionality
- Establish SwiftUI coding standards and best practices early
- Leverage preview canvas extensively for UI debugging
- Create reusable SwiftUI components for common patterns

## Alternatives Considered

### UIKit with Manual Gesture Recognition

**Pros:** Full control over gesture handling, mature framework
**Cons:** Significant boilerplate, manual animation coordination, slower development

### React Native with Gesture Handler

**Pros:** Cross-platform development
**Cons:** Not native performance, additional complexity, not aligned with iOS-first strategy

### Flutter

**Pros:** Cross-platform, good gesture support
**Cons:** Not native, different toolchain, team expertise in Swift/iOS

## References

- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)
- [Human Interface Guidelines - Gestures](https://developer.apple.com/design/human-interface-guidelines/inputs/gestures)
- [SwiftUI Animation Guide](https://developer.apple.com/documentation/swiftui/animation)

## Review Notes

- Decision aligns with product requirements for rapid prototyping
- SwiftUI gesture system meets all technical requirements for photo swiping
- Team comfortable with learning curve given long-term benefits
- Preview canvas significantly improves development velocity

---

**Next Steps:**

1. Set up SwiftUI project structure
2. Create reusable gesture components
3. Establish SwiftUI coding conventions
4. Begin implementation of core swipe interface
