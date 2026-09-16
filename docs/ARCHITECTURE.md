# ClaudeDeck architecture

ClaudeDeck is a Swift package with two targets:

| Target | Kind | Responsibility |
|---|---|---|
| `DeckCore` | library, no AppKit/SwiftUI | Everything that can be unit-tested: reading Claude Code's session registry and transcripts, inspecting processes, measuring memory/CPU, policies (finish detection, warnings, sorting, bulk sleep), resume/focus scripts, the sleep store and process termination. |
| `ClaudeDeck` | executable app | The AppKit + SwiftUI shell: the floating non-activating `NSPanel`, menu-bar item, global hotkey, notifications, settings and all views. |

Tests live in `Tests/DeckCoreTests` (swift-testing). The app target is exercised end-to-end through the fake-session sandbox (see [CONTRIBUTING](../CONTRIBUTING.md)).

## Data sources (all read-only)

| Source | What ClaudeDeck reads |
|---|---|
| `~/.claude/sessions/<pid>.json` | Claude Code's live-session registry: `pid`, `sessionId`, `cwd`, `status` (`busy` / `idle` / `shell`), `updatedAt`, `statusUpdatedAt`, `procStart` (UTC, ctime format), `name` / `nameSource`, `entrypoint`. |
| `~/.claude/projects/<slug>/<sessionId>.jsonl` | Session transcript. `slug` is the launch directory with every non-alphanumeric character replaced by `-`. Only the last 1 MB is read, in one reverse pass, for `ai-title`, `last-prompt`, the newest user `cwd`/`entrypoint`, assistant `model` and `permission-mode`. Results are cached by file modification time. |
| `sysctl(KERN_PROC_*)`, `KERN_PROCARGS2` | Process table (pid → parent, start time), argv and environment of session processes. macOS hides the environment of Apple platform binaries, which does not affect `claude`. |
| `proc_pid_rusage(RUSAGE_INFO_V2)` | `ri_phys_footprint` (the "Memory" column of Activity Monitor) and user+system CPU time, converted from Mach ticks with `mach_timebase_info`. |

Nothing is ever written under `~/.claude`. ClaudeDeck's own state lives in `~/Library/Application Support/ClaudeDeck` (`sleeping.json`, short-lived launch scripts) and `UserDefaults`.

## Snapshot pipeline

Every 3 seconds (and on file-system events in the registry directory) `DeckStore.refresh()` runs `SnapshotBuilder.build()` off the main thread:

1. `RegistryReader` decodes the registry files.
2. `Liveness` keeps entries whose pid is alive, whose argv/executable contains `claude`, and whose kernel start time matches `procStart` (guards against stale files and reused pids).
3. Duplicate session ids keep the most recently updated entry.
4. `ResourceSampler` walks each session's process tree (claude + MCP servers, tools, subprocesses). A session nested inside another session's tree is counted only once. CPU % is the delta of consumed CPU time between consecutive samples, keyed by pid + start time.
5. `TranscriptCache` supplies title, last prompt, model and permission mode; `TitleResolver` picks the label (user rename → AI title → cmux auto-name → folder · short id).

Back on the main actor, `DeckStore.apply` updates the published state, the 200-sample usage history, and runs the policies:

- `FinishDetector`: working (`busy`/`shell`) → idle after at least N seconds → notification + "Done" badge.
- `ResourceWarningEvaluator`: memory above the limit immediately, CPU above the limit when sustained for 60 s.
- `SessionSorter` and `IdleSleepPlanner` for sorting, pins and bulk sleep.

Unchanged snapshots are not re-published, and only membership changes animate, so an idle card stays well under 1 % CPU.

## Sleep and wake

**Sleep** writes a `SleepingSession` (id, cwd, title, preserved flags such as `--dangerously-skip-permissions`, `--model`, `--permission-mode`, `--add-dir`) and then ends the process tree with `SessionKiller`: `SIGTERM`, a 1.5 s grace period (Claude can swallow `SIGTERM`), then `SIGKILL` for the root and any surviving descendants. The pid is re-verified to still be a `claude` process right before signalling.

**Wake** and **Recent → Resume** write a self-deleting `.command` script (`Scripts.resume`) that `cd`s into the project directory and runs `claude --resume <id> <flags>`, and hand it to a terminal. `claude --resume` only finds a session from the directory it was started in, so Recent sessions resolve the directory from the transcript folder slug rather than the last recorded `cwd`.

### cmux trust boundary

cmux's control socket defaults to `socketControlMode: cmuxOnly`, which rejects processes not started inside cmux (a menu-bar app gets "Broken pipe"). ClaudeDeck therefore never needs socket access to open sessions: `open -a cmux script.command` makes cmux run the script itself, and processes started that way are trusted. Jumping to a cmux workspace tries the socket first and otherwise opens a throwaway workspace that runs `cmux workspace select` and closes itself.

## Terminals

`HostResolver` (DeckCore) works out which app a session runs in, in this order: `CMUX_WORKSPACE_ID` → cmux; `TMUX` + `TMUX_PANE` → remembered, and the outer host is still resolved; environment hints (`__CFBundleIdentifier`, `TERM_PROGRAM`, `ITERM_SESSION_ID`, `KITTY_WINDOW_ID`, `WEZTERM_PANE`); and the parent-process chain (`proc_pidpath`) up to the first ancestor inside an `.app`, taking the outermost bundle (VS Code and Cursor run terminals from helper apps nested in the main app). When the chain reaches a known terminal it wins over the hints: it is the only way to tell Cursor from VS Code (both set `TERM_PROGRAM=vscode`) and it ignores variables inherited from whatever launched the terminal. The session's tty comes from `kinfo_proc.kp_eproc.e_tdev`.

**Resume** (`ResumePlanner`, `ResumeExecutor`) writes the same `.command` script for every terminal and tries launch methods in order: `open -a` for Terminal, cmux, WezTerm, kitty and Warp; AppleScript for Ghostty 1.3+ (new window with `initial input`, falling back to `open -a`) and iTerm2 (`write text`); `open -na Alacritty.app --args -e <shell> -lic <script>` for Alacritty. With "Auto" a sleeping session reopens in the terminal it was put to sleep from (`SleepingSession.hostBundleID`); Recent sessions use the default app for `.command` files. Warp has a paste fallback (a `warp://action/new_tab` URL plus the command on the pasteboard).

**Jump** (`FocusPlanner`, `FocusExecutor`): cmux selects the workspace; Terminal and iTerm2 select the tab whose `tty` matches; Ghostty focuses the terminal with the session's working directory; kitty (`kitten @ focus-window`, needs remote control) and WezTerm (`wezterm cli activate-pane`) target the window/pane from the environment; inside tmux the pane is selected in its most recently active client (`list-clients`, `switch-client`) and that client's own terminal is focused the same way. Warp, Alacritty, VS Code and Cursor are only brought to the front.

AppleScripts get every value through `on run argv` (never interpolated) and run via `osascript` with a 60 s timeout, since the first run waits on the Automation prompt; error -1743 shows a banner that opens System Settings → Privacy & Security → Automation.

## UI notes

- `DeckPanel` is a borderless, non-activating `NSPanel`: it can become key (for the search field) without activating the app, and `FirstMouseHostingView` lets the first click hit controls.
- Hover opacity uses an AppKit tracking area with `.activeAlways`, so it works while another app is active.
- The busy "heartbeat" ring is a Core Animation layer animation. A SwiftUI `phaseAnimator` kept a display link running and cost several percent CPU.
- The CPU sparkline is drawn with SwiftUI `Shape`s. `Canvas` re-rasterized into new GPU surfaces on every update and pushed the app's memory footprint from ~40 MB to ~200 MB.
- Numbers inside `Text` are passed with `verbatim:` to avoid locale digit grouping ("pid 6.004").
- All user-visible strings live in `Strings` (English default, Turkish).
