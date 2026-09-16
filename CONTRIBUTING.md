# Contributing to ClaudeDeck

Thanks for helping! Bug reports, terminal integrations, translations and small focused pull requests are all welcome. For larger changes, please open an issue first so we can agree on the approach.

## Requirements

- macOS 14 Sonoma or later (Apple Silicon or Intel)
- Swift 6 toolchain — the Xcode **Command Line Tools** are enough (`xcode-select --install`); Xcode is optional
- Python 3 for the development scripts (Pillow only for `make-screenshots.py`)

## Build and test

```bash
swift build                          # debug build of DeckCore + the app
swift test                           # DeckCore unit and flow tests (swift-testing)
./scripts/build-app.sh               # release build → dist/ClaudeDeck.app (ad-hoc signed)
./scripts/build-app.sh --install     # …and install to ~/Applications and launch it
```

`build-app.sh` also takes the flags the release workflow uses; they can be combined in any order:

| Flag | Effect |
|---|---|
| `--universal` | Builds `arm64` and `x86_64` slices and merges them with `lipo` (fails if either is missing) |
| `--version X.Y.Z` | Sets `CFBundleShortVersionString` and `CFBundleVersion` in the built bundle |
| `--zip` | Writes `dist/ClaudeDeck-<version>.zip` and `dist/ClaudeDeck-<version>.zip.sha256` |
| `--install` | Replaces `~/Applications/ClaudeDeck.app` and launches it |

## Developing against fake sessions

You don't need real Claude Code sessions — and you shouldn't point a dev build at them. `scripts/fake-sessions.py` creates a sandbox with fake `claude` processes (realistic memory and CPU), registry entries, transcripts, sleeping sessions and ended "recent" sessions. Nothing under `~/.claude` is touched.

```bash
python3 scripts/fake-sessions.py up /tmp/deck-fake    # start the sandbox, prints its env.sh
./scripts/dev-run.sh /tmp/deck-fake                   # rebuild and run one dev instance against it
```

`dev-run.sh` sources `/tmp/deck-fake/env.sh`, which redirects every path through environment variables, and sets `CLAUDE_DECK_DEBUG=1`:

| Variable | Purpose |
|---|---|
| `CLAUDE_DECK_SESSIONS_DIR` | Replaces `~/.claude/sessions` |
| `CLAUDE_DECK_PROJECTS_DIR` | Replaces `~/.claude/projects` |
| `CLAUDE_DECK_STATE_DIR` | Replaces `~/Library/Application Support/ClaudeDeck` |
| `CLAUDE_DECK_CLAUDE_BIN` | The `claude` executable used by resume scripts (the sandbox uses a fake that logs to `resume.log`) |
| `CLAUDE_DECK_DEFAULTS_SUITE` | Separate `UserDefaults` suite, so your real preferences stay untouched |
| `CLAUDE_DECK_DEBUG` | `1` enables the debug trigger below |

### Driving the app from scripts

With `CLAUDE_DECK_DEBUG=1`, the app listens for debug actions (see `DeckStore.handleDebug`) and runs them through the same code paths as the UI:

```bash
swift scripts/debug-action.swift <action> [value]
```

| Action | Value |
|---|---|
| `sleep`, `close`, `wake`, `resume-recent`, `focus`, `forget` | session ID |
| `request-close`, `request-sleep` | session ID (shows the confirmation strip) |
| `expand`, `pin` | session ID (toggles details / pin) |
| `bulk` | idle threshold in seconds (default `86400`) — opens the bulk-sleep confirmation |
| `bulk-confirm` | — |
| `settings`, `compact`, `usage` | `on` / `off` |
| `filter` | `all` / `busy` / `idle` / `sleeping` / `recent` |
| `sort` | `activity` / `memory` / `cpu` / `recent` / `name` |
| `language` | `en` / `tr` |
| `query` | search text |
| `terminal` | `auto`, `cmux`, `terminalApp`, `iterm2`, `ghostty`, `warp`, `wezterm`, `kitty` or `alacritty` |
| `warp-paste` | `on` / `off` — resume Warp sessions by opening a tab and copying the command instead |
| `min-busy` | seconds a session must work before a finished alert |
| `memory-limit` | GB |
| `resize` | `WIDTHxHEIGHT`, e.g. `380x600` |
| `appearance` | `light` / `dark` / `system` |
| `permission` | — (shows the notification permission state in a banner) |
| `banner` | text |
| `snapshot` | output PNG path (renders the card) |

Session IDs are in the sandbox registry: `cat /tmp/deck-fake/sessions/*.json`.

To test finished-turn alerts, flip a fake session's status (use a pid from the registry file names):

```bash
python3 scripts/fake-sessions.py status /tmp/deck-fake <pid> busy 60   # has been working for 60 s
# wait a few seconds so the app sees the working state, then:
python3 scripts/fake-sessions.py status /tmp/deck-fake <pid> idle      # → "Done" badge + notification
```

When you're done:

```bash
python3 scripts/fake-sessions.py down /tmp/deck-fake
```

Notifications need a real app bundle, so they work with `dev-run.sh` but not with `swift run`.

### Screenshots

README images are made from card snapshots of the fake sandbox, then composited onto a desktop-style background:

```bash
mkdir -p /tmp/deck-shots
swift scripts/debug-action.swift appearance dark
swift scripts/debug-action.swift resize 380x600
swift scripts/debug-action.swift snapshot /tmp/deck-shots/main.png
swift scripts/debug-action.swift expand <session-id>
swift scripts/debug-action.swift snapshot /tmp/deck-shots/details.png
swift scripts/debug-action.swift expand <session-id>
swift scripts/debug-action.swift filter recent
swift scripts/debug-action.swift snapshot /tmp/deck-shots/recent.png
swift scripts/debug-action.swift filter all
swift scripts/debug-action.swift settings on
swift scripts/debug-action.swift snapshot /tmp/deck-shots/settings.png
swift scripts/debug-action.swift settings off

python3 scripts/make-screenshots.py /tmp/deck-shots          # writes docs/images/
```

`make-screenshots.py` expects `main.png`, `details.png`, `recent.png` and `settings.png` in the input directory (missing ones are skipped) and writes `docs/images/hero.png`, `details.png`, `recent.png`, `settings.png` and `social-preview.png` (1280×640, for the GitHub social preview). Run `python3 scripts/make-screenshots.py --help` for options such as `--out` and `--scale`.

## Code layout

| Path | What lives there |
|---|---|
| `Sources/DeckCore` | All logic that can be unit-tested, **without AppKit or SwiftUI**: registry and transcript reading, process inspection (`sysctl`, `libproc`), memory/CPU sampling, policies (finish detection, warnings, sorting, bulk sleep), resume/focus scripts and launchers, the sleep store, process termination. |
| `Sources/ClaudeDeck` | The AppKit + SwiftUI app: floating `NSPanel`, menu-bar item, global hotkey, notifications, settings and views. `Strings.swift` holds every user-visible string. |
| `Tests/DeckCoreTests` | swift-testing tests for `DeckCore`, including end-to-end sleep → wake flows with real processes. |
| `scripts/` | Build, release, fake-session sandbox, debug actions, icon and screenshot tooling. |
| `docs/ARCHITECTURE.md` | How the pieces fit together — read this before larger changes. |

## Guidelines

- **Strings:** every user-visible string goes through `Strings` in `Sources/ClaudeDeck/Strings.swift`, with both English and Turkish (`t("English", "Türkçe")`). If you can't write Turkish, add your best guess and mention it in the PR.
- **Keep `DeckCore` AppKit-free and tested.** New logic belongs in `DeckCore` with tests whenever it doesn't need UI; the app target should stay a thin shell.
- **No network.** ClaudeDeck makes no network requests and has no telemetry. Opening a URL in the user's browser is fine; fetching one is not.
- **Never write under `~/.claude`.** Claude Code's data is read-only for ClaudeDeck. App state goes to the state directory (`DeckPaths.stateDir`).
- **Stay light.** The app idles at ~0.5–1% CPU and ~40–60 MB. Watch out for SwiftUI animations that keep a display link running, `Canvas` re-rasterizing, and re-publishing unchanged state (see "UI notes" in the architecture doc).
- **No personal data** in code, tests, fixtures or screenshots: use generic paths like `~/code/api-server` and generated session IDs.
- Match the existing style: small types, `// MARK:` sections, comments that explain *why*.

## Pull request checklist

- [ ] `swift build` has no new warnings and `swift test` passes
- [ ] New logic is in `DeckCore` with tests (or the PR explains why not)
- [ ] New strings are in `Strings.swift` in English and Turkish
- [ ] UI changes were tried in the fake-session sandbox, light and dark; screenshots are in the PR
- [ ] No network access, no writes under `~/.claude`, no personal data
- [ ] `CHANGELOG.md` has an entry under `## [Unreleased]` for user-visible changes

## How releases work

Releases are built by GitHub Actions from a version tag.

1. Move the `## [Unreleased]` entries in `CHANGELOG.md` into a new `## [X.Y.Z] - YYYY-MM-DD` section and commit.
2. Tag and push:
   ```bash
   git tag -a vX.Y.Z -m "ClaudeDeck X.Y.Z"
   git push origin vX.Y.Z
   ```
3. [`.github/workflows/release.yml`](.github/workflows/release.yml) runs the tests, builds a universal, ad-hoc signed app with `./scripts/build-app.sh --universal --version X.Y.Z --zip`, and creates the GitHub release with `ClaudeDeck-X.Y.Z.zip`, its `.sha256`, and the matching `CHANGELOG.md` section as release notes.
4. Update the Homebrew cask in the `yentur/homebrew-tap` repository (`Casks/claudedeck.rb`) with the new `version` and the `sha256` from the release's `.sha256` file.

If Actions is unavailable, `GH_TOKEN=<token> ./scripts/release.sh X.Y.Z` does the same from a clean local checkout whose commit is already pushed: it runs the tests, builds the universal zip, creates a **draft** release with the changelog notes and uploads the assets through the GitHub REST API, then creates the annotated tag locally. It never pushes — it prints the commands to push the tag and publish the draft. (The release starts as a draft because publishing it would make GitHub create the tag itself, and your annotated tag push would then be rejected.)

For reference, a cask for the tap looks like this:

```ruby
cask "claudedeck" do
  version "1.0.0"
  sha256 "<contents of ClaudeDeck-1.0.0.zip.sha256>"

  url "https://github.com/yentur/ClaudeDeck/releases/download/v#{version}/ClaudeDeck-#{version}.zip"
  name "ClaudeDeck"
  desc "Floating card to monitor, sleep and resume Claude Code sessions"
  homepage "https://github.com/yentur/ClaudeDeck"

  depends_on macos: ">= :sonoma"

  app "ClaudeDeck.app"

  zap trash: [
    "~/Library/Application Support/ClaudeDeck",
    "~/Library/LaunchAgents/io.github.yentur.ClaudeDeck.plist",
    "~/Library/Preferences/io.github.yentur.ClaudeDeck.plist",
  ]
end
```

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
