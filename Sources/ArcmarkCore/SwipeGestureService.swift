import AppKit

enum SwipeDirection: Sendable {
    case left, right
}

@MainActor
protocol SwipeGestureServiceDelegate: AnyObject {
    func swipeGestureDidBegin(_ service: SwipeGestureService)
    func swipeGestureDidUpdate(_ service: SwipeGestureService, translationX: CGFloat)
    func swipeGestureDidComplete(_ service: SwipeGestureService, direction: SwipeDirection)
    func swipeGestureDidCancel(_ service: SwipeGestureService)
}

/// Detects horizontal trackpad swipes via global+local NSEvent monitors.
/// Not @MainActor so event monitor callbacks can access state synchronously
/// (event monitors always run on main thread).
final class SwipeGestureService: @unchecked Sendable {
    @MainActor static let shared = SwipeGestureService()

    @MainActor weak var delegate: SwipeGestureServiceDelegate?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private weak var window: NSWindow?

    // Gesture state — accessed synchronously from main-thread event monitor callbacks
    private var isTracking = false
    private var accumulatedDeltaX: CGFloat = 0
    private var accumulatedDeltaY: CGFloat = 0
    private var gestureDecided = false
    private var isHorizontalGesture = false
    private var hasTriggered = false

    private let directionLockThreshold: CGFloat = 10
    private let triggerThreshold: CGFloat = 50

    private init() {}

    @MainActor
    func enable(window: NSWindow) {
        self.window = window
        disable()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScrollEvent(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }

            // Handle event synchronously so state is updated before consume decision
            self.handleScrollEvent(event)

            // Consume event if tracking and either undecided or confirmed horizontal
            if event.hasPreciseScrollingDeltas,
               self.isTracking && (!self.gestureDecided || self.isHorizontalGesture) {
                return nil
            }
            return event
        }
    }

    @MainActor
    func disable() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        resetState()
    }

    private func handleScrollEvent(_ event: NSEvent) {
        // Trackpad only — ignore mouse scroll wheels
        guard event.hasPreciseScrollingDeltas else { return }

        switch event.phase {
        case .began:
            handleBegan(event)
        case .changed:
            handleChanged(event)
        case .ended, .cancelled:
            handleEnded()
        default:
            if event.momentumPhase != [] {
                return
            }
        }
    }

    private func handleBegan(_ event: NSEvent) {
        guard let window else { return }

        let mouseLocation = NSEvent.mouseLocation
        guard window.frame.contains(mouseLocation) else { return }

        resetState()
        isTracking = true
        notifyDelegate { $0.swipeGestureDidBegin(self) }
    }

    private func handleChanged(_ event: NSEvent) {
        guard isTracking, !hasTriggered else { return }

        accumulatedDeltaX += event.scrollingDeltaX
        accumulatedDeltaY += event.scrollingDeltaY

        if !gestureDecided {
            let totalMovement = abs(accumulatedDeltaX) + abs(accumulatedDeltaY)
            if totalMovement >= directionLockThreshold {
                gestureDecided = true
                isHorizontalGesture = abs(accumulatedDeltaX) > abs(accumulatedDeltaY) * 1.5
                if !isHorizontalGesture {
                    isTracking = false
                    notifyDelegate { $0.swipeGestureDidCancel(self) }
                    return
                }
            } else {
                return
            }
        }

        guard isHorizontalGesture else { return }

        let translationX = accumulatedDeltaX
        notifyDelegate { $0.swipeGestureDidUpdate(self, translationX: translationX) }

        if abs(accumulatedDeltaX) > triggerThreshold {
            hasTriggered = true
            let direction: SwipeDirection = accumulatedDeltaX < 0 ? .left : .right
            notifyDelegate { $0.swipeGestureDidComplete(self, direction: direction) }
        }
    }

    private func handleEnded() {
        guard isTracking else { return }

        if !hasTriggered && gestureDecided && isHorizontalGesture {
            notifyDelegate { $0.swipeGestureDidCancel(self) }
        }

        resetState()
    }

    private func resetState() {
        isTracking = false
        accumulatedDeltaX = 0
        accumulatedDeltaY = 0
        gestureDecided = false
        isHorizontalGesture = false
        hasTriggered = false
    }

    /// Dispatches delegate calls on MainActor. Since event monitors run on
    /// the main thread, this executes synchronously via assumeIsolated.
    private func notifyDelegate(_ body: @escaping @MainActor (SwipeGestureServiceDelegate) -> Void) {
        MainActor.assumeIsolated {
            guard let delegate = self.delegate else { return }
            body(delegate)
        }
    }
}
