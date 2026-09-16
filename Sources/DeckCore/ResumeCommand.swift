import Foundation

public enum ResumeCommand {
    private static let valuelessFlags: Set<String> = ["--dangerously-skip-permissions", "--allow-dangerously-skip-permissions"]
    private static let valuedFlags: Set<String> = ["--model", "--permission-mode", "--add-dir"]

    /// Extracts the launch flags worth carrying over to `claude --resume`.
    /// Everything else (`--settings`, `--resume`, `--session-id`, …) is dropped.
    public static func preservedFlags(from argv: [String]) -> [String] {
        var kept: [String] = []
        var index = argv.startIndex == argv.endIndex ? argv.endIndex : argv.index(after: argv.startIndex)
        while index < argv.endIndex {
            let arg = argv[index]
            if valuelessFlags.contains(arg) {
                kept.append(arg)
            } else if valuedFlags.contains(arg), index + 1 < argv.endIndex {
                kept.append(contentsOf: [arg, argv[index + 1]])
                index += 1
            } else if let eq = arg.firstIndex(of: "="), valuedFlags.contains(String(arg[..<eq])) {
                kept.append(arg)
            }
            index += 1
        }
        return kept
    }

    /// Flags that restore a transcript's recorded permission mode.
    public static func flags(permissionMode: String?) -> [String] {
        switch permissionMode {
        case nil, "default"?: return []
        case "bypassPermissions"?: return ["--dangerously-skip-permissions"]
        case let mode?: return ["--permission-mode", mode]
        }
    }

    public static func shellQuote(_ value: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./=:@%+,")
        if !value.isEmpty && value.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    public static func build(claudeBin: String, sessionId: String, flags: [String]) -> String {
        ([claudeBin, "--resume", sessionId] + flags).map(shellQuote).joined(separator: " ")
    }
}
