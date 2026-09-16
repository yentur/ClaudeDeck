import AppKit
import SwiftUI

/// Transparent view that turns a mouse drag into a window move (used behind the header).
struct WindowDragHandle: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Bottom-left corner grip: resizes the card while its top-right corner stays anchored.
struct ResizeGrip: NSViewRepresentable {
    final class GripView: NSView {
        private var startFrame: NSRect = .zero
        private var startMouse: NSPoint = .zero

        override func resetCursorRects() {
            if #available(macOS 15.0, *) {
                addCursorRect(bounds, cursor: .frameResize(position: .bottomLeft, directions: .all))
            } else {
                addCursorRect(bounds, cursor: .crosshair)
            }
        }

        override func mouseDown(with event: NSEvent) {
            startFrame = window?.frame ?? .zero
            startMouse = NSEvent.mouseLocation
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window else { return }
            let mouse = NSEvent.mouseLocation
            let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? startFrame
            let width = min(max(startFrame.width - (mouse.x - startMouse.x), window.minSize.width), visible.width)
            let height = min(max(startFrame.height - (mouse.y - startMouse.y), window.minSize.height), visible.height)
            let frame = NSRect(x: startFrame.maxX - width, y: startFrame.maxY - height, width: width, height: height)
            window.setFrame(frame, display: true)
        }
    }

    func makeNSView(context: Context) -> NSView { GripView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
