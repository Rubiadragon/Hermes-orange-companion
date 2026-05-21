import AppKit

class KeyableWindow: NSWindow {
    var onCloseRequest: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performClose(_ sender: Any?) {
        if let onCloseRequest {
            onCloseRequest()
        } else {
            super.performClose(sender)
        }
    }
}

class DraggablePopoverRootView: NSView {
    var onManualDragBegan: (() -> Void)?
    var onManualDragEnded: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onManualDragBegan?()
        window?.performDrag(with: event)
        onManualDragEnded?()
    }
}

class CharacterContentView: NSView {
    weak var character: WalkerCharacter?
    private var dragStartScreenPoint: NSPoint?
    private var dragStartWindowOrigin: NSPoint?
    private var dragGrabPoint: NSPoint?
    private var pendingSingleClickWorkItem: DispatchWorkItem?
    private var didDrag = false
    private let dragThreshold: CGFloat = 6

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        guard bounds.contains(localPoint) else { return nil }

        // Keep interaction forgiving while the animation assets change shape.
        // Precise alpha hit-testing can come back with ScreenCaptureKit later.
        return self
    }

    override func mouseDown(with event: NSEvent) {
        guard let window = window else { return }
        dragStartScreenPoint = NSEvent.mouseLocation
        dragStartWindowOrigin = window.frame.origin
        dragGrabPoint = convert(event.locationInWindow, from: nil)
        didDrag = false
        character?.playInflatablePress()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let character = character,
              let startPoint = dragStartScreenPoint,
              let startOrigin = dragStartWindowOrigin else { return }

        let current = NSEvent.mouseLocation
        let dx = current.x - startPoint.x
        let dy = current.y - startPoint.y

        if !didDrag, hypot(dx, dy) >= dragThreshold {
            didDrag = true
            character.beginManualDrag(grabPoint: dragGrabPoint ?? .zero)
        }

        guard didDrag else { return }
        let newOrigin = NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy)
        character.updateManualDragOrigin(newOrigin, pointer: current, delta: CGVector(dx: dx, dy: dy))
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStartScreenPoint = nil
            dragStartWindowOrigin = nil
            dragGrabPoint = nil
        }

        guard let character = character else { return }
        if didDrag {
            pendingSingleClickWorkItem?.cancel()
            pendingSingleClickWorkItem = nil
            character.endManualDrag()
        } else if event.clickCount >= 2 {
            pendingSingleClickWorkItem?.cancel()
            pendingSingleClickWorkItem = nil
            character.applyPokeInteraction()
            character.toggleFormForCurrentAnimation()
        } else {
            pendingSingleClickWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak character] in
                character?.toggleActionMenu()
            }
            pendingSingleClickWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: workItem)
        }
    }
}
