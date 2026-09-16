import AppKit
import Combine
import SwiftUI

/// Borderless, non-activating floating panel: clicking it never steals focus from the
/// app you're working in, yet it can still become key so the search field accepts typing.
final class DeckPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        minSize = PanelController.minSize
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Vibrancy background that reports pointer enter/exit even while the app is inactive.
final class HoverTrackingEffectView: NSVisualEffectView {
    var onHoverChange: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }
}

/// Lets the first click on an inactive card hit the button under the cursor.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class PanelController: NSObject, ObservableObject, NSWindowDelegate {
    static let defaultSize = NSSize(width: 360, height: 520)
    static let minSize = NSSize(width: 280, height: 180)
    static let margin = (right: CGFloat(12), top: CGFloat(8))
    static let cornerRadius: CGFloat = 16

    let panel: DeckPanel
    let settings: AppSettings
    private var hovering = false
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings) {
        self.settings = settings
        panel = DeckPanel(contentRect: NSRect(origin: .zero, size: Self.defaultSize))
        super.init()
        panel.delegate = self

        let effect = HoverTrackingEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.roundedMask(radius: Self.cornerRadius)
        panel.contentView = effect
        effect.onHoverChange = { [weak self] inside in self?.setHovering(inside) }

        restoreFrame()

        settings.$opacity.sink { [weak self] _ in self?.applyAlpha(animated: false) }.store(in: &cancellables)
        settings.$hoverOpaque.sink { [weak self] _ in
            DispatchQueue.main.async { self?.applyAlpha(animated: false) }
        }.store(in: &cancellables)
        settings.$alwaysOnTop.sink { [weak self] onTop in self?.panel.level = onTop ? .floating : .normal }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.ensureOnScreen() }
            .store(in: &cancellables)
    }

    func install<Content: View>(rootView: Content) {
        guard let effect = panel.contentView else { return }
        let hosting = FirstMouseHostingView(rootView: rootView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
    }

    var isVisible: Bool { panel.isVisible }

    func show() {
        ensureOnScreen()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    /// Snaps the card to the top-right corner of the screen it's on (or the main screen).
    func pinTopRight(size: NSSize? = nil) {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let target = size ?? panel.frame.size
        let width = min(max(target.width, Self.minSize.width), visible.width - Self.margin.right * 2)
        let height = min(max(target.height, Self.minSize.height), visible.height - Self.margin.top * 2)
        let frame = NSRect(x: visible.maxX - width - Self.margin.right,
                           y: visible.maxY - height - Self.margin.top,
                           width: width, height: height)
        panel.setFrame(frame, display: true, animate: panel.isVisible)
    }

    /// Resizes while keeping the top-right corner fixed.
    func resize(to size: NSSize) {
        var frame = panel.frame
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame ?? frame
        let width = min(max(size.width, Self.minSize.width), visible.width)
        let height = min(max(size.height, Self.minSize.height), visible.height)
        frame.origin.x = frame.maxX - width
        frame.origin.y = frame.maxY - height
        frame.size = NSSize(width: width, height: height)
        panel.setFrame(frame, display: true, animate: true)
    }

    func setHovering(_ value: Bool) {
        guard hovering != value else { return }
        hovering = value
        applyAlpha(animated: true)
    }

    private func applyAlpha(animated: Bool) {
        let target = (settings.hoverOpaque && hovering) ? 1.0 : settings.opacity
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                panel.animator().alphaValue = target
            }
        } else {
            panel.alphaValue = target
        }
    }

    private func restoreFrame() {
        if let stored = settings.frame {
            let frame = NSRectFromString(stored)
            if frame.width >= Self.minSize.width, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
                panel.setFrame(frame, display: false)
                return
            }
        }
        pinTopRight(size: Self.defaultSize)
    }

    private func ensureOnScreen() {
        let frame = panel.frame
        let onScreen = NSScreen.screens.contains { screen in
            let overlap = screen.visibleFrame.intersection(frame)
            return overlap.width >= 80 && overlap.height >= 40
        }
        if !onScreen { pinTopRight() }
    }

    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidResize(_ notification: Notification) {
        saveFrame()
        panel.invalidateShadow()
    }

    /// Dev-only: renders the card into a PNG (vibrancy approximated with a flat HUD tone),
    /// for environments where screen capture isn't permitted.
    func writeSnapshot(to path: String, dark: Bool = true) {
        guard let view = panel.contentView, let content = view.subviews.first,
              let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: rep)
        // Keep the backing scale (2x on Retina) so README images stay sharp.
        let size = view.bounds.size
        let scale = max(1, CGFloat(rep.pixelsWide) / max(1, content.bounds.width))
        guard let output = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }
        output.size = size   // must precede the context so drawing is scaled from points to pixels
        guard let context = NSGraphicsContext(bitmapImageRep: output) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let rect = NSRect(origin: .zero, size: size)
        (dark ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
        NSBezierPath(roundedRect: rect, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius).fill()
        rep.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = output.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    private func saveFrame() {
        settings.frame = NSStringFromRect(panel.frame)
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
