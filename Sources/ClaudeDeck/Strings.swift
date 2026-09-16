import DeckCore
import Foundation

/// Every user-visible string, in English (default) and Turkish.
struct Strings {
    let language: DeckLanguage
    private var tr: Bool { language == .tr }
    private func t(_ en: String, _ tr: String) -> String { self.tr ? tr : en }

    // MARK: Header & summary
    var appTitle: String { t("Claude Sessions", "Claude Oturumları") }
    var settingsTitle: String { t("Settings", "Ayarlar") }
    func summary(live: Int, busy: Int, asleep: Int) -> String {
        var parts = [t("\(live) running", "\(live) aktif")]
        if busy > 0 { parts.append(t("\(busy) working", "\(busy) çalışıyor")) }
        if asleep > 0 { parts.append(t("\(asleep) asleep", "\(asleep) uyuyan")) }
        return parts.joined(separator: " · ")
    }
    var pinTopRightHelp: String { t("Snap to top right", "Sağ üste yapıştır") }
    var settingsHelp: String { t("Settings", "Ayarlar") }
    var backToListHelp: String { t("Back to sessions", "Listeye dön") }
    var hideHelp: String { t("Hide (⌥⌘K)", "Gizle (⌥⌘K)") }

    // MARK: Filters, sort, bulk
    func filter(_ filter: SessionFilter) -> String {
        switch filter {
        case .all: return t("All", "Tümü")
        case .busy: return t("Working", "Çalışan")
        case .idle: return t("Idle", "Boşta")
        case .sleeping: return t("Asleep", "Uyuyan")
        case .recent: return t("Recent", "Geçmiş")
        }
    }
    var searchPlaceholder: String { t("Search title or folder", "Başlık veya klasör ara") }
    var moreHelp: String { t("Sort & bulk actions", "Sıralama ve toplu işlemler") }
    var sortBy: String { t("Sort by", "Sırala") }
    func sort(_ sort: SessionSort) -> String {
        switch sort {
        case .activity: return t("Activity", "Durum")
        case .memory: return t("Memory", "Bellek")
        case .cpu: return t("CPU", "CPU")
        case .recent: return t("Last active", "Son etkinlik")
        case .name: return t("Name", "Ad")
        }
    }
    var sleepIdleSessions: String { t("Sleep idle sessions", "Boştaki oturumları uyut")  }
    func idleThreshold(_ seconds: TimeInterval) -> String {
        if seconds < 3600 {
            let minutes = max(1, Int(seconds / 60))
            return t("Idle > \(minutes) min", "\(minutes) dakikadan uzun boşta")
        }
        let hours = Int(seconds / 3600)
        if hours >= 24 { return t("Idle > \(hours / 24) day\(hours / 24 == 1 ? "" : "s")", "\(hours / 24) günden uzun boşta") }
        return t("Idle > \(hours) hour\(hours == 1 ? "" : "s")", "\(hours) saatten uzun boşta")
    }
    func bulkOption(_ plan: IdleSleepPlan) -> String {
        "\(idleThreshold(plan.threshold)) — " + (plan.sessions.isEmpty
            ? t("none", "yok")
            : t("\(plan.sessions.count) · frees \(Fmt.bytes(plan.memoryBytes, language))",
                "\(plan.sessions.count) · \(Fmt.bytes(plan.memoryBytes, language)) boşalır"))
    }
    func bulkConfirm(_ plan: IdleSleepPlan) -> String {
        t("Sleep \(plan.sessions.count) sessions (\(idleThreshold(plan.threshold).lowercased()))? Frees ~\(Fmt.bytes(plan.memoryBytes, language)).",
          "\(plan.sessions.count) oturum uyutulsun mu (\(idleThreshold(plan.threshold)))? ~\(Fmt.bytes(plan.memoryBytes, language)) boşalır.")
    }
    var sleepAll: String { t("Sleep all", "Hepsini uyut") }
    var refresh: String { t("Refresh", "Yenile") }

    // MARK: Usage panel
    var sessionsTile: String { t("Sessions", "Oturumlar") }
    var memoryTile: String { t("Memory", "Bellek") }
    var cpuTile: String { t("CPU", "CPU") }
    func sessionsCaption(busy: Int, asleep: Int, processes: Int) -> String {
        t("\(busy) working · \(processes) procs", "\(busy) çalışıyor · \(processes) süreç")
    }
    func ramShare(percent: Int, total: UInt64) -> String {
        t("\(percent)% of \(Fmt.bytes(total, language))", "%\(percent) / \(Fmt.bytes(total, language))")
    }
    func cpuCaption(cores: Int) -> String { t("last 10 min · \(cores) cores", "son 10 dk · \(cores) çekirdek") }
    func cpuHover(value: String, ago: String) -> String { t("\(value) · \(ago) ago", "\(value) · \(ago) önce") }
    var cpuHelp: String {
        t("Sum over all sessions and their child processes. 100% = one full CPU core.",
          "Tüm oturumlar ve alt süreçlerinin toplamı. %100 = bir tam CPU çekirdeği.")
    }
    var memoryHelp: String {
        t("Memory footprint of every session and its child processes (MCP servers, tools), like Activity Monitor.",
          "Her oturumun ve alt süreçlerinin (MCP sunucuları, araçlar) bellek kullanımı; Activity Monitor ile aynı ölçü.")
    }

    // MARK: Rows
    func activity(_ activity: SessionActivity) -> String {
        switch activity {
        case .busy: return t("Working", "Çalışıyor")
        case .shell: return t("Running a shell command", "Shell komutu çalışıyor")
        case .idle: return t("Idle", "Boşta")
        case .other(let raw): return raw
        }
    }
    var done: String { t("Done", "Bitti") }
    var doneHelp: String { t("Finished its turn — waiting for you", "Turunu bitirdi — seni bekliyor") }
    var sleepHelp: String { t("Sleep — close now, resume later where it left off", "Uyut — şimdi kapat, sonra kaldığı yerden aç") }
    var closeHelp: String { t("Close", "Kapat") }
    var pinHelp: String { t("Pin to top", "Üste sabitle") }
    var unpinHelp: String { t("Unpin", "Sabitlemeyi kaldır") }
    var detailsHelp: String { t("Details", "Ayrıntılar") }
    var wakeHelp: String { t("Wake — resume where it left off", "Uyandır — kaldığı yerden aç") }
    var resumeHelp: String { t("Resume this session", "Bu oturumu devam ettir") }
    var forgetHelp: String { t("Remove from list", "Listeden kaldır") }
    var rowTapHint: String { t("Click: jump to its terminal tab", "Tıkla: terminal sekmesine geç") }
    var sleepingTapHint: String { t("Double-click: wake", "Çift tıkla: uyandır") }
    var recentTapHint: String { t("Double-click: resume", "Çift tıkla: devam ettir") }
    func sleptAgo(_ relative: String) -> String {
        relative == Fmt.relative(Date(), now: Date(), language)
            ? t("slept just now", "az önce uyudu")
            : t("slept \(relative) ago", "\(relative) önce uyudu")
    }
    func endedAgo(_ relative: String) -> String {
        relative == Fmt.relative(Date(), now: Date(), language) ? t("just now", "az önce") : t("\(relative) ago", "\(relative) önce")
    }
    var asleepSection: String { t("ASLEEP", "UYUYAN") }
    func pending(_ action: PendingAction) -> String {
        switch action {
        case .closing: return t("Closing…", "Kapatılıyor…")
        case .sleeping: return t("Sleeping…", "Uyutuluyor…")
        case .waking: return t("Opening…", "Açılıyor…")
        }
    }
    var confirmClose: String { t("Close this session?", "Oturum kapatılsın mı?") }
    var confirmCloseBusy: String { t("It's working — close anyway?", "Çalışıyor — yine de kapatılsın mı?") }
    var confirmSleepBusy: String { t("It's working — sleep anyway?", "Çalışıyor — yine de uyutulsun mu?") }
    var cancel: String { t("Cancel", "İptal") }
    var close: String { t("Close", "Kapat") }
    var sleep: String { t("Sleep", "Uyut") }
    func memoryWarning(used: UInt64, limit: UInt64) -> String {
        t("High memory: \(Fmt.bytes(used, language)) (limit \(Fmt.bytes(limit, language)))",
          "Yüksek bellek: \(Fmt.bytes(used, language)) (limit \(Fmt.bytes(limit, language)))")
    }
    func cpuWarning(used: Double, limit: Double) -> String {
        t("Sustained high CPU: \(Fmt.percent(used, language)) (limit \(Fmt.percent(limit, language)) for 1 min)",
          "Sürekli yüksek CPU: \(Fmt.percent(used, language)) (1 dk boyunca limit \(Fmt.percent(limit, language)))")
    }

    // MARK: Details
    var detailFolder: String { t("Folder", "Klasör") }
    var detailSession: String { t("Session", "Oturum") }
    var detailProcess: String { t("Process", "Süreç") }
    var detailUsage: String { t("Usage", "Kullanım") }
    var detailUptime: String { t("Running for", "Çalışma süresi") }
    var detailModel: String { t("Model", "Model") }
    var detailMode: String { t("Permissions", "İzinler") }
    var detailTranscript: String { t("Transcript", "Transcript") }
    var detailLastPrompt: String { t("Last prompt", "Son istem") }
    func processes(_ count: Int) -> String { t("\(count) process\(count == 1 ? "" : "es")", "\(count) süreç") }

    // MARK: Context menus
    var focus: String { t("Jump to tab", "Sekmeye geç") }
    var showDetails: String { t("Show details", "Ayrıntıları göster") }
    var hideDetails: String { t("Hide details", "Ayrıntıları gizle") }
    var copyResume: String { t("Copy resume command", "Resume komutunu kopyala") }
    var copySessionId: String { t("Copy session ID", "Session ID kopyala") }
    var revealInFinder: String { t("Show folder in Finder", "Klasörü Finder'da göster") }
    var wake: String { t("Wake", "Uyandır") }
    var resume: String { t("Resume", "Devam ettir") }
    var removeFromList: String { t("Remove from list", "Listeden kaldır") }
    var pin: String { t("Pin to top", "Üste sabitle") }
    var unpin: String { t("Unpin", "Sabitlemeyi kaldır") }

    // MARK: Empty states
    func empty(_ filter: SessionFilter, query: String) -> String {
        if !query.isEmpty { return t("No matching sessions", "Eşleşen oturum yok") }
        switch filter {
        case .all: return t("No Claude Code sessions running", "Açık Claude Code oturumu yok")
        case .busy: return t("Nothing is working right now", "Şu an çalışan oturum yok")
        case .idle: return t("No idle sessions", "Boşta bekleyen oturum yok")
        case .sleeping: return t("No sleeping sessions", "Uyuyan oturum yok")
        case .recent: return t("No recent sessions", "Geçmiş oturum yok")
        }
    }
    var loadingRecent: String { t("Reading transcripts…", "Transcript'ler okunuyor…") }

    // MARK: Banners
    func couldNotClose(pid: Int32) -> String { t("Couldn't close the session (pid \(pid))", "Oturum kapatılamadı (pid \(pid))") }
    func couldNotSleep(pid: Int32) -> String { t("Couldn't put the session to sleep (pid \(pid))", "Oturum uyutulamadı (pid \(pid))") }
    func sleepRecordFailed(_ error: Error) -> String { t("Couldn't save sleep record: ", "Uyku kaydı yazılamadı: ") + error.localizedDescription }
    func folderMissing(_ path: String) -> String { t("Folder no longer exists: ", "Klasör artık yok: ") + Fmt.shortPath(path) }
    var cmuxMissing: String { t("cmux not found — choose Terminal in Settings", "cmux bulunamadı — Ayarlar'dan Terminal'i seç") }
    var notYetVisible: String { t("Session started but hasn't shown up yet", "Oturum başlatıldı ama henüz listede görünmedi") }
    func focusFailed(_ error: Error) -> String { t("Couldn't jump to it: ", "Odaklanılamadı: ") + error.localizedDescription }
    var copiedResume: String { t("Resume command copied", "Resume komutu kopyalandı") }
    var copiedSessionId: String { t("Session ID copied", "Session ID kopyalandı") }
    func loginItemFailed(_ error: Error) -> String { t("Couldn't change login item: ", "Giriş öğesi ayarlanamadı: ") + error.localizedDescription }
    func bulkDone(_ count: Int, _ memory: UInt64) -> String {
        t("Put \(count) sessions to sleep · freed ~\(Fmt.bytes(memory, language))", "\(count) oturum uyutuldu · ~\(Fmt.bytes(memory, language)) boşaldı")
    }

    // MARK: Notifications
    var finishedTitle: String { t("Claude finished", "Claude bitirdi") }
    func finishedBody(title: String, worked: TimeInterval) -> String {
        t("“\(title)” is waiting for you · worked \(Fmt.duration(worked, language))",
          "“\(title)” seni bekliyor · \(Fmt.duration(worked, language)) çalıştı")
    }
    func warningTitle(_ warning: ResourceWarning) -> String {
        warning == .memory ? t("Session using a lot of memory", "Oturum çok bellek kullanıyor")
            : t("Session using a lot of CPU", "Oturum çok CPU kullanıyor")
    }

    // MARK: Settings
    var sectionGeneral: String { t("GENERAL", "GENEL") }
    var sectionAppearance: String { t("APPEARANCE", "GÖRÜNÜM") }
    var sectionNotifications: String { t("NOTIFICATIONS", "BİLDİRİMLER") }
    var sectionWarnings: String { t("RESOURCE WARNINGS", "KAYNAK UYARILARI") }
    var sectionSessions: String { t("SESSIONS", "OTURUMLAR") }
    var sectionSystem: String { t("SYSTEM", "SİSTEM") }
    var language_: String { t("Language", "Dil") }
    var opacity: String { t("Opacity", "Saydamlık") }
    var hoverOpaque: String { t("Fully opaque on hover", "Üzerine gelince tam opak") }
    var alwaysOnTop: String { t("Always on top", "Her zaman üstte") }
    var compactRows: String { t("Compact rows", "Kompakt satırlar") }
    var showUsagePanel: String { t("Show usage panel", "Kullanım panelini göster") }
    var menuBarMemory: String { t("Show total memory in menu bar", "Menü çubuğunda toplam belleği göster") }
    var size: String { t("Size", "Boyut") }
    var small: String { t("Small", "Küçük") }
    var medium: String { t("Medium", "Orta") }
    var large: String { t("Large", "Büyük") }
    var snapTopRight: String { t("Snap top right", "Sağ üste yapıştır") }
    var resizeHint: String { t("You can also drag the bottom-left corner.", "Sol alt köşeden sürükleyerek de boyutlandırabilirsin.") }
    var notifyFinished: String { t("Notify when a session finishes", "Oturum bitince bildir") }
    var minimumBusy: String { t("Only if it worked at least", "En az şu kadar çalıştıysa") }
    var playSound: String { t("Play sound", "Ses çal") }
    var notificationsDenied: String {
        t("Notifications are turned off for ClaudeDeck in System Settings.", "ClaudeDeck bildirimleri Sistem Ayarları'nda kapalı.")
    }
    var openSystemSettings: String { t("Open", "Aç") }
    var highlightHeavy: String { t("Highlight heavy sessions", "Ağır oturumları vurgula") }
    var memoryLimit: String { t("Memory above", "Bellek şunu aşınca") }
    var cpuLimit: String { t("CPU above (for 1 min)", "CPU şunu aşınca (1 dk)") }
    var notifyWarnings: String { t("Notify on warnings", "Uyarılarda bildir") }
    var launchAtLogin: String { t("Launch at login", "Girişte başlat") }
    var showHide: String { t("Show / hide", "Göster / gizle") }
    var quit: String { t("Quit ClaudeDeck", "ClaudeDeck'ten çık") }
    func seconds(_ value: Int) -> String {
        value < 60 ? t("\(value) s", "\(value) sn") : t("\(value / 60) min", "\(value / 60) dk")
    }

    // MARK: Menu bar
    var showCard: String { t("Show Card", "Kartı Göster") }
    var hideCard: String { t("Hide Card", "Kartı Gizle") }
    var snapTopRightMenu: String { t("Snap to Top Right", "Sağ Üste Yapıştır") }
    var settingsMenu: String { t("Settings…", "Ayarlar…") }
    var quitMenu: String { t("Quit ClaudeDeck", "ClaudeDeck'ten Çık") }

    // MARK: Terminals
    var detailTerminal: String { t("Terminal", "Terminal") }
    var unknownTerminal: String { t("Unknown", "Bilinmiyor") }
    func terminalName(_ host: SessionHost) -> String { TerminalApps.name(of: host, unknown: unknownTerminal) }
    /// "Ghostty · tmux · ttys003"
    func terminalSummary(_ host: SessionHost) -> String {
        var parts = [terminalName(host)]
        if host.tmux != nil { parts.append("tmux") }
        if let tty = host.tty { parts.append(URL(fileURLWithPath: tty).lastPathComponent) }
        return parts.joined(separator: " · ")
    }
    var resumeTerminalLabel: String { t("Open resumed sessions in", "Devam ettirilen oturumları şurada aç") }
    var resumeTerminalAuto: String { t("Auto (same terminal as before)", "Otomatik (önceki terminal)") }
    var resumeTerminalHint: String {
        t("Auto reopens a sleeping session in the terminal it ran in; other sessions open where most of your sessions run, or in your default app for .command files.",
          "Otomatik, uyuyan oturumu çalıştığı terminalde açar; diğerleri oturumlarının çoğunun çalıştığı terminalde ya da .command dosyalarını açan varsayılan uygulamada açılır.")
    }
    func terminalNotInstalled(_ name: String) -> String {
        t("\(name) isn't installed — choose another terminal in Settings", "\(name) yüklü değil — Ayarlar'dan başka bir terminal seç")
    }
    func couldNotOpen(_ detail: String) -> String { t("Couldn't open: ", "Açılamadı: ") + detail }
    func automationDenied(_ app: String) -> String {
        t("ClaudeDeck isn't allowed to control \(app). Allow it in System Settings → Privacy & Security → Automation.",
          "ClaudeDeck'in \(app) uygulamasını yönetme izni yok. Sistem Ayarları → Gizlilik ve Güvenlik → Otomasyon'dan izin ver.")
    }
    var openAutomationSettings: String { t("Open Settings", "Ayarları Aç") }
    func tabNotFound(_ app: String) -> String {
        t("Couldn't find its tab — brought \(app) to the front", "Sekmesi bulunamadı — \(app) öne getirildi")
    }
    var hostUnknown: String {
        t("Couldn't tell which terminal this session runs in", "Bu oturumun hangi terminalde çalıştığı anlaşılamadı")
    }
    var tmuxNoClient: String {
        t("No tmux client is attached — attach command copied", "Bağlı tmux istemcisi yok — attach komutu kopyalandı")
    }
    var warpPasteHint: String {
        t("Resume command copied — paste with ⌘V and press Return", "Resume komutu kopyalandı — ⌘V ile yapıştırıp Return'e bas")
    }

    // MARK: Release polish
    var githubMenu: String { t("ClaudeDeck on GitHub…", "GitHub'da ClaudeDeck…") }
    var checkForUpdatesMenu: String { t("Check for Updates…", "Güncellemeleri Denetle…") }
    func versionFooter(_ version: String) -> String { t("ClaudeDeck \(version)", "ClaudeDeck \(version)") }
    var githubLink: String { t("GitHub", "GitHub") }
    var moveToApplications: String {
        t("Move ClaudeDeck to Applications, then reopen it.", "ClaudeDeck'i Uygulamalar klasörüne taşı, sonra yeniden aç.")
    }
}
