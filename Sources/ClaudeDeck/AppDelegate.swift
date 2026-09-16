import AppKit
import Combine
import DeckCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: AppSettings!
    private var store: DeckStore!
    private var notifier: Notifier!
    private var panel: PanelController!
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let env = ProcessInfo.processInfo.environment
        if env["CLAUDE_DECK_DEFAULTS_SUITE"] == nil, anotherInstanceIsRunning() {
            NSApp.terminate(nil)
            return
        }

        LegacyMigration.run()
        settings = AppSettings()
        notifier = Notifier()
        store = DeckStore(settings: settings, notifier: notifier)
        panel = PanelController(settings: settings)
        panel.install(rootView: DeckRootView()
            .environmentObject(store)
            .environmentObject(settings)
            .environmentObject(panel)
            .environmentObject(notifier))

        notifier.onOpenSession = { [weak self] sessionId in
            guard let self else { return }
            self.panel.show()
            self.store.focus(sessionId)
        }
        notifier.start()

        store.debugSnapshot = { [weak self] path in
            guard let self else { return }
            let dark = self.panel.panel.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            self.panel.writeSnapshot(to: path, dark: dark)
        }
        store.debugResize = { [weak self] size in self?.panel.resize(to: size) }
        store.debugAppearance = { [weak self] name in
            self?.panel.panel.appearance = name == "light" ? NSAppearance(named: .aqua)
                : name == "dark" ? NSAppearance(named: .darkAqua) : nil
        }

        setUpStatusItem()
        hotKey = HotKey.optionCommandK { [weak self] in self?.panel.toggle() }

        store.start()
        panel.show()
        if AppInfo.isTranslocated { store.showBanner(settings.strings.moveToApplications) }
    }

    private func anotherInstanceIsRunning() -> Bool {
        guard let bundleId = Bundle.main.bundleIdentifier else { return false }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .contains { $0.processIdentifier != getpid() }
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "ClaudeDeck")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        Publishers.CombineLatest4(store.$sessions, store.$totals, store.$finishedUnseen,
                                  settings.$menuBarMemory.combineLatest(settings.$language))
            .map { sessions, totals, finished, options -> String in
                let (showMemory, language) = options
                var parts: [String] = []
                let busy = sessions.filter { $0.activity == .busy }.count
                if busy > 0 { parts.append("\(busy)") }
                if showMemory { parts.append(Fmt.bytes(totals.memoryBytes, language)) }
                if !finished.isEmpty { parts.append("✓\(finished.count)") }
                return parts.isEmpty ? "" : " " + parts.joined(separator: " · ")
            }
            .removeDuplicates()
            .sink { [weak self] title in self?.statusItem.button?.title = title }
            .store(in: &cancellables)
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            statusItem.menu = makeMenu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            panel.toggle()
        }
    }

    private func makeMenu() -> NSMenu {
        let s = settings.strings
        let menu = NSMenu()
        menu.addItem(item(panel.isVisible ? s.hideCard : s.showCard, #selector(togglePanel), key: "k", modifiers: [.command, .option]))
        menu.addItem(item(s.snapTopRightMenu, #selector(pinPanel)))
        menu.addItem(item(s.settingsMenu, #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item(s.refresh, #selector(refreshNow), key: "r"))
        menu.addItem(.separator())
        menu.addItem(item(s.githubMenu, #selector(openGitHub)))
        menu.addItem(item(s.checkForUpdatesMenu, #selector(checkForUpdates)))
        menu.addItem(.separator())
        menu.addItem(item(s.quitMenu, #selector(quit), key: "q"))
        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        return item
    }

    @objc private func togglePanel() { panel.toggle() }
    @objc private func pinPanel() { panel.show(); panel.pinTopRight() }
    @objc private func refreshNow() { store.refresh() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func openGitHub() { AppInfo.open(AppInfo.repositoryURL) }
    /// Opens the latest release page in the browser; ClaudeDeck itself never checks the network.
    @objc private func checkForUpdates() { AppInfo.open(AppInfo.latestReleaseURL) }

    @objc private func openSettings() {
        store.showSettings = true
        panel.show()
    }
}
