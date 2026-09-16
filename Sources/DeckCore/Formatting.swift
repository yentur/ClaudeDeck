import Foundation

public enum DeckLanguage: String, CaseIterable, Identifiable, Sendable {
    case en, tr
    public var id: String { rawValue }
}

/// Compact display formatting for the card. English is the default.
public enum Fmt {
    public static func relative(_ date: Date, now: Date = Date(), _ language: DeckLanguage = .en) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        let tr = language == .tr
        switch seconds {
        case ..<60: return tr ? "şimdi" : "now"
        case ..<3600: return tr ? "\(seconds / 60) dk" : "\(seconds / 60)m"
        case ..<86_400: return tr ? "\(seconds / 3600) sa" : "\(seconds / 3600)h"
        default: return tr ? "\(seconds / 86_400) g" : "\(seconds / 86_400)d"
        }
    }

    public static func bytes(_ value: UInt64, _ language: DeckLanguage = .en) -> String {
        let mb = Double(value) / 1_048_576
        if value > 0 && mb < 1 { return "<1 MB" }
        if mb < 1024 { return "\(Int(mb)) MB" }
        let gb = (mb / 1024 * 10).rounded() / 10
        let number = gb == gb.rounded() ? String(Int(gb)) : decimal(String(format: "%.1f", gb), language)
        return number + " GB"
    }

    /// Activity Monitor style CPU percent: one decimal below 10 %, whole numbers above.
    public static func percent(_ value: Double, _ language: DeckLanguage = .en) -> String {
        let number = value < 10 ? decimal(String(format: "%.1f", (value * 10).rounded() / 10), language) : "\(Int(value.rounded()))"
        return language == .tr ? "%\(number)" : "\(number)%"
    }

    public static func duration(_ seconds: TimeInterval, _ language: DeckLanguage = .en) -> String {
        let total = Int(seconds)
        let (d, h, m) = (total / 86_400, total % 86_400 / 3600, total % 3600 / 60)
        let tr = language == .tr
        let (dayUnit, hourUnit, minuteUnit) = tr ? ("g", "sa", "dk") : ("d", "h", "m")
        if d > 0 { return "\(d)\(dayUnit) \(h)\(hourUnit)" }
        if h > 0 { return "\(h)\(hourUnit) \(m)\(minuteUnit)" }
        if m > 0 { return "\(m)\(minuteUnit)" }
        return "<1\(minuteUnit)"
    }

    public static func shortPath(_ path: String, home: String = NSHomeDirectory()) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            let parts = path.dropFirst(home.count + 1).split(separator: "/")
            return parts.count > 2 ? "~/…/" + parts.suffix(2).joined(separator: "/") : "~/" + parts.joined(separator: "/")
        }
        let parts = path.split(separator: "/")
        return parts.count > 3 ? "…/" + parts.suffix(2).joined(separator: "/") : path
    }

    private static func decimal(_ number: String, _ language: DeckLanguage) -> String {
        language == .tr ? number.replacingOccurrences(of: ".", with: ",") : number
    }
}
