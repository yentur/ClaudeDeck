import DeckCore
import SwiftUI

struct DeckRootView: View {
    @EnvironmentObject var store: DeckStore
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            if store.showSettings {
                SettingsView()
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                if settings.showUsagePanel {
                    UsagePanel()
                }
                FilterBar()
                if let plan = store.bulkPlan {
                    ConfirmStrip(text: settings.strings.bulkConfirm(plan), actionTitle: settings.strings.sleepAll,
                                 cancelTitle: settings.strings.cancel, actionColor: .claude,
                                 onCancel: store.cancelBulkSleep, onConfirm: store.confirmBulkSleep)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                Rectangle().fill(Color.wash(0.08)).frame(height: 0.5)
                SessionListView()
                    .transition(.opacity)
            }
            if let banner = store.banner {
                BannerView(text: banner, action: store.bannerAction)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottomLeading) { GripOverlay() }
        .overlay(
            RoundedRectangle(cornerRadius: PanelController.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        )
        .animation(.easeInOut(duration: 0.18), value: store.showSettings)
        .animation(.easeInOut(duration: 0.18), value: settings.showUsagePanel)
    }
}

private struct GripOverlay: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ResizeGrip()
            Image(systemName: "arrow.down.left")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Color.secondary.opacity(0.5))
                .padding(4)
                .allowsHitTesting(false)
        }
        .frame(width: 18, height: 18)
    }
}

struct BannerView: View {
    let text: String
    var action: BannerAction?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle.fill").foregroundStyle(Color.claude)
            Text(text).lineLimit(action == nil ? 2 : 4).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let action {
                Button(action.title) { action.perform() }
                    .buttonStyle(PillButtonStyle(fill: Color.wash(0.12), foreground: .primary))
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.wash(0.07))
        .padding(.leading, 12)
    }
}

struct HeaderView: View {
    @EnvironmentObject var store: DeckStore
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var panel: PanelController

    var body: some View {
        let s = settings.strings
        HStack(spacing: 9) {
            ZStack {
                Circle().fill(Color.claude.opacity(0.18))
                Image(systemName: "sparkle")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.claude)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(store.showSettings ? s.settingsTitle : s.appTitle)
                    .font(.system(size: 13, weight: .semibold))
                Text(s.summary(live: store.sessions.count, busy: store.busyCount, asleep: store.sleeping.count))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)

            HStack(spacing: 0) {
                IconButton(systemName: "pin", help: s.pinTopRightHelp) { panel.pinTopRight() }
                IconButton(systemName: store.showSettings ? "list.bullet" : "slider.horizontal.3",
                           help: store.showSettings ? s.backToListHelp : s.settingsHelp) {
                    store.showSettings.toggle()
                }
                IconButton(systemName: "minus", help: s.hideHelp) { panel.hide() }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(WindowDragHandle())
    }
}

struct FilterBar: View {
    @EnvironmentObject var store: DeckStore
    @EnvironmentObject var settings: AppSettings
    @FocusState private var searchFocused: Bool

    var body: some View {
        let s = settings.strings
        VStack(spacing: 7) {
            HStack(spacing: 4) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(SessionFilter.allCases) { filter in
                            FilterChip(title: s.filter(filter), count: store.count(for: filter), selected: settings.filter == filter) {
                                withAnimation(.easeInOut(duration: 0.15)) { settings.filter = filter }
                            }
                        }
                    }
                }
                MoreMenu()
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField(s.searchPlaceholder, text: $store.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($searchFocused)
                    .onExitCommand { store.query = ""; searchFocused = false }
                if !store.query.isEmpty {
                    Button { store.query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.wash(searchFocused ? 0.1 : 0.06)))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 9)
    }
}

/// Sort order and "sleep idle sessions" bulk actions.
private struct MoreMenu: View {
    @EnvironmentObject var store: DeckStore
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        let s = settings.strings
        Menu {
            Picker(s.sortBy, selection: $settings.sort) {
                ForEach(SessionSort.allCases) { sort in
                    Text(s.sort(sort)).tag(sort)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Section(s.sleepIdleSessions) {
                ForEach(AppSettings.idleSleepThresholds, id: \.self) { threshold in
                    let plan = store.idleSleepPlan(threshold: threshold)
                    Button(s.bulkOption(plan)) { store.requestBulkSleep(threshold: threshold) }
                        .disabled(plan.sessions.isEmpty)
                }
            }
            Divider()
            Button(s.refresh) {
                store.refresh()
                store.refreshRecent()
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 24, height: 22)
        .help(s.moreHelp)
    }
}

private struct FilterChip: View {
    let title: String
    let count: Int?
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).font(.system(size: 11, weight: .semibold))
                if let count {
                    Text(verbatim: "\(count)")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .opacity(0.75)
                }
            }
            .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.8))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(selected ? Color.claude : Color.wash(hovering ? 0.1 : 0.05)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
