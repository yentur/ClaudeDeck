import AppKit
import DeckCore
import SwiftUI

extension Color {
    static let claude = Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)
    static let busyGreen = Color(red: 0x3F / 255, green: 0xB9 / 255, blue: 0x50 / 255)
    /// Subtle fill that works on both light and dark vibrancy.
    static func wash(_ opacity: Double) -> Color { Color.primary.opacity(opacity) }
}

/// Reserved status palette — always paired with an icon and a label, never used for identity.
enum StatusColor {
    static let good = Color(red: 0x0C / 255, green: 0xA3 / 255, blue: 0x0C / 255)
    static let warning = Color(red: 0xFA / 255, green: 0xB2 / 255, blue: 0x19 / 255)
    static let serious = Color(red: 0xEC / 255, green: 0x83 / 255, blue: 0x5A / 255)
    static let critical = Color(red: 0xD0 / 255, green: 0x3B / 255, blue: 0x3B / 255)
}

extension SessionActivity {
    var color: Color {
        switch self {
        case .busy: return .busyGreen
        case .shell: return .claude
        case .idle: return Color.secondary.opacity(0.55)
        case .other: return .blue
        }
    }
}

/// Small borderless icon button with a hover highlight.
struct IconButton: View {
    let systemName: String
    let help: String
    var tint: Color = .primary
    var size: CGFloat = 12
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(hovering ? tint : Color.secondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.wash(hovering ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

/// Animated status indicator; busy sessions get an expanding "heartbeat" ring.
struct StatusDot: View {
    let activity: SessionActivity
    let label: String

    var body: some View {
        ZStack {
            if activity == .busy {
                PulseRing(color: NSColor(activity.color))
            }
            Circle()
                .fill(activity.color)
                .frame(width: 8, height: 8)
                .shadow(color: activity == .busy ? activity.color.opacity(0.7) : .clear, radius: 3)
        }
        .frame(width: 16, height: 16)
        .help(label)
    }
}

/// Core Animation ring: the render server drives it, so a list full of busy sessions
/// doesn't keep a SwiftUI display link (and the CPU) spinning.
private struct PulseRing: NSViewRepresentable {
    let color: NSColor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let ring = CAShapeLayer()
        ring.fillColor = nil
        ring.lineWidth = 1.5
        view.layer?.addSublayer(ring)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let ring = view.layer?.sublayers?.first as? CAShapeLayer else { return }
        ring.strokeColor = color.cgColor
        DispatchQueue.main.async {
            let bounds = view.bounds
            guard bounds.width > 0 else { return }
            ring.frame = bounds
            ring.path = CGPath(ellipseIn: bounds.insetBy(dx: 1, dy: 1), transform: nil)
            guard ring.animation(forKey: "pulse") == nil else { return }

            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.45
            scale.toValue = 1.0
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.9
            fade.toValue = 0.0
            let group = CAAnimationGroup()
            group.animations = [scale, fade]
            group.duration = 1.3
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            group.repeatCount = .infinity
            ring.opacity = 0
            ring.add(group, forKey: "pulse")
        }
    }
}

struct PillButtonStyle: ButtonStyle {
    var fill: Color
    var foreground: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(fill.opacity(configuration.isPressed ? 0.7 : 1)))
            .contentShape(Capsule())
    }
}

/// Inline confirmation strip (never an alert: the non-activating panel must not steal focus).
struct ConfirmStrip: View {
    let text: String
    let actionTitle: String
    let cancelTitle: String
    let actionColor: Color
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10.5))
                .foregroundStyle(actionColor)
            Text(text).font(.system(size: 11)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(cancelTitle, action: onCancel)
                .buttonStyle(PillButtonStyle(fill: Color.wash(0.12), foreground: .primary))
            Button(actionTitle, action: onConfirm)
                .buttonStyle(PillButtonStyle(fill: actionColor))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(actionColor.opacity(0.13)))
    }
}
