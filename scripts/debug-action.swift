// Sends a debug action to a ClaudeDeck instance started with CLAUDE_DECK_DEBUG=1.
// Usage: swift scripts/debug-action.swift <action> [value]
import Foundation

let args = CommandLine.arguments.dropFirst()
guard let action = args.first else {
    print("usage: debug-action.swift <action> [value]")
    exit(1)
}
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("io.github.yentur.ClaudeDeck.debug"), object: nil,
    userInfo: ["action": action, "value": args.dropFirst().first ?? ""], deliverImmediately: true)
// Give the notification time to leave the process.
RunLoop.current.run(until: Date().addingTimeInterval(0.2))
