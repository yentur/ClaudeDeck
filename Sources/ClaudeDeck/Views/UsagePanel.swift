import DeckCore
import SwiftUI

/// KPI row: sessions, total memory (meter against physical RAM), total CPU (10-minute sparkline).
struct UsagePanel: View {
    @EnvironmentObject var store: DeckStore
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        let s = settings.strings
        let language = settings.language
        let share = store.systemMemory > 0 ? Double(store.totals.memoryBytes) / Double(store.systemMemory) : 0

        HStack(spacing: 6) {
            StatTile(label: s.sessionsTile, value: "\(store.sessions.count)",
                     caption: s.sessionsCaption(busy: store.busyCount, asleep: store.sleeping.count, processes: store.totals.processCount)) {
                ActivityBar(working: store.busyCount, total: store.sessions.count)
            }
            StatTile(label: s.memoryTile, value: Fmt.bytes(store.totals.memoryBytes, language),
                     caption: s.ramShare(percent: Int((share * 100).rounded()), total: store.systemMemory),
                     captionIcon: share >= 0.6 ? "exclamationmark.triangle.fill" : nil,
                     captionIconColor: Meter.color(for: share)) {
                Meter(fraction: share)
            }
            .help(s.memoryHelp)
            CPUTile()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

struct StatTile<Accessory: View>: View {
    let label: String
    let value: String
    let caption: String
    var captionIcon: String?
    var captionIconColor: Color = .secondary
    @ViewBuilder let accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            accessory
                .frame(height: 14)
            HStack(spacing: 3) {
                if let captionIcon {
                    Image(systemName: captionIcon).font(.system(size: 8.5)).foregroundStyle(captionIconColor)
                }
                Text(caption)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.wash(0.06)))
    }
}

/// Share of physical RAM. The fill carries severity; the caption repeats it with an icon.
struct Meter: View {
    let fraction: Double

    static func color(for fraction: Double) -> Color {
        switch fraction {
        case ..<0.6: return Color.primary.opacity(0.55)
        case ..<0.85: return StatusColor.warning
        default: return StatusColor.critical
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.wash(0.12))
                Capsule()
                    .fill(Self.color(for: fraction))
                    .frame(width: max(4, proxy.size.width * min(fraction, 1)))
            }
            .frame(height: 4)
            .frame(maxHeight: .infinity)
        }
    }
}

/// Working vs idle sessions as a two-part bar (2 pt surface gap between the parts).
private struct ActivityBar: View {
    let working: Int
    let total: Int

    var body: some View {
        GeometryReader { proxy in
            let fraction = total > 0 ? CGFloat(working) / CGFloat(total) : 0
            HStack(spacing: working > 0 && working < total ? 2 : 0) {
                if working > 0 {
                    Capsule().fill(Color.busyGreen).frame(width: max(4, (proxy.size.width - 2) * fraction))
                }
                if working < total { Capsule().fill(Color.wash(0.12)) }
            }
            .frame(height: 4)
            .frame(maxHeight: .infinity)
        }
    }
}

/// Total CPU with a sparkline of the last ~10 minutes; hovering reads out any point.
private struct CPUTile: View {
    @EnvironmentObject var store: DeckStore
    @EnvironmentObject var settings: AppSettings
    @State private var hoverIndex: Int?

    var body: some View {
        let s = settings.strings
        let samples = store.history.samples
        let hovered = hoverIndex.flatMap { samples.indices.contains($0) ? samples[$0] : nil }
        let caption = hovered.map {
            s.cpuHover(value: Fmt.percent($0.cpuPercent, settings.language), ago: Fmt.relative($0.at, now: Date(), settings.language))
        } ?? s.cpuCaption(cores: store.cpuCores)

        StatTile(label: s.cpuTile, value: Fmt.percent(store.totals.cpuPercent, settings.language), caption: caption) {
            Sparkline(values: samples.map(\.cpuPercent), floor: 10, highlight: hoverIndex)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        guard samples.count > 1 else { return }
                        // Width is the tile's inner width; the sparkline fills it.
                        hoverIndex = min(samples.count - 1, max(0, Int((point.x / max(1, sparklineWidth)) * CGFloat(samples.count - 1) + 0.5)))
                    case .ended:
                        hoverIndex = nil
                    }
                }
                .background(GeometryReader { proxy in
                    Color.clear.onAppear { sparklineWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, width in sparklineWidth = width }
                })
        }
        .help(s.cpuHelp)
    }

    @State private var sparklineWidth: CGFloat = 1
}

/// Single-series line: de-emphasised stroke with a light wash, accent end dot, hairline crosshair on hover.
/// Built from vector shapes rather than `Canvas`, which re-rasterized into fresh GPU surfaces on every update.
struct Sparkline: View {
    let values: [Double]
    /// Minimum top of the y-scale so near-zero noise doesn't look like a spike.
    var floor: Double = 1
    var highlight: Int?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            if values.count > 1 {
                let marked = highlight ?? values.count - 1
                let point = SparklineGeometry(values: values, floor: floor).point(marked, in: size)
                ZStack(alignment: .topLeading) {
                    SparklineShape(values: values, floor: floor, closed: true)
                        .fill(Color.secondary.opacity(0.10))
                    SparklineShape(values: values, floor: floor, closed: false)
                        .stroke(Color.secondary.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    if highlight != nil {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 1, height: size.height)
                            .offset(x: point.x - 0.5)
                    }
                    Circle()
                        .fill(Color.claude)
                        .frame(width: 6, height: 6)
                        .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor).opacity(0.9), lineWidth: 1))
                        .offset(x: point.x - 3, y: point.y - 3)
                }
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(height: 1)
                    .offset(y: size.height - 1)
            }
        }
    }
}

private struct SparklineGeometry {
    let values: [Double]
    let floor: Double
    let inset: CGFloat = 3

    func point(_ index: Int, in size: CGSize) -> CGPoint {
        let top = max(values.max() ?? 0, floor) * 1.1
        return CGPoint(x: CGFloat(index) / CGFloat(max(1, values.count - 1)) * size.width,
                       y: inset + (size.height - inset * 2) * (1 - CGFloat(values[index] / top)))
    }
}

private struct SparklineShape: Shape {
    let values: [Double]
    let floor: Double
    let closed: Bool

    func path(in rect: CGRect) -> Path {
        let geometry = SparklineGeometry(values: values, floor: floor)
        var path = Path()
        guard values.count > 1 else { return path }
        path.move(to: geometry.point(0, in: rect.size))
        for index in values.indices.dropFirst() { path.addLine(to: geometry.point(index, in: rect.size)) }
        if closed {
            path.addLine(to: CGPoint(x: rect.width, y: rect.height))
            path.addLine(to: CGPoint(x: 0, y: rect.height))
            path.closeSubpath()
        }
        return path
    }
}
