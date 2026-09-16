import Foundation

public enum TitleResolver {
    /// Picks the most human-meaningful label for a session.
    /// Order: user rename → AI title → cmux auto-name → "<folder> · <short id>".
    public static func resolve(_ record: SessionRecord, aiTitle: String?) -> String {
        let name = record.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let source = record.nameSource

        if !name.isEmpty && (source == nil || source == "user") {
            return humanize(name)
        }
        if let ai = aiTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !ai.isEmpty {
            return humanize(ai)
        }
        if !name.isEmpty && source == "auto" {
            return humanize(name)
        }
        let folder = URL(fileURLWithPath: record.cwd).lastPathComponent
        return "\(folder) · \(record.sessionId.prefix(8))"
    }

    /// cmux auto-names sessions in kebab-case ("claude-deck-app-plan"); turn those into
    /// "Claude deck app plan". Anything that isn't pure kebab-case is left untouched.
    public static func humanize(_ title: String) -> String {
        let words = title.split(separator: "-", omittingEmptySubsequences: false)
        let isKebab = words.count > 1 && words.allSatisfy { word in
            !word.isEmpty && word.allSatisfy { ($0.isLowercase || $0.isNumber) && $0.isASCII }
        }
        guard isKebab else { return title }
        let sentence = words.joined(separator: " ")
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }
}
