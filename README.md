<p align="right">🇹🇷 <a href="README.tr.md">Türkçe</a></p>

<p align="center">
  <img src="Resources/AppIcon-1024.png" width="128" alt="ClaudeDeck icon">
</p>

<h1 align="center">ClaudeDeck</h1>

<p align="center">
  <b>Every Claude Code session on your Mac — in one floating card.</b><br>
  See memory &amp; CPU per session, put idle ones to sleep, resume them exactly where they left off.
</p>

<p align="center">
  <a href="https://github.com/yentur/ClaudeDeck/releases/latest"><img src="https://img.shields.io/github/v/release/yentur/ClaudeDeck?style=flat-square&label=release" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-000000?style=flat-square&logo=apple&logoColor=white" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.10%2B-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.10+">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" alt="MIT license"></a>
  <a href="#install"><img src="https://img.shields.io/badge/homebrew-yentur%2Ftap-FBB040?style=flat-square&logo=homebrew&logoColor=white" alt="Homebrew tap"></a>
  <a href="https://github.com/yentur/ClaudeDeck/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/yentur/ClaudeDeck/ci.yml?branch=main&style=flat-square&label=CI" alt="CI"></a>
</p>

<p align="center">
  <img src="docs/images/hero.png" alt="ClaudeDeck showing running Claude Code sessions with memory and CPU usage" width="880">
</p>

## Why ClaudeDeck?

Once you run more than a handful of Claude Code sessions in parallel, the terminal tabs stop telling you what you need to know:

- **Which one is burning RAM?** Every session drags along MCP servers, language servers and build tools. ClaudeDeck adds up each session's whole process tree, so the heavy one is obvious.
- **Which one finished?** Get a notification the moment a session finishes its turn and is waiting for you — then click it to jump straight to its tab.
- **Can I close it without losing context?** Put a session to sleep to free its memory, and wake it later with `claude --resume`, in the same folder, with the same flags.

ClaudeDeck is a small native app (SwiftUI + AppKit) that stays out of your way: a translucent card pinned to the top-right corner, toggled with <kbd>⌥</kbd><kbd>⌘</kbd><kbd>K</kbd>. It is 100% local and light: ~0.5–1% CPU while idle and ~40–60 MB of memory.

## Features

**📊 See everything at a glance**
- 🟢 Every running Claude Code CLI session in one list, with a status dot: working (pulses), running a shell command, or idle.
- 🏷️ Real titles (the AI-generated title from the transcript, or the name you gave it), plus folder · last active · model.
- 🧠 Per-session memory and CPU, measured over the whole process tree: `claude` + MCP servers + tools and subprocesses.
- 📈 Usage panel: session count with a working/idle bar and process count, total memory with a share-of-RAM meter, and total CPU with a 10-minute sparkline (hover to read past values).
- 🔎 Details for any session: folder, session ID, pid and process count, usage, uptime, model, permission mode, transcript size and the last prompt.

**😴 Sleep, wake and resume**
- 💤 **Sleep** closes a session now and remembers how to resume it exactly where it left off — including flags like `--dangerously-skip-permissions`, `--model`, `--permission-mode` and `--add-dir`.
- ▶️ **Wake** reopens it in your terminal with `claude --resume`, in the original project folder.
- 🧹 **Sleep idle sessions** idle for more than 1 h / 6 h / 24 h / 3 days in one go; the menu shows how much memory it frees.
- 🕘 **Recent** tab: sessions that already ended (even ones ClaudeDeck never touched), resumable with one click. The permission mode is restored and the session runs in its original project folder.

**🔔 Stay in the loop**
- ✅ Finished-turn alerts: a macOS notification when a working session goes idle after at least N seconds (click it to jump to the session), a **Done** badge on the row and a ✓ count in the menu bar. Without notification permission, ClaudeDeck plays a sound instead.
- ⚠️ Resource warnings: a row turns amber when a session tree goes over a memory limit (default 2 GB) or stays over a CPU limit (default 100% for 1 minute). Optional notifications.

**🖥️ Fits your workflow**
- 🎯 Click a row to jump to its terminal tab — cmux, Terminal.app, iTerm2, Ghostty, kitty, WezTerm and tmux panes (see [Supported terminals](#supported-terminals)).
- 📌 Pins, filters (All · Working · Idle · Asleep · Recent), search over title, folder and last prompt, and sorting by activity, memory, CPU, last active or name.
- 🎛️ Settings: English / Türkçe, opacity, fully opaque on hover, always on top, compact rows, usage panel, total memory in the menu bar, size presets, notifications, warning limits, the terminal for resumed sessions, and launch at login.
- 🔒 Private by design: no network access, no telemetry, and `~/.claude` is only ever read.

## Screenshots

<table>
  <tr>
    <td align="center"><img src="docs/images/details.png" alt="Session details" width="280"><br><sub>Session details</sub></td>
    <td align="center"><img src="docs/images/recent.png" alt="Recent sessions" width="280"><br><sub>Recent sessions</sub></td>
    <td align="center"><img src="docs/images/settings.png" alt="Settings" width="280"><br><sub>Settings</sub></td>
  </tr>
</table>

## Install

Requires **macOS 14 Sonoma or later** on Apple Silicon or Intel, and Claude Code installed.

### Homebrew

```bash
brew install --cask yentur/tap/claudedeck
```

### Download

1. Download `ClaudeDeck-<version>.zip` from the [latest release](https://github.com/yentur/ClaudeDeck/releases/latest).
2. Unzip it and move **ClaudeDeck.app** to your **Applications** folder.
3. Open it. The card appears in the top-right corner; press <kbd>⌥</kbd><kbd>⌘</kbd><kbd>K</kbd> to show or hide it.

<details>
<summary><b>“ClaudeDeck can’t be opened” / Gatekeeper warning</b></summary>

<br>

ClaudeDeck is ad-hoc signed but not notarized by Apple, so macOS asks you to confirm the first launch. You only need to do this once per download.

**macOS 15 Sequoia and later**

1. Open ClaudeDeck. When the warning appears, click **Done**.
2. Open **System Settings → Privacy & Security** and scroll down to the **Security** section.
3. Next to “ClaudeDeck was blocked to protect your Mac”, click **Open Anyway** and authenticate.
4. Click **Open Anyway** in the confirmation dialog.

**macOS 14 Sonoma**

Control-click **ClaudeDeck.app** in Finder, choose **Open**, then click **Open** again.

**Terminal (any version)**

```bash
xattr -dr com.apple.quarantine /Applications/ClaudeDeck.app
```

The release zips come with a `.sha256` file, and the [release workflow](.github/workflows/release.yml) builds them from the tagged source on GitHub Actions — or build it yourself (below).

</details>

### Build from source

Only the Xcode **Command Line Tools** are needed (`xcode-select --install`) — no Xcode.

```bash
git clone https://github.com/yentur/ClaudeDeck.git
cd ClaudeDeck
./scripts/build-app.sh --install   # builds, installs to ~/Applications and launches
```

## Usage

| What | How |
|---|---|
| Show / hide the card | <kbd>⌥</kbd><kbd>⌘</kbd><kbd>K</kbd>, or click the ✳︎ menu-bar item (right-click for the menu) |
| Move / resize | Drag the header · drag the bottom-left corner · 📌 snaps back to the top right · Settings → Small / Medium / Large |
| Jump to a session | Click its row |
| Row actions | Hover a row: 📌 pin · ⌄ details · ⏾ sleep · ✕ close. Right-click for more: copy resume command, copy session ID, show folder in Finder |
| Wake a sleeping session | ▶ or double-click the row |
| Filter & search | **All · Working · Idle · Asleep · Recent**; search matches title, folder and last prompt |
| Sort | Menu next to the filters → Activity / Memory / CPU / Last active / Name (pinned sessions stay on top) |
| Bulk sleep | Same menu → **Sleep idle sessions** idle > 1 h / 6 h / 24 h / 3 days, with the memory it frees; confirm to sleep them all |
| Resume an ended session | **Recent** tab → ▶ or double-click |
| Finished-turn alerts | Settings → Notifications: on/off, minimum working time, sound. Click a notification to jump to the session |
| Resource warnings | Settings → Resource warnings: memory limit, sustained CPU limit, optional notifications |
| Menu bar | Shows the number of working sessions, ✓N finished sessions and (optionally) total memory |

## Supported terminals

**Resume** opens woken and recent sessions in the terminal you choose in Settings. **Jump** is what happens when you click a session row.

| Terminal | Resume | Jump |
|---|:---:|---|
| cmux | ✅ | ✅ exact workspace |
| Terminal.app ¹ | ✅ | ✅ exact tab |
| iTerm2 ¹ ² | ✅ | ✅ exact session, matched by tty |
| Ghostty ¹ | ✅ | ✅ tab matched by working directory (Ghostty 1.3+) |
| kitty ³ | ✅ | ✅ exact window |
| WezTerm | ✅ | ✅ exact pane |
| Warp | ✅ | ⚠️ activates the app |
| Alacritty | ✅ | ⚠️ activates the app |
| tmux (inside any terminal) | — | ✅ switches the client to the session's pane |
| VS Code / Cursor terminal | — | ⚠️ activates the app |

¹ Jumping to a tab in Terminal.app, iTerm2 and Ghostty, and resuming in iTerm2 and Ghostty, uses AppleScript, so macOS asks once for **Automation** permission. Resuming in Terminal.app needs no permission.<br>
² iTerm2 support is community-tested and not verified by the author.<br>
³ kitty needs remote control: add `allow_remote_control yes` and `listen_on unix:/tmp/kitty` to `kitty.conf`, then restart kitty.

## How it works

ClaudeDeck only reads what Claude Code already writes, plus the process table. The full tour is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

- **Sessions** come from Claude Code's live-session registry, `~/.claude/sessions/<pid>.json`. Each entry is checked against the process table (pid alive, really `claude`, same start time), so stale files and reused pids are ignored.
- **Titles and details** come from the transcript `~/.claude/projects/<project>/<session-id>.jsonl`. Only the last 1 MB is read, and only when the file changes.
- **Memory and CPU** are sampled every 3 seconds over each session's process tree with `proc_pid_rusage` — the same memory footprint Activity Monitor shows. 100% CPU = one full core.
- **Sleep** first records what `claude --resume` needs (session ID, folder, title, flags), then sends `SIGTERM` to the process tree, followed by `SIGKILL` if it's still alive after 1.5 s.
- **Wake** writes a small self-deleting `.command` script that `cd`s into the project and runs `claude --resume <id>`, and hands it to your terminal.

## Privacy & permissions

- **No network.** ClaudeDeck makes no network requests and has no analytics or telemetry. “Check for Updates…” and “ClaudeDeck on GitHub…” just open a page in your browser.
- **Read-only access to Claude Code data.** Nothing is ever written under `~/.claude`. ClaudeDeck's own state (sleeping sessions, short-lived launch scripts) lives in `~/Library/Application Support/ClaudeDeck`; preferences live in `UserDefaults`.
- **Notifications** (optional) — for finished turns and resource warnings.
- **Automation** (only if you use Terminal.app, iTerm2 or Ghostty) — to focus a session's tab, and to open resumed sessions in iTerm2 or Ghostty.

## FAQ

<details>
<summary><b>“ClaudeDeck can’t be opened” or “ClaudeDeck is damaged”</b></summary>

<br>

The app isn't notarized, so Gatekeeper blocks the first launch of a downloaded copy. Follow the steps under [Install → Gatekeeper warning](#download), or run:

```bash
xattr -dr com.apple.quarantine /Applications/ClaudeDeck.app
```

“Damaged” almost always means the quarantine flag is still set — the command above fixes it. Also make sure the app is in **Applications**: if you run it straight from Downloads, macOS starts it from a temporary read-only location, and ClaudeDeck will ask you to move it first.
</details>

<details>
<summary><b>The Automation prompt appears again after updating</b></summary>

<br>

macOS remembers Automation permission per code signature. Release builds are ad-hoc signed, so every new version has a new identity and macOS asks again. Click **OK** once; if you denied it earlier, re-enable ClaudeDeck under **System Settings → Privacy & Security → Automation**.
</details>

<details>
<summary><b>Does it work on Intel Macs?</b></summary>

<br>

Yes. Release builds are universal binaries (Apple Silicon + Intel).
</details>

<details>
<summary><b>Does it modify my Claude Code data?</b></summary>

<br>

No. ClaudeDeck never writes to `~/.claude`. It reads the session registry and transcripts, and ends sessions only when you ask it to (Close, Sleep or Sleep idle sessions).
</details>

<details>
<summary><b>Where are sleeping sessions stored?</b></summary>

<br>

In `~/Library/Application Support/ClaudeDeck/sleeping.json`: session ID, folder, title, preserved flags and when it went to sleep. The conversation itself stays in Claude Code's own transcript, which is what `claude --resume` loads. You can also resume any session by hand: right-click → **Copy resume command**.
</details>

<details>
<summary><b>Can I use it without cmux?</b></summary>

<br>

Yes. Sessions from any terminal show up in the list. Choose the terminal for resumed sessions in **Settings → Sessions**; see [Supported terminals](#supported-terminals) for what jumping does in each one.
</details>

## Contributing

Bug reports, terminal integrations and translations are very welcome. [CONTRIBUTING.md](CONTRIBUTING.md) explains the build, the fake-session sandbox for developing without touching your real sessions, and the code layout.

## Roadmap ideas

- Configurable global shortcut
- More languages
- Per-project grouping and totals
- Token and cost usage per session from transcripts
- Notarized builds

Have an idea? [Open a feature request](https://github.com/yentur/ClaudeDeck/issues/new/choose).

## License

[MIT](LICENSE) © 2026 Ömer Yentür

---

<sub>ClaudeDeck is an independent open-source project and is not affiliated with, endorsed by, or sponsored by Anthropic. Claude and Claude Code are trademarks of Anthropic, PBC.</sub>
