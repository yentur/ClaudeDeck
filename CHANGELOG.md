# Changelog

All notable changes to ClaudeDeck are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-09-16

First public release.

### Added

- Translucent floating card pinned to the top-right corner, toggled with ⌥⌘K or the ✳︎ menu-bar item; drag to move, resize from the bottom-left corner, Small / Medium / Large presets.
- Live list of every running Claude Code CLI session from `~/.claude/sessions`, verified against the process table (stale files and reused pids are ignored).
- Session rows with a status dot (working pulses, shell command, idle), the AI title from the transcript, folder · last active · model, and per-session memory and CPU.
- Usage panel: session count with a working/idle bar and process count, total memory with a share-of-RAM meter, total CPU with a 10-minute sparkline that shows past values on hover.
- Memory and CPU measured over each session's whole process tree (`claude`, MCP servers, tools and subprocesses) with `proc_pid_rusage`; nested sessions are counted once.
- Row hover actions: pin, details, sleep and close; right-click to copy the resume command or session ID, or show the folder in Finder.
- Details view: folder, session ID, pid and process count, usage, uptime, model, permission mode, transcript size and last prompt.
- Click a session to jump to its terminal tab.
- Sleep: closes a session now (`SIGTERM`, then `SIGKILL` after 1.5 s) and records how to resume it, preserving flags such as `--dangerously-skip-permissions`, `--model`, `--permission-mode` and `--add-dir`.
- Wake: resumes a sleeping session with `claude --resume` in its original folder through a self-deleting `.command` script.
- Bulk action "Sleep idle sessions" for sessions idle longer than 1 h, 6 h, 24 h or 3 days, showing the memory it frees.
- Sorting by activity, memory, CPU, last active or name, with pinned sessions on top; filters (All, Working, Idle, Asleep, Recent) and search over title, folder and last prompt.
- Recent tab: ended sessions from `~/.claude/projects` transcripts, resumable with one click in their original project folder with the permission mode restored.
- Finished-turn alerts: macOS notification when a working session goes idle after at least N seconds (click to jump to it), a "Done" badge on the row and a ✓ count in the menu bar; plays a sound when notifications aren't allowed.
- Resource warnings: rows turn amber when a session tree exceeds a memory limit (default 2 GB) or a sustained CPU limit (default 100% for 1 minute), with optional notifications.
- Terminal support for resuming sessions in Terminal.app, iTerm2, Ghostty, Warp, WezTerm, kitty, Alacritty and cmux, and for jumping to the exact tab in cmux, Terminal.app, iTerm2, tmux, kitty and WezTerm (Ghostty 1.3 by working directory; other terminals are activated).
- Settings: English and Turkish, opacity, fully opaque on hover, always on top, compact rows, usage panel, total memory in the menu bar, size presets, notifications, warning limits, terminal for resumed sessions and launch at login.
- "ClaudeDeck on GitHub…" and "Check for Updates…" menu items and a version footer in Settings (they open the browser; the app makes no network requests).
- A banner asking to move the app to Applications when macOS runs it from a translocated location; launch at login is refused until then.
- Privacy: fully local, no network access or telemetry; `~/.claude` is only read, app state lives in `~/Library/Application Support/ClaudeDeck`.
- Universal (Apple Silicon + Intel), ad-hoc signed release builds produced by GitHub Actions, with SHA-256 checksums.

[Unreleased]: https://github.com/yentur/ClaudeDeck/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/yentur/ClaudeDeck/releases/tag/v1.0.0
