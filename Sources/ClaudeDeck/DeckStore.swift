import AppKit
import Combine
import DeckCore
import SwiftUI

enum PendingAction: Equatable {
    case closing, sleeping, waking
}

struct Confirmation: Equatable {
    enum Kind: Equatable { case close, sleepBusy }
    var id: String
    var kind: Kind
}

/// A button shown next to a banner's text.
struct BannerAction {
    var title: String
    var perform: @MainActor () -> Void
}

struct UsageTotals: Equatable {
    var memoryBytes: UInt64 = 0
    var cpuPercent: Double = 0
    var processCount: Int = 0
}

@MainActor
final class DeckStore: ObservableObject {
    @Published private(set) var sessions: [LiveSession] = []
    @Published private(set) var sleeping: [SleepingSession] = []
    @Published private(set) var recent: [RecentSession] = []
    @Published private(set) var recentLoaded = false
    @Published private(set) var pending: [String: PendingAction] = [:]
    @Published private(set) var loaded = false
    @Published private(set) var now = Date()
    @Published private(set) var totals = UsageTotals()
    @Published private(set) var history = UsageHistory(capacity: 200)
    @Published private(set) var finishedUnseen: Set<String> = []
    @Published private(set) var warnings: [String: Set<ResourceWarning>] = [:]
    @Published var expanded: Set<String> = []
    @Published var query = ""
    @Published var confirmation: Confirmation?
    @Published var bulkPlan: IdleSleepPlan?
    @Published var banner: String?
    @Published private(set) var bannerAction: BannerAction?
    @Published var showSettings = false

    let settings: AppSettings
    let notifier: Notifier
    let paths: DeckPaths
    let systemMemory = ProcessInfo.processInfo.physicalMemory
    let cpuCores = ProcessInfo.processInfo.activeProcessorCount

    private let inspector = SystemProcessInspector()
    private let transcripts = TranscriptCache()
    private let sampler = ResourceSampler()
    private let sleepStore: SleepStore
    private var finishDetector = FinishDetector()
    private var warningEvaluator = ResourceWarningEvaluator(thresholds: WarningThresholds(memoryBytes: .max, cpuPercent: .infinity, cpuSustain: 60))
    private var timer: Timer?
    private var ticks = 0
    private var directorySource: DispatchSourceFileSystemObject?
    private var debounce: DispatchWorkItem?
    private var refreshInFlight = false
    private var refreshQueued = false
    private var recentInFlight = false
    private var bannerTask: Task<Void, Never>?
    private var wakeTimeouts: [String: Task<Void, Never>] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var debugObserver: NSObjectProtocol?
    /// nil until the first focus attempt tells us whether cmux accepts our socket calls.
    private var cmuxSocketUsable: Bool?
    private var focusInFlight: Set<String> = []

    var debugSnapshot: ((String) -> Void)?
    var debugResize: ((NSSize) -> Void)?
    var debugAppearance: ((String) -> Void)?

    private var s: Strings { settings.strings }

    init(settings: AppSettings, notifier: Notifier, paths: DeckPaths = DeckPaths()) {
        self.settings = settings
        self.notifier = notifier
        self.paths = paths
        sleepStore = SleepStore(url: paths.sleepStoreURL)
        // Views read filter/sort/language from settings; re-render when they change.
        settings.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        settings.$filter.removeDuplicates().sink { [weak self] filter in
            if filter == .recent { DispatchQueue.main.async { self?.refreshRecent() } }
        }.store(in: &cancellables)
    }

    // MARK: - Lifecycle

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.ticks += 1
                self.refresh()
                if self.settings.filter == .recent, self.ticks % 10 == 0 { self.refreshRecent() }
            }
        }
        watchSessionsDirectory()
        if settings.notifyOnFinish || settings.notifyOnWarning { notifier.requestPermissionIfNeeded() }
        if ProcessInfo.processInfo.environment["CLAUDE_DECK_DEBUG"] == "1" { installDebugTrigger() }
    }

    private func watchSessionsDirectory() {
        let fd = open(paths.sessionsDir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
        directorySource = source
    }

    private func scheduleRefresh() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    func refresh() {
        guard !refreshInFlight else {
            refreshQueued = true
            return
        }
        refreshInFlight = true
        let builder = SnapshotBuilder(paths: paths, inspector: inspector, transcripts: transcripts, sampler: sampler)
        let store = sleepStore
        Task.detached(priority: .utility) { [weak self] in
            let live = builder.build()
            let asleep = store.load()
            await self?.apply(live: live, asleep: asleep)
        }
    }

    private func apply(live: [LiveSession], asleep: [SleepingSession]) {
        refreshInFlight = false
        let current = Date()
        let liveIds = Set(live.map(\.sessionId))

        // A sleeping session showing up live again has been woken (from here or elsewhere).
        for entry in asleep where liveIds.contains(entry.sessionId) && pending[entry.sessionId] != .sleeping {
            try? sleepStore.remove(sessionId: entry.sessionId)
        }
        for (id, action) in pending {
            let done = action == .waking ? liveIds.contains(id) : !liveIds.contains(id)
            if done {
                pending[id] = nil
                wakeTimeouts.removeValue(forKey: id)?.cancel()
            }
        }
        if let confirmation, !liveIds.contains(confirmation.id) { self.confirmation = nil }

        updateAlerts(live: live, now: current)

        let remaining = asleep.filter { !liveIds.contains($0.sessionId) }.sorted { $0.sleptAt > $1.sleptAt }
        if live != sessions || remaining != sleeping {
            // Animate only membership/order changes; plain field updates (status, time, usage) just re-render.
            let membershipChanged = Set(live.map(\.sessionId)) != Set(sessions.map(\.sessionId))
                || remaining.map(\.sessionId) != sleeping.map(\.sessionId)
            withAnimation(membershipChanged ? .easeInOut(duration: 0.2) : nil) {
                sessions = live
                sleeping = remaining
            }
            if membershipChanged && settings.filter == .recent { refreshRecent() }
        }

        let newTotals = live.compactMap(\.usage).reduce(into: UsageTotals()) { totals, usage in
            totals.memoryBytes += usage.memoryBytes
            totals.cpuPercent += usage.cpuPercent
            totals.processCount += usage.processCount
        }
        if newTotals != totals { totals = newTotals }
        history.append(UsageSample(at: current, memoryBytes: newTotals.memoryBytes, cpuPercent: newTotals.cpuPercent))
        if current.timeIntervalSince(now) >= 30 { now = current }
        if !loaded { loaded = true }

        if refreshQueued {
            refreshQueued = false
            refresh()
        }
    }

    private func updateAlerts(live: [LiveSession], now: Date) {
        finishDetector.minimumBusy = TimeInterval(settings.minimumBusySeconds)
        let finished = finishDetector.update(live, now: now)
        var unseen = finishedUnseen.filter { id in live.contains { $0.sessionId == id && !$0.isWorking } }
        for turn in finished {
            unseen.insert(turn.sessionId)
            if settings.notifyOnFinish {
                notifier.post(identifier: "finished-\(turn.sessionId)-\(Int(now.timeIntervalSince1970))",
                              title: s.finishedTitle, body: s.finishedBody(title: turn.session.title, worked: turn.worked),
                              sessionId: turn.sessionId, sound: settings.notificationSound)
            }
        }
        if unseen != finishedUnseen { finishedUnseen = unseen }
        // Without notification permission, still make a finished turn noticeable.
        if !finished.isEmpty, settings.notifyOnFinish, settings.notificationSound, notifier.permission == .denied {
            NSSound(named: "Glass")?.play()
        }

        guard settings.warningsEnabled else {
            if !warnings.isEmpty { warnings = [:] }
            return
        }
        warningEvaluator.thresholds = settings.warningThresholds
        let result = warningEvaluator.update(live, now: now)
        if result.active != warnings { warnings = result.active }
        if settings.notifyOnWarning {
            for raised in result.raised {
                notifier.post(identifier: "warning-\(raised.session.sessionId)-\(raised.warning.rawValue)-\(Int(now.timeIntervalSince1970))",
                              title: s.warningTitle(raised.warning), body: warningText(raised.session, raised.warning),
                              sessionId: raised.session.sessionId, sound: settings.notificationSound)
            }
        }
    }

    func refreshRecent() {
        guard !recentInFlight else { return }
        recentInFlight = true
        let scanner = RecentSessionsScanner(projectsDir: paths.projectsDir, transcripts: transcripts)
        let excluded = Set(sessions.map(\.sessionId)).union(sleeping.map(\.sessionId))
        Task.detached(priority: .utility) { [weak self] in
            let found = scanner.scan(excluding: excluded)
            await self?.applyRecent(found)
        }
    }

    private func applyRecent(_ found: [RecentSession]) {
        recentInFlight = false
        if found != recent {
            withAnimation(.easeInOut(duration: 0.2)) { recent = found }
        }
        recentLoaded = true
    }

    // MARK: - Derived state

    var busyCount: Int { sessions.filter(\.isWorking).count }
    var idleCount: Int { sessions.filter { !$0.isWorking }.count }

    func count(for filter: SessionFilter) -> Int? {
        switch filter {
        case .all: return sessions.count + sleeping.count
        case .busy: return busyCount
        case .idle: return idleCount
        case .sleeping: return sleeping.count
        case .recent: return nil
        }
    }

    var visibleSessions: [LiveSession] {
        let filter = settings.filter
        guard filter == .all || filter == .busy || filter == .idle else { return [] }
        let matching = sessions.filter { session in
            let passesFilter: Bool
            switch filter {
            case .busy: passesFilter = session.isWorking
            case .idle: passesFilter = !session.isWorking
            default: passesFilter = true
            }
            return passesFilter && matchesQuery(session.title, session.cwd, session.lastPrompt ?? "")
        }
        return SessionSorter.sorted(matching, by: settings.sort, pinned: settings.pinned)
    }

    var visibleSleeping: [SleepingSession] {
        guard settings.filter == .all || settings.filter == .sleeping else { return [] }
        return sleeping.filter { matchesQuery($0.title, $0.cwd) }
    }

    var visibleRecent: [RecentSession] {
        guard settings.filter == .recent else { return [] }
        let hidden = Set(sessions.map(\.sessionId)).union(sleeping.map(\.sessionId))
        return recent.filter { !hidden.contains($0.sessionId) && matchesQuery($0.title, $0.cwd, $0.lastPrompt ?? "") }
    }

    private func matchesQuery(_ fields: String...) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return true }
        return fields.contains { $0.localizedStandardContains(needle) }
    }

    func session(_ id: String) -> LiveSession? { sessions.first { $0.sessionId == id } }

    func idleSleepPlan(threshold: TimeInterval) -> IdleSleepPlan {
        IdleSleepPlanner.plan(sessions.filter { pending[$0.sessionId] == nil }, idleLongerThan: threshold, pinned: settings.pinned)
    }

    func warningText(_ session: LiveSession, _ warning: ResourceWarning) -> String {
        let thresholds = settings.warningThresholds
        switch warning {
        case .memory: return s.memoryWarning(used: session.usage?.memoryBytes ?? 0, limit: thresholds.memoryBytes)
        case .cpu: return s.cpuWarning(used: session.usage?.cpuPercent ?? 0, limit: thresholds.cpuPercent)
        }
    }

    // MARK: - Row actions

    func markSeen(_ id: String) {
        if finishedUnseen.contains(id) { finishedUnseen.remove(id) }
    }

    func toggleExpanded(_ id: String) {
        withAnimation(.easeInOut(duration: 0.18)) {
            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        }
    }

    func togglePin(_ id: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if settings.pinned.contains(id) { settings.pinned.remove(id) } else { settings.pinned.insert(id) }
        }
    }

    func requestClose(_ id: String) {
        withAnimation(.easeOut(duration: 0.15)) { confirmation = Confirmation(id: id, kind: .close) }
    }

    func requestSleep(_ id: String) {
        guard let session = session(id) else { return }
        if session.activity == .busy {
            withAnimation(.easeOut(duration: 0.15)) { confirmation = Confirmation(id: id, kind: .sleepBusy) }
        } else {
            sleep(id)
        }
    }

    func cancelConfirmation() {
        withAnimation(.easeOut(duration: 0.15)) { confirmation = nil }
    }

    func confirm() {
        guard let confirmation else { return }
        cancelConfirmation()
        switch confirmation.kind {
        case .close: close(confirmation.id)
        case .sleepBusy: sleep(confirmation.id)
        }
    }

    func close(_ id: String) {
        guard let session = session(id), pending[id] == nil else { return }
        pending[id] = .closing
        Task {
            if await !terminate(session) {
                pending[id] = nil
                showBanner(s.couldNotClose(pid: session.pid))
            }
            refresh()
        }
    }

    func sleep(_ id: String) {
        guard let session = session(id), pending[id] == nil else { return }
        Task {
            if await !performSleep(session) { showBanner(s.couldNotSleep(pid: session.pid)) }
            refresh()
        }
    }

    /// Records the session for resuming, then ends it. Returns false (and drops the record) on failure.
    private func performSleep(_ session: LiveSession) async -> Bool {
        let id = session.sessionId
        let cmuxEnv = session.cmuxEnv
        let entry = SleepingSession(
            sessionId: id, cwd: session.cwd, title: session.title, flags: session.flags,
            sleptAt: Date(), cmuxEnv: cmuxEnv.isEmpty ? nil : cmuxEnv, hostBundleID: session.host.bundleID
        )
        do {
            try sleepStore.upsert(entry)
        } catch {
            showBanner(s.sleepRecordFailed(error))
            return false
        }
        pending[id] = .sleeping
        guard await terminate(session) else {
            try? sleepStore.remove(sessionId: id)
            pending[id] = nil
            return false
        }
        return true
    }

    func requestBulkSleep(threshold: TimeInterval) {
        let plan = idleSleepPlan(threshold: threshold)
        guard !plan.sessions.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.15)) { bulkPlan = plan }
    }

    func cancelBulkSleep() {
        withAnimation(.easeOut(duration: 0.15)) { bulkPlan = nil }
    }

    func confirmBulkSleep() {
        guard let plan = bulkPlan else { return }
        cancelBulkSleep()
        // Re-plan so sessions that started working since the menu opened are spared.
        let fresh = idleSleepPlan(threshold: plan.threshold)
        Task {
            var slept = 0
            var freed: UInt64 = 0
            await withTaskGroup(of: (Bool, UInt64).self) { group in
                for session in fresh.sessions {
                    group.addTask { @MainActor in (await self.performSleep(session), session.usage?.memoryBytes ?? 0) }
                }
                for await (ok, memory) in group where ok {
                    slept += 1
                    freed += memory
                }
            }
            showBanner(s.bulkDone(slept, freed))
            refresh()
        }
    }

    func wake(_ id: String) {
        guard let entry = sleeping.first(where: { $0.sessionId == id }) else { return }
        resume(sessionId: entry.sessionId, cwd: entry.cwd, title: entry.title, flags: entry.flags,
               hostBundleID: entry.resumeHostBundleID ?? dominantHostBundleID)
    }

    func resumeRecent(_ id: String) {
        guard let entry = recent.first(where: { $0.sessionId == id }) else { return }
        resume(sessionId: entry.sessionId, cwd: entry.cwd, title: entry.title, flags: entry.flags,
               hostBundleID: dominantHostBundleID)
    }

    /// The terminal most running sessions live in: for sessions with no recorded host (Recent, older
    /// sleep records) a better "Auto" guess than the system's default app for `.command` files.
    private var dominantHostBundleID: String? {
        var counts: [String: Int] = [:]
        for session in sessions where session.host.kind.canResume {
            if let bundleID = session.host.bundleID { counts[bundleID, default: 0] += 1 }
        }
        return counts.max { $0.value < $1.value }?.key
    }

    /// Opens `claude --resume` in the chosen terminal ("auto": where the session last ran).
    private func resume(sessionId id: String, cwd: String, title: String, flags: [String], hostBundleID: String?) {
        guard pending[id] == nil else { return }
        guard FileManager.default.fileExists(atPath: cwd) else {
            showBanner(s.folderMissing(cwd))
            return
        }
        let target: ResumeTarget
        if let kind = settings.resumeTerminalKind {
            guard let url = TerminalApps.url(for: kind) else {
                showBanner(kind == .cmux ? s.cmuxMissing : s.terminalNotInstalled(kind.displayName))
                return
            }
            target = ResumeTarget(kind: kind, appURL: url)
        } else {
            target = TerminalApps.autoTarget(hostBundleID: hostBundleID)
        }
        if target.kind == .warp && settings.warpPasteFallback {
            pasteResumeIntoWarp(sessionId: id, cwd: cwd, flags: flags)
            return
        }

        let cmuxPath = target.kind == .cmux ? cmuxCLI(in: target.appURL) : nil
        let script = Scripts.resume(title: title, cwd: cwd, claudeBin: paths.claudeBin, sessionId: id, flags: flags,
                                    cmuxPath: cmuxPath)
        let executor = ResumeExecutor(launcher: ScriptLauncher(appURL: target.appURL, scriptsDir: paths.scriptsDir))
        let shell = ResumePlanner.defaultShell()

        pending[id] = .waking
        Task {
            let outcome = await Task.detached {
                executor.run(script: script, kind: target.kind, cwd: cwd, shell: shell)
            }.value
            switch outcome {
            case .launched:
                startWakeTimeout(id)
            case .automationDenied(let launched):
                if launched { startWakeTimeout(id) } else { pending[id] = nil }
                showAutomationDenied(appName: target.kind.displayName)
            case .failed(let detail):
                pending[id] = nil
                if target.kind == .warp {
                    pasteResumeIntoWarp(sessionId: id, cwd: cwd, flags: flags)
                } else {
                    showBanner(s.couldNotOpen(detail))
                }
            }
        }
    }

    private func startWakeTimeout(_ id: String) {
        wakeTimeouts[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard let self, !Task.isCancelled, self.pending[id] == .waking else { return }
            self.pending[id] = nil
            self.showBanner(self.s.notYetVisible)
        }
    }

    /// Warp fallback: open a new Warp tab in the folder and put the resume command on the pasteboard.
    private func pasteResumeIntoWarp(sessionId id: String, cwd: String, flags: [String]) {
        let command = WarpFallback.command(cwd: cwd, claudeBin: paths.claudeBin, sessionId: id, flags: flags)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        if let url = WarpFallback.newTabURL(cwd: cwd) { NSWorkspace.shared.open(url) }
        showBanner(s.warpPasteHint, duration: 8)
    }

    /// cmux's CLI: the one found at launch, else the copy inside the app bundle.
    private func cmuxCLI(in app: URL) -> String? {
        if let path = settings.cmuxPath { return path }
        let bundled = app.appendingPathComponent("Contents/Resources/bin/cmux").path
        return FileManager.default.isExecutableFile(atPath: bundled) ? bundled : nil
    }

    func forget(_ id: String) {
        try? sleepStore.remove(sessionId: id)
        withAnimation(.easeInOut(duration: 0.2)) { sleeping.removeAll { $0.sessionId == id } }
    }

    /// Jumps to the session's terminal tab: cmux workspace, tmux pane, Terminal / iTerm2 tab by tty,
    /// Ghostty terminal, kitty window or WezTerm pane; other hosts just come to the front.
    func focus(_ id: String) {
        guard let session = session(id) else { return }
        markSeen(id)
        // A jump can wait up to a minute on the Automation prompt; ignore repeat clicks meanwhile.
        guard focusInFlight.insert(id).inserted else { return }
        let host = session.host
        let env = session.terminalEnv
        let cwd = session.cwd
        let executor = FocusExecutor(inspector: inspector, appPathForBundleID: { TerminalApps.url(forBundleID: $0)?.path })
        Task {
            let result = await Task.detached { executor.run(host: host, env: env, cwd: cwd) }.value
            focusInFlight.remove(id)
            if let target = result.activate { TerminalApps.activate(target) }
            let name = s.terminalName(result.activate ?? host)
            switch result.outcome {
            case .focused, .activated:
                break
            case .notFound:
                showBanner(s.tabNotFound(name))
            case .automationDenied:
                showAutomationDenied(appName: name)
            case .cmux(let workspace):
                focusCmux(workspaceId: workspace)
            case .noTmuxClient(let command):
                copy(command, message: s.tmuxNoClient)
            case .unknownHost:
                showBanner(s.hostUnknown)
            }
        }
    }

    /// Selects a cmux workspace: directly over the socket when cmux allows it, otherwise through
    /// a throwaway workspace script (cmux's default `cmuxOnly` socket mode).
    private func focusCmux(workspaceId workspace: String) {
        guard let app = settings.cmuxPath.flatMap(CmuxFocus.appBundle(containing:)) ?? TerminalApps.url(for: .cmux) else {
            showBanner(s.cmuxMissing)
            return
        }
        guard let cmux = cmuxCLI(in: app) else {
            activate(appAt: app)
            return
        }
        let arguments = ["workspace", "select", workspace]
        let scriptsDir = paths.scriptsDir
        let trySocket = cmuxSocketUsable != false
        Task {
            if trySocket {
                let result = try? await Task.detached { try ProcessRunner(timeout: 3).run(cmux, arguments) }.value
                if result?.status == 0 {
                    cmuxSocketUsable = true
                    activate(appAt: app)
                    return
                }
                cmuxSocketUsable = false
            }
            do {
                let script = Scripts.cmuxFocus(workspaceId: workspace, cmuxPath: cmux)
                _ = try await Task.detached {
                    try ScriptLauncher(appURL: app, scriptsDir: scriptsDir).open(script: script)
                }.value
            } catch {
                showBanner(s.focusFailed(error))
            }
        }
    }

    func copyResumeCommand(sessionId: String, cwd: String, flags: [String]) {
        let command = "cd \(ResumeCommand.shellQuote(cwd)) && " + ResumeCommand.build(claudeBin: "claude", sessionId: sessionId, flags: flags)
        copy(command, message: s.copiedResume)
    }

    func copy(_ text: String, message: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showBanner(message)
    }

    func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func showBanner(_ text: String, action: BannerAction? = nil, duration: TimeInterval = 4) {
        bannerTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            banner = text
            bannerAction = action
        }
        bannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) {
                self?.banner = nil
                self?.bannerAction = nil
            }
        }
    }

    /// macOS refused the Apple Events ClaudeDeck needs to drive `appName`.
    private func showAutomationDenied(appName: String) {
        let action = BannerAction(title: s.openAutomationSettings) {
            NSWorkspace.shared.open(AppleScript.automationSettingsURL)
        }
        showBanner(s.automationDenied(appName), action: action, duration: 12)
    }

    // MARK: - Helpers

    /// Kills the session tree after re-checking the pid still belongs to a Claude process.
    /// (cmux closes the tab by itself once the tab's root process exits.)
    private func terminate(_ session: LiveSession) async -> Bool {
        let inspector = inspector
        guard let args = inspector.args(session.pid),
              ([args.argv.first ?? "", args.executablePath]).contains(where: { $0.lowercased().contains("claude") })
        else { return !inspector.isAlive(session.pid) }

        return await SessionKiller(inspector: inspector, signaler: SystemSignaler()).terminate(pid: session.pid)
    }

    private func activate(appAt url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    /// Dev-only: `CLAUDE_DECK_DEBUG=1` lets scripts/debug-action.swift drive the same actions the UI uses.
    private func installDebugTrigger() {
        debugObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("io.github.yentur.ClaudeDeck.debug"), object: nil, queue: .main
        ) { [weak self] note in
            let action = note.userInfo?["action"] as? String ?? ""
            let value = note.userInfo?["value"] as? String ?? ""
            MainActor.assumeIsolated { self?.handleDebug(action: action, value: value) }
        }
    }

    private func handleDebug(action: String, value: String) {
        switch action {
        case "sleep": sleep(value)
        case "close": close(value)
        case "wake": wake(value)
        case "resume-recent": resumeRecent(value)
        case "focus": focus(value)
        case "forget": forget(value)
        case "request-close": requestClose(value)
        case "request-sleep": requestSleep(value)
        case "expand": toggleExpanded(value)
        case "pin": togglePin(value)
        case "bulk": requestBulkSleep(threshold: TimeInterval(value) ?? 86_400)
        case "bulk-confirm": confirmBulkSleep()
        case "settings": showSettings = value == "on"
        case "compact": settings.compact = value == "on"
        case "usage": settings.showUsagePanel = value == "on"
        case "filter": settings.filter = SessionFilter(rawValue: value) ?? .all
        case "sort": settings.sort = SessionSort(rawValue: value) ?? .activity
        case "language": settings.language = DeckLanguage(rawValue: value) ?? .en
        case "query": query = value
        case "terminal":
            if value == AppSettings.autoTerminal || TerminalKind(rawValue: value)?.canResume == true { settings.resumeTerminal = value }
        case "warp-paste": settings.warpPasteFallback = value == "on"
        case "min-busy": settings.minimumBusySeconds = Int(value) ?? 20
        case "memory-limit": settings.memoryLimitGB = Double(value) ?? 2
        case "banner": showBanner(value)
        case "permission":
            notifier.refreshPermission()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showBanner("notifications: \(self.notifier.permission)") }
        case "snapshot": debugSnapshot?(value)
        case "appearance": debugAppearance?(value)
        case "resize":
            let parts = value.split(separator: "x").compactMap { Double($0) }
            if parts.count == 2 { debugResize?(NSSize(width: parts[0], height: parts[1])) }
        default: showBanner("Unknown debug action: \(action)")
        }
    }
}
