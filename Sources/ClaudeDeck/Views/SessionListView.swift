import DeckCore
import SwiftUI

struct SessionListView: View {
    @EnvironmentObject var store: DeckStore
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        let live = store.visibleSessions
        let asleep = store.visibleSleeping
        let recent = store.visibleRecent

        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(live) { session in
                    SessionRowView(session: session)
                        .id("live-" + session.sessionId)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
                if !asleep.isEmpty {
                    if settings.filter == .all {
                        SectionLabel(title: settings.strings.asleepSection, count: asleep.count)
                    }
                    ForEach(asleep) { entry in
                        SleepingRowView(entry: entry)
                            .id("sleeping-" + entry.sessionId)
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                }
                ForEach(recent) { entry in
                    RecentRowView(entry: entry)
                        .id("recent-" + entry.sessionId)
                        .transition(.opacity)
                }
                if live.isEmpty && asleep.isEmpty && recent.isEmpty {
                    EmptyStateView()
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .padding(.bottom, 18)
        }
        .scrollIndicators(.automatic)
    }
}

private struct SectionLabel: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 9.5, weight: .bold)).tracking(0.8)
            Text(verbatim: "\(count)").font(.system(size: 9.5, weight: .bold).monospacedDigit())
            Rectangle().fill(Color.wash(0.1)).frame(height: 0.5)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}

private struct EmptyStateView: View {
    @EnvironmentObject var store: DeckStore
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        let s = settings.strings
        let loading = settings.filter == .recent ? !store.recentLoaded : !store.loaded
        VStack(spacing: 8) {
            if loading {
                ProgressView().controlSize(.small)
                if settings.filter == .recent {
                    Text(s.loadingRecent).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: settings.filter == .sleeping ? "moon.zzz" : settings.filter == .recent ? "clock" : "sparkles")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.secondary)
                Text(s.empty(settings.filter, query: store.query)).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

// MARK: - Live session row

struct SessionRowView: View {
    let session: LiveSession
    @EnvironmentObject var store: DeckStore
    @EnvironmentObject var settings: AppSettings
    @State private var hovering = false

    private var isSDK: Bool {
        guard let entrypoint = session.entrypoint else { return false }
        return entrypoint != "cli"
    }

    var body: some View {
        let s = settings.strings
        let language = settings.language
        let pending = store.pending[session.sessionId]
        let confirmation = store.confirmation?.id == session.sessionId ? store.confirmation : nil
        let pinned = settings.pinned.contains(session.sessionId)
        let expanded = store.expanded.contains(session.sessionId)
        let finished = store.finishedUnseen.contains(session.sessionId)
        let warnings = store.warnings[session.sessionId] ?? []

        VStack(spacing: 0) {
            HStack(spacing: 9) {
                StatusDot(activity: session.activity, label: s.activity(session.activity))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        if pinned {
                            Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(.secondary)
                        }
                        Text(session.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if isSDK { Badge(text: "SDK") }
                        if finished { DonePill(text: s.done).help(s.doneHelp) }
                    }
                    if !settings.compact {
                        Text(meta(language))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 4)

                if let pending {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.mini)
                        Text(s.pending(pending)).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                } else if hovering {
                    HStack(spacing: 0) {
                        IconButton(systemName: pinned ? "pin.slash" : "pin", help: pinned ? s.unpinHelp : s.pinHelp, size: 11) {
                            store.togglePin(session.sessionId)
                        }
                        IconButton(systemName: expanded ? "chevron.up" : "chevron.down", help: s.detailsHelp, size: 11) {
                            store.toggleExpanded(session.sessionId)
                        }
                        IconButton(systemName: "moon.zzz", help: s.sleepHelp, tint: .claude) {
                            store.requestSleep(session.sessionId)
                        }
                        IconButton(systemName: "xmark", help: s.closeHelp, tint: StatusColor.critical) {
                            store.requestClose(session.sessionId)
                        }
                    }
                    .transition(.opacity)
                } else {
                    UsageColumn(session: session, warnings: warnings)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, settings.compact ? 5 : 7)

            if let confirmation {
                ConfirmStrip(
                    text: confirmation.kind == .close
                        ? (session.activity == .busy ? s.confirmCloseBusy : s.confirmClose)
                        : s.confirmSleepBusy,
                    actionTitle: confirmation.kind == .close ? s.close : s.sleep,
                    cancelTitle: s.cancel,
                    actionColor: confirmation.kind == .close ? StatusColor.critical : .claude,
                    onCancel: store.cancelConfirmation, onConfirm: store.confirm
                )
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if expanded {
                SessionDetails(session: session)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(rowFill(warned: !warnings.isEmpty, highlighted: hovering || confirmation != nil || expanded))
        )
        .opacity(pending == .closing || pending == .sleeping ? 0.55 : 1)
        .contentShape(Rectangle())
        .onHover { value in
            withAnimation(.easeOut(duration: 0.12)) { hovering = value }
            if value { store.markSeen(session.sessionId) }
        }
        .onTapGesture { store.focus(session.sessionId) }
        .help("\(session.title)\n\(session.cwd)\n\(s.activity(session.activity)) · pid \(session.pid)\n\(s.rowTapHint)")
        .contextMenu {
            Button(s.focus) { store.focus(session.sessionId) }
            Button(expanded ? s.hideDetails : s.showDetails) { store.toggleExpanded(session.sessionId) }
            Button(pinned ? s.unpin : s.pin) { store.togglePin(session.sessionId) }
            Divider()
            Button(s.sleep) { store.requestSleep(session.sessionId) }
            Button(s.close) { store.requestClose(session.sessionId) }
            Divider()
            Button(s.copyResume) {
                store.copyResumeCommand(sessionId: session.sessionId, cwd: session.cwd, flags: session.flags)
            }
            Button(s.copySessionId) { store.copy(session.sessionId, message: s.copiedSessionId) }
            Button(s.revealInFinder) { store.revealInFinder(session.cwd) }
        }
    }

    private func meta(_ language: DeckLanguage) -> String {
        var parts = [Fmt.shortPath(session.cwd)]
        if let updated = session.updatedAt { parts.append(Fmt.relative(updated, now: store.now, language)) }
        if let model = session.model { parts.append(model.replacingOccurrences(of: "claude-", with: "")) }
        return parts.joined(separator: " · ")
    }

    private func rowFill(warned: Bool, highlighted: Bool) -> Color {
        if warned { return StatusColor.warning.opacity(highlighted ? 0.16 : 0.10) }
        return Color.wash(highlighted ? 0.075 : 0)
    }
}

/// Right-aligned memory / CPU figures (tabular digits so the column lines up).
private struct UsageColumn: View {
    let session: LiveSession
    let warnings: Set<ResourceWarning>
    @EnvironmentObject var store: DeckStore
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        let language = settings.language
        if let usage = session.usage {
            HStack(spacing: 5) {
                if !warnings.isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(StatusColor.warning)
                        .help(warnings.sorted { $0.rawValue < $1.rawValue }.map { store.warningText(session, $0) }.joined(separator: "\n"))
                }
                if settings.compact {
                    Text(verbatim: "\(Fmt.bytes(usage.memoryBytes, language)) · \(Fmt.percent(usage.cpuPercent, language))")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Fmt.bytes(usage.memoryBytes, language))
                            .font(.system(size: 10.5, weight: warnings.contains(.memory) ? .semibold : .regular).monospacedDigit())
                            .foregroundStyle(warnings.contains(.memory) ? Color.primary : Color.primary.opacity(0.75))
                        Text(Fmt.percent(usage.cpuPercent, language))
                            .font(.system(size: 10, weight: warnings.contains(.cpu) ? .semibold : .regular).monospacedDigit())
                            .foregroundStyle(warnings.contains(.cpu) ? Color.primary : Color.secondary)
                    }
                }
            }
        }
    }
}

private struct SessionDetails: View {
    let session: LiveSession
    @EnvironmentObject var store: DeckStore
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        let s = settings.strings
        let language = settings.language
        VStack(alignment: .leading, spacing: 4) {
            DetailRow(label: s.detailFolder) {
                Text(Fmt.shortPath(session.cwd)).textSelection(.enabled).lineLimit(2).help(session.cwd)
                IconButton(systemName: "folder", help: s.revealInFinder, size: 9.5) { store.revealInFinder(session.cwd) }
            }
            DetailRow(label: s.detailSession) {
                Text(session.sessionId).font(.system(size: 10).monospaced()).textSelection(.enabled).lineLimit(1)
                IconButton(systemName: "doc.on.doc", help: s.copySessionId, size: 9.5) {
                    store.copy(session.sessionId, message: s.copiedSessionId)
                }
            }
            DetailRow(label: s.detailTerminal) { Text(verbatim: s.terminalSummary(session.host)).lineLimit(1) }
            if let usage = session.usage {
                DetailRow(label: s.detailProcess) { Text(verbatim: "pid \(session.pid) · \(s.processes(usage.processCount))") }
                DetailRow(label: s.detailUsage) {
                    Text(verbatim: "\(Fmt.bytes(usage.memoryBytes, language)) · \(Fmt.percent(usage.cpuPercent, language)) CPU")
                }
            }
            if let started = session.startedAt {
                DetailRow(label: s.detailUptime) { Text(Fmt.duration(Date().timeIntervalSince(started), language)) }
            }
            if let model = session.model { DetailRow(label: s.detailModel) { Text(model) } }
            if let mode = session.permissionMode { DetailRow(label: s.detailMode) { Text(mode) } }
            if let bytes = session.transcriptBytes { DetailRow(label: s.detailTranscript) { Text(Fmt.bytes(bytes, language)) } }
            if let prompt = session.lastPrompt {
                DetailRow(label: s.detailLastPrompt) {
                    Text(prompt).lineLimit(4).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.leading, 33)
        .padding(.trailing, 10)
        .padding(.bottom, 9)
    }
}

private struct DetailRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 2) { content }
                .font(.system(size: 10.5))
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Sleeping row

struct SleepingRowView: View {
    let entry: SleepingSession
    @EnvironmentObject var store: DeckStore
    @EnvironmentObject var settings: AppSettings
    @State private var hovering = false

    var body: some View {
        let s = settings.strings
        let pending = store.pending[entry.sessionId]

        HStack(spacing: 9) {
            Image(systemName: "moon.fill")
                .font(.system(size: 9.5))
                .foregroundStyle(Color.secondary.opacity(0.8))
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !settings.compact {
                    Text(verbatim: "\(s.sleptAgo(Fmt.relative(entry.sleptAt, now: store.now, settings.language))) · \(Fmt.shortPath(entry.cwd))")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.secondary.opacity(0.75))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)

            if let pending {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text(s.pending(pending)).font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            } else if hovering {
                HStack(spacing: 0) {
                    IconButton(systemName: "play.fill", help: s.wakeHelp, tint: .claude) { store.wake(entry.sessionId) }
                    IconButton(systemName: "trash", help: s.forgetHelp, tint: StatusColor.critical) { store.forget(entry.sessionId) }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, settings.compact ? 5 : 7)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.wash(hovering ? 0.075 : 0)))
        .contentShape(Rectangle())
        .onHover { value in withAnimation(.easeOut(duration: 0.12)) { hovering = value } }
        .onTapGesture(count: 2) { store.wake(entry.sessionId) }
        .help("\(entry.title)\n\(entry.cwd)\n\(s.sleepingTapHint)")
        .contextMenu {
            Button(s.wake) { store.wake(entry.sessionId) }
            Button(s.copyResume) { store.copyResumeCommand(sessionId: entry.sessionId, cwd: entry.cwd, flags: entry.flags) }
            Divider()
            Button(s.removeFromList) { store.forget(entry.sessionId) }
        }
    }
}

// MARK: - Recent row

struct RecentRowView: View {
    let entry: RecentSession
    @EnvironmentObject var store: DeckStore
    @EnvironmentObject var settings: AppSettings
    @State private var hovering = false

    var body: some View {
        let s = settings.strings
        let language = settings.language
        let pending = store.pending[entry.sessionId]

        HStack(spacing: 9) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                if !settings.compact {
                    Text([Fmt.shortPath(entry.cwd), s.endedAgo(Fmt.relative(entry.modified, now: store.now, language)),
                          Fmt.bytes(entry.sizeBytes, language)].joined(separator: " · "))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)

            if let pending {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text(s.pending(pending)).font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            } else if hovering {
                HStack(spacing: 0) {
                    IconButton(systemName: "doc.on.doc", help: s.copyResume, size: 10.5) {
                        store.copyResumeCommand(sessionId: entry.sessionId, cwd: entry.cwd, flags: entry.flags)
                    }
                    IconButton(systemName: "play.fill", help: s.resumeHelp, tint: .claude) { store.resumeRecent(entry.sessionId) }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, settings.compact ? 5 : 7)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.wash(hovering ? 0.075 : 0)))
        .contentShape(Rectangle())
        .onHover { value in withAnimation(.easeOut(duration: 0.12)) { hovering = value } }
        .onTapGesture(count: 2) { store.resumeRecent(entry.sessionId) }
        .help([entry.title, entry.cwd, entry.lastPrompt.map { "“\($0.prefix(160))”" }, s.recentTapHint]
            .compactMap { $0 }.joined(separator: "\n"))
        .contextMenu {
            Button(s.resume) { store.resumeRecent(entry.sessionId) }
            Button(s.copyResume) { store.copyResumeCommand(sessionId: entry.sessionId, cwd: entry.cwd, flags: entry.flags) }
            Button(s.copySessionId) { store.copy(entry.sessionId, message: s.copiedSessionId) }
            Button(s.revealInFinder) { store.revealInFinder(entry.cwd) }
        }
    }
}

private struct Badge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 8.5, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 3).stroke(Color.secondary.opacity(0.5), lineWidth: 0.5))
    }
}

/// "Done" marker for a session that finished while you weren't looking (icon + label, not color alone).
private struct DonePill: View {
    let text: String

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 8.5)).foregroundStyle(StatusColor.good)
            Text(text).font(.system(size: 9, weight: .semibold))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(Capsule().fill(StatusColor.good.opacity(0.15)))
    }
}
