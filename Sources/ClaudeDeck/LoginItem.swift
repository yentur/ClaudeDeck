import DeckCore
import Foundation

/// "Launch at login" through a per-user LaunchAgent (works for an ad-hoc signed app).
enum LoginItem {
    static let label = "io.github.yentur.ClaudeDeck"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// Refused while the app runs from an App Translocation path: that path is temporary,
    /// so a login item pointing at it would silently stop working.
    struct TranslocatedError: LocalizedError {
        let language: DeckLanguage
        var errorDescription: String? { Strings(language: language).moveToApplications }
    }

    static func setEnabled(_ enabled: Bool, language: DeckLanguage = .en) throws {
        if !enabled {
            if isEnabled { try FileManager.default.removeItem(at: plistURL) }
            return
        }
        guard !AppInfo.isTranslocated else { throw TranslocatedError(language: language) }
        guard let executable = Bundle.main.executablePath else { return }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: plistURL, options: .atomic)
    }
}
