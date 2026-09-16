import AppKit
import Combine
import DeckCore

enum SessionFilter: String, CaseIterable, Identifiable {
    case all, busy, idle, sleeping, recent
    var id: String { rawValue }
}

/// User preferences, persisted in UserDefaults. `CLAUDE_DECK_DEFAULTS_SUITE` isolates dev runs.
@MainActor
final class AppSettings: ObservableObject {
    static let opacityRange: ClosedRange<Double> = 0.35...1.0
    static let minimumBusyChoices = [10, 20, 30, 60, 120, 300]
    static let memoryLimitChoicesGB: [Double] = [0.5, 1, 1.5, 2, 3, 4, 6, 8]
    static let cpuLimitChoices: [Double] = [50, 80, 100, 150, 200, 400]
    static let idleSleepThresholds: [TimeInterval] = [3600, 6 * 3600, 24 * 3600, 3 * 86_400]

    private let defaults: UserDefaults

    @Published var language: DeckLanguage { didSet { defaults.set(language.rawValue, forKey: "language") } }
    @Published var opacity: Double { didSet { defaults.set(opacity, forKey: "opacity") } }
    @Published var hoverOpaque: Bool { didSet { defaults.set(hoverOpaque, forKey: "hoverOpaque") } }
    @Published var alwaysOnTop: Bool { didSet { defaults.set(alwaysOnTop, forKey: "alwaysOnTop") } }
    @Published var compact: Bool { didSet { defaults.set(compact, forKey: "compact") } }
    @Published var showUsagePanel: Bool { didSet { defaults.set(showUsagePanel, forKey: "showUsagePanel") } }
    @Published var menuBarMemory: Bool { didSet { defaults.set(menuBarMemory, forKey: "menuBarMemory") } }
    /// `autoTerminal` or a `TerminalKind` raw value. Stored under the key older builds used for
    /// their cmux / Terminal choice, whose values ("cmux", "terminalApp") remain valid.
    @Published var resumeTerminal: String { didSet { defaults.set(resumeTerminal, forKey: "terminal") } }
    @Published var filter: SessionFilter { didSet { defaults.set(filter.rawValue, forKey: "filter") } }
    @Published var sort: SessionSort { didSet { defaults.set(sort.rawValue, forKey: "sort") } }
    @Published var pinned: Set<String> { didSet { defaults.set(Array(pinned), forKey: "pinned") } }
    @Published var notifyOnFinish: Bool { didSet { defaults.set(notifyOnFinish, forKey: "notifyOnFinish") } }
    @Published var minimumBusySeconds: Int { didSet { defaults.set(minimumBusySeconds, forKey: "minimumBusySeconds") } }
    @Published var notificationSound: Bool { didSet { defaults.set(notificationSound, forKey: "notificationSound") } }
    @Published var warningsEnabled: Bool { didSet { defaults.set(warningsEnabled, forKey: "warningsEnabled") } }
    @Published var memoryLimitGB: Double { didSet { defaults.set(memoryLimitGB, forKey: "memoryLimitGB") } }
    @Published var cpuLimitPercent: Double { didSet { defaults.set(cpuLimitPercent, forKey: "cpuLimitPercent") } }
    @Published var notifyOnWarning: Bool { didSet { defaults.set(notifyOnWarning, forKey: "notifyOnWarning") } }
    var frame: String? {
        get { defaults.string(forKey: "frame") }
        set { defaults.set(newValue, forKey: "frame") }
    }

    let cmuxPath: String?
    /// Resumable terminals found on this Mac (refreshed when Settings opens).
    @Published private(set) var installedTerminals: [TerminalKind] = []

    static let autoTerminal = "auto"

    /// The explicitly chosen terminal; nil means "auto".
    var resumeTerminalKind: TerminalKind? { TerminalKind(rawValue: resumeTerminal) }

    /// Hidden (`defaults write … warpPasteFallback -bool true`): resume Warp sessions by opening a
    /// tab in the folder and copying the command, instead of handing Warp the script.
    var warpPasteFallback: Bool {
        get { defaults.bool(forKey: "warpPasteFallback") }
        set { defaults.set(newValue, forKey: "warpPasteFallback") }
    }

    func refreshInstalledTerminals() {
        let found = TerminalApps.installedResumable()
        if found != installedTerminals { installedTerminals = found }
    }

    var strings: Strings { Strings(language: language) }

    var warningThresholds: WarningThresholds {
        WarningThresholds(memoryBytes: UInt64(memoryLimitGB * 1_073_741_824), cpuPercent: cpuLimitPercent, cpuSustain: 60)
    }

    init(env: [String: String] = ProcessInfo.processInfo.environment) {
        defaults = env["CLAUDE_DECK_DEFAULTS_SUITE"].flatMap { UserDefaults(suiteName: $0) } ?? .standard
        cmuxPath = CmuxFocus.locate()
        defaults.register(defaults: [
            "opacity": 0.88,
            "hoverOpaque": true,
            "alwaysOnTop": true,
            "compact": false,
            "showUsagePanel": true,
            "menuBarMemory": false,
            "notifyOnFinish": true,
            "minimumBusySeconds": 20,
            "notificationSound": true,
            "warningsEnabled": true,
            "memoryLimitGB": 2.0,
            "cpuLimitPercent": 100.0,
            "notifyOnWarning": false,
        ])
        language = defaults.string(forKey: "language").flatMap(DeckLanguage.init(rawValue:)) ?? .en
        opacity = min(max(defaults.double(forKey: "opacity"), Self.opacityRange.lowerBound), Self.opacityRange.upperBound)
        hoverOpaque = defaults.bool(forKey: "hoverOpaque")
        alwaysOnTop = defaults.bool(forKey: "alwaysOnTop")
        compact = defaults.bool(forKey: "compact")
        showUsagePanel = defaults.bool(forKey: "showUsagePanel")
        menuBarMemory = defaults.bool(forKey: "menuBarMemory")
        let storedTerminal = defaults.string(forKey: "terminal").flatMap(TerminalKind.init(rawValue:))
        resumeTerminal = storedTerminal.flatMap { $0.canResume ? $0.rawValue : nil } ?? Self.autoTerminal
        filter = defaults.string(forKey: "filter").flatMap(SessionFilter.init(rawValue:)) ?? .all
        sort = defaults.string(forKey: "sort").flatMap(SessionSort.init(rawValue:)) ?? .activity
        pinned = Set(defaults.stringArray(forKey: "pinned") ?? [])
        notifyOnFinish = defaults.bool(forKey: "notifyOnFinish")
        minimumBusySeconds = defaults.integer(forKey: "minimumBusySeconds")
        notificationSound = defaults.bool(forKey: "notificationSound")
        warningsEnabled = defaults.bool(forKey: "warningsEnabled")
        memoryLimitGB = defaults.double(forKey: "memoryLimitGB")
        cpuLimitPercent = defaults.double(forKey: "cpuLimitPercent")
        notifyOnWarning = defaults.bool(forKey: "notifyOnWarning")
        installedTerminals = TerminalApps.installedResumable()
    }
}
