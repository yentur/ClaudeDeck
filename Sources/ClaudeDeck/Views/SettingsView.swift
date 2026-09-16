import AppKit
import DeckCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: DeckStore
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var panel: PanelController
    @EnvironmentObject var notifier: Notifier
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        let s = settings.strings
        let presets: [(String, NSSize)] = [
            (s.small, NSSize(width: 320, height: 420)),
            (s.medium, NSSize(width: 380, height: 600)),
            (s.large, NSSize(width: 460, height: 780)),
        ]

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SettingsSection(title: s.sectionGeneral) {
                    LabeledRow(s.language_) {
                        Picker("", selection: $settings.language) {
                            Text("English").tag(DeckLanguage.en)
                            Text("Türkçe").tag(DeckLanguage.tr)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 150)
                    }
                }

                SettingsSection(title: s.sectionAppearance) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(s.opacity)
                            Spacer()
                            Text(Fmt.percent(settings.opacity * 100, settings.language))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $settings.opacity, in: AppSettings.opacityRange)
                            .tint(.claude)
                    }
                    SwitchRow(s.hoverOpaque, isOn: $settings.hoverOpaque)
                    SwitchRow(s.alwaysOnTop, isOn: $settings.alwaysOnTop)
                    SwitchRow(s.compactRows, isOn: $settings.compact)
                    SwitchRow(s.showUsagePanel, isOn: $settings.showUsagePanel)
                    SwitchRow(s.menuBarMemory, isOn: $settings.menuBarMemory)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(s.size)
                        HStack(spacing: 5) {
                            ForEach(presets, id: \.0) { preset in
                                Button(preset.0) { panel.resize(to: preset.1) }
                                    .buttonStyle(PillButtonStyle(fill: Color.wash(0.1), foreground: .primary))
                            }
                            Spacer(minLength: 0)
                            Button(s.snapTopRight) { panel.pinTopRight() }
                                .buttonStyle(PillButtonStyle(fill: .claude))
                        }
                        Text(s.resizeHint)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsSection(title: s.sectionNotifications) {
                    SwitchRow(s.notifyFinished, isOn: $settings.notifyOnFinish)
                        .onChange(of: settings.notifyOnFinish) { _, on in if on { notifier.requestPermissionIfNeeded() } }
                    LabeledRow(s.minimumBusy) {
                        Picker("", selection: $settings.minimumBusySeconds) {
                            ForEach(Self.withCurrent(AppSettings.minimumBusyChoices, settings.minimumBusySeconds), id: \.self) {
                                Text(s.seconds($0)).tag($0)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 90)
                    }
                    .disabled(!settings.notifyOnFinish)
                    SwitchRow(s.playSound, isOn: $settings.notificationSound)
                    if notifier.permission == .denied {
                        HStack(spacing: 6) {
                            Image(systemName: "bell.slash.fill").foregroundStyle(StatusColor.warning)
                            Text(s.notificationsDenied).font(.system(size: 10.5)).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Button(s.openSystemSettings) { notifier.openSystemSettings() }
                                .buttonStyle(PillButtonStyle(fill: Color.wash(0.12), foreground: .primary))
                        }
                    }
                }

                SettingsSection(title: s.sectionWarnings) {
                    SwitchRow(s.highlightHeavy, isOn: $settings.warningsEnabled)
                    Group {
                        LabeledRow(s.memoryLimit) {
                            Picker("", selection: $settings.memoryLimitGB) {
                                ForEach(Self.withCurrent(AppSettings.memoryLimitChoicesGB, settings.memoryLimitGB), id: \.self) { gb in
                                    Text(Fmt.bytes(UInt64(gb * 1_073_741_824), settings.language)).tag(gb)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 90)
                        }
                        LabeledRow(s.cpuLimit) {
                            Picker("", selection: $settings.cpuLimitPercent) {
                                ForEach(Self.withCurrent(AppSettings.cpuLimitChoices, settings.cpuLimitPercent), id: \.self) {
                                    Text(Fmt.percent($0, settings.language)).tag($0)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 90)
                        }
                        SwitchRow(s.notifyWarnings, isOn: $settings.notifyOnWarning)
                            .onChange(of: settings.notifyOnWarning) { _, on in if on { notifier.requestPermissionIfNeeded() } }
                    }
                    .disabled(!settings.warningsEnabled)
                }

                SettingsSection(title: s.sectionSessions) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(s.resumeTerminalLabel)
                        Picker("", selection: $settings.resumeTerminal) {
                            Text(s.resumeTerminalAuto).tag(AppSettings.autoTerminal)
                            Divider()
                            ForEach(resumeChoices, id: \.self) { kind in
                                Text(kind.displayName).tag(kind.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: 240, alignment: .leading)
                        Text(s.resumeTerminalHint)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                SettingsSection(title: s.sectionSystem) {
                    SwitchRow(s.launchAtLogin, isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, enabled in
                            do {
                                try LoginItem.setEnabled(enabled, language: settings.language)
                            } catch {
                                launchAtLogin = LoginItem.isEnabled
                                store.showBanner(s.loginItemFailed(error))
                            }
                        }
                    HStack {
                        Text(s.showHide)
                        Spacer()
                        Text("⌥⌘K")
                            .font(.system(size: 11, weight: .semibold).monospaced())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.wash(0.1)))
                    }
                    Button(s.quit) { NSApp.terminate(nil) }
                        .buttonStyle(PillButtonStyle(fill: StatusColor.critical.opacity(0.9)))
                }

                HStack(spacing: 4) {
                    Text(s.versionFooter(AppInfo.version))
                    Text(verbatim: "·")
                    Button(s.githubLink) { AppInfo.open(AppInfo.repositoryURL) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.claude)
                        .help(AppInfo.repositoryURL.absoluteString)
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
            }
            .font(.system(size: 12))
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 20)
        }
        .onAppear {
            notifier.refreshPermission()
            settings.refreshInstalledTerminals()
        }
    }

    /// Installed terminals, plus the chosen one even if it has since been uninstalled.
    private var resumeChoices: [TerminalKind] {
        guard let chosen = settings.resumeTerminalKind, !settings.installedTerminals.contains(chosen) else {
            return settings.installedTerminals
        }
        return settings.installedTerminals + [chosen]
    }

    /// Keeps a picker from rendering blank when the stored value isn't one of the presets.
    static func withCurrent<T: Comparable & Hashable>(_ choices: [T], _ current: T) -> [T] {
        choices.contains(current) ? choices : (choices + [current]).sorted()
    }
}

/// Label on the left, switch on the right.
private struct SwitchRow: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn).labelsHidden()
        }
    }
}

private struct LabeledRow<Control: View>: View {
    let title: String
    @ViewBuilder let control: Control

    init(_ title: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.control = control()
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            control
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
            VStack(alignment: .leading, spacing: 9) {
                content
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.wash(0.05)))
        }
    }
}
