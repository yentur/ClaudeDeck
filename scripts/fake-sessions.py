#!/usr/bin/env python3
"""Create a sandbox of fake Claude Code sessions for developing (and screenshotting) ClaudeDeck.

Usage:
  scripts/fake-sessions.py up <dir> [--cmux-workspace ID] [--no-load] [--code-dir DIR]
  scripts/fake-sessions.py status <dir> <pid> <busy|idle|shell> [since_seconds_ago]
  scripts/fake-sessions.py down <dir>

`up` starts fake `claude` processes (with realistic memory/CPU unless --no-load), writes their
registry entries, transcripts, a couple of sleeping sessions and a few ended "recent" sessions,
then prints the path of an env file. Nothing under ~/.claude is touched: point the app at the
sandbox with the CLAUDE_DECK_* variables from <dir>/env.sh (see scripts/dev-run.sh).
"""
import datetime
import json
import os
import signal
import subprocess
import sys
import time
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
COMPACT = {"ensure_ascii": False, "separators": (",", ":")}

# (status, project, title, prompt, flags, model, memory MB, cpu %, minutes since last activity, extra env)
LIVE = [
    ("busy", "api-server", "Refactor auth middleware to JWT",
     "Replace the session-cookie auth middleware with JWT validation and keep the old routes working.",
     ["--dangerously-skip-permissions"], "claude-opus-5", 540, 38, 0, {}),
    ("shell", "web-app", "Fix flaky checkout e2e tests",
     "The checkout Playwright tests fail about 1 in 5 runs on CI. Find the race and fix it.",
     [], "claude-sonnet-5", 410, 12, 2, {"FAKE_IGNORE_TERM": "1"}),
    ("idle", "billing-service", "Write Postgres migration for invoices",
     "Add a migration that splits invoices.total into subtotal/tax and backfills existing rows.",
     ["--model", "opus"], "claude-opus-5", 1250, 1, 14, {}),
    ("idle", "web-app", "Add dark mode to settings page",
     "Add a dark mode toggle to the settings page and persist it per user.",
     [], "claude-sonnet-5", 330, 0, 95, {}),
    ("idle", "queue-worker", "Investigate memory leak in queue worker",
     "Memory of the queue worker grows ~200MB/hour in production. Profile it and find the leak.",
     ["--dangerously-skip-permissions"], "claude-opus-5", 290, 0, 60 * 26, {}),
]
# (project, title, hours since slept)
SLEEPING = [
    ("web-app", "Upgrade to React 19", 2),
    ("search", "Benchmark vector search indexes", 30),
]
# (project, title, prompt, hours since last activity, permission mode)
RECENT = [
    ("api-server", "Cache dependencies in GitHub Actions", "Speed up CI by caching the package manager store.", 3, "default"),
    ("docs", "Write onboarding guide for new contributors", "Draft CONTRIBUTING.md with the local dev loop.", 20, "acceptEdits"),
    ("infra", "Tune Nginx rate limits", "Our API gets 429s during deploys; tune the limits.", 50, "bypassPermissions"),
    ("cli", "Prototype shell autocomplete", "Add zsh and fish completions for the CLI.", 100, "default"),
]


def slug(path):
    return "".join(c if c.isascii() and c.isalnum() else "-" for c in path)


def proc_start_utc(pid):
    out = subprocess.run(["ps", "-o", "lstart=", "-p", str(pid)], capture_output=True, text=True,
                         env={**os.environ, "LC_ALL": "C"}).stdout.strip()
    local = datetime.datetime.strptime(" ".join(out.split()), "%a %b %d %H:%M:%S %Y")
    utc = local.astimezone(datetime.timezone.utc)
    return utc.strftime("%a %b ") + str(utc.day) + utc.strftime(" %H:%M:%S %Y")


def write_transcript(projects, cwd, sid, title, prompt, model, permission_mode, modified=None):
    directory = os.path.join(projects, slug(cwd))
    os.makedirs(directory, exist_ok=True)
    path = os.path.join(directory, sid + ".jsonl")
    lines = [
        {"type": "permission-mode", "permissionMode": permission_mode, "sessionId": sid},
        {"type": "user", "cwd": cwd, "entrypoint": "cli", "sessionId": sid,
         "message": {"role": "user", "content": prompt}},
        {"type": "assistant", "sessionId": sid,
         "message": {"model": model, "content": [{"type": "text", "text": "Working on it. " * 200}]}},
        {"type": "ai-title", "aiTitle": title, "sessionId": sid},
    ]
    with open(path, "w") as f:
        f.write("".join(json.dumps(line, **COMPACT) + "\n" for line in lines))
    if modified:
        os.utime(path, (modified, modified))


def up(root, cmux_workspace, load, code_dir=None):
    # --code-dir puts the demo project folders somewhere that reads well in screenshots (e.g. ~/code).
    bin_dir, sessions, projects, state = (os.path.join(root, d) for d in ("bin", "sessions", "projects", "state"))
    code = os.path.abspath(os.path.expanduser(code_dir)) if code_dir else os.path.join(root, "code")
    for d in (bin_dir, sessions, projects, state, code):
        os.makedirs(d, exist_ok=True)

    fake = os.path.join(bin_dir, "claude")
    subprocess.run(["cc", "-O2", "-o", fake, os.path.join(HERE, "fake-claude.c")], check=True)

    resume = os.path.join(bin_dir, "claude-resume.sh")
    with open(resume, "w") as f:
        f.write(f"""#!/bin/bash
# Logs the resume invocation, registers itself like Claude would, then becomes the fake claude.
echo "$(date +%T) $*" >> {root}/resume.log
sid=""
while [ $# -gt 0 ]; do [ "$1" = "--resume" ] && sid="$2"; shift; done
printf '{{"pid":%d,"sessionId":"%s","cwd":"%s","status":"idle","updatedAt":%d000,"name":"x","nameSource":"derived"}}' \\
  $$ "$sid" "$PWD" "$(date +%s)" > {sessions}/$$.json
exec -a claude {fake} --dangerously-skip-permissions
""")
    os.chmod(resume, 0o755)

    now = time.time()
    now_ms = int(now * 1000)
    for i, (status, project, title, prompt, flags, model, mem, cpu, idle_minutes, extra_env) in enumerate(LIVE):
        cwd = os.path.join(code, project)
        os.makedirs(cwd, exist_ok=True)
        env = {"PATH": "/usr/bin:/bin", "HOME": os.environ["HOME"], "TERM_PROGRAM": "Apple_Terminal", **extra_env}
        if load:
            env.update(FAKE_MEM_MB=str(mem), FAKE_CPU=str(cpu))
        if cmux_workspace:
            env["CMUX_WORKSPACE_ID"] = cmux_workspace
            env["CMUX_SURFACE_ID"] = "00000000-0000-0000-0000-00000000000%d" % i
        p = subprocess.Popen([fake, *flags], executable=fake, cwd=cwd, env=env, start_new_session=True,
                             stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        sid = str(uuid.uuid4())
        time.sleep(0.05)
        last = now_ms - idle_minutes * 60 * 1000
        record = {
            "pid": p.pid, "sessionId": sid, "cwd": cwd, "startedAt": last - 40 * 60 * 1000,
            "procStart": proc_start_utc(p.pid), "version": "fake", "kind": "interactive", "entrypoint": "cli",
            "name": "demo-%d" % i, "nameSource": "derived", "status": status,
            "updatedAt": last, "statusUpdatedAt": last - (3 * 60 * 1000 if status != "idle" else 0),
        }
        with open(os.path.join(sessions, "%d.json" % p.pid), "w") as f:
            json.dump(record, f, **COMPACT)
        mode = "bypassPermissions" if "--dangerously-skip-permissions" in flags else "default"
        write_transcript(projects, cwd, sid, title, prompt, model, mode)

    sleeping = []
    for project, title, hours in SLEEPING:
        cwd = os.path.join(code, project)
        os.makedirs(cwd, exist_ok=True)
        slept = datetime.datetime.fromtimestamp(now - hours * 3600, datetime.timezone.utc)
        sleeping.append({"sessionId": str(uuid.uuid4()), "cwd": cwd, "title": title, "flags": [],
                         "sleptAt": slept.strftime("%Y-%m-%dT%H:%M:%SZ")})
    with open(os.path.join(state, "sleeping.json"), "w") as f:
        json.dump(sleeping, f, indent=2)

    for project, title, prompt, hours, mode in RECENT:
        cwd = os.path.join(code, project)
        os.makedirs(cwd, exist_ok=True)
        write_transcript(projects, cwd, str(uuid.uuid4()), title, prompt, "claude-sonnet-5", mode, now - hours * 3600)

    env_file = os.path.join(root, "env.sh")
    with open(env_file, "w") as f:
        f.write(f"""export CLAUDE_DECK_SESSIONS_DIR={sessions}
export CLAUDE_DECK_PROJECTS_DIR={projects}
export CLAUDE_DECK_STATE_DIR={state}
export CLAUDE_DECK_CLAUDE_BIN={resume}
export CLAUDE_DECK_DEFAULTS_SUITE=io.github.yentur.ClaudeDeck.dev
""")
    print(env_file)


def set_status(root, pid, status, since_seconds_ago=0):
    path = os.path.join(root, "sessions", "%s.json" % pid)
    with open(path) as f:
        record = json.load(f)
    now_ms = int(time.time() * 1000)
    record.update(status=status, updatedAt=now_ms, statusUpdatedAt=now_ms - int(since_seconds_ago) * 1000)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(record, f, **COMPACT)
    os.replace(tmp, path)


def down(root):
    sessions = os.path.join(root, "sessions")
    for name in os.listdir(sessions) if os.path.isdir(sessions) else []:
        if name.endswith(".json"):
            try:
                os.kill(int(name[:-5]), signal.SIGKILL)
            except (ValueError, ProcessLookupError):
                pass
    subprocess.run(["pkill", "-9", "-f", os.path.join(root, "bin", "claude")])


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    cmd, root = sys.argv[1], os.path.abspath(sys.argv[2])
    if cmd == "up":
        ws = sys.argv[sys.argv.index("--cmux-workspace") + 1] if "--cmux-workspace" in sys.argv else None
        code_dir = sys.argv[sys.argv.index("--code-dir") + 1] if "--code-dir" in sys.argv else None
        up(root, ws, load="--no-load" not in sys.argv, code_dir=code_dir)
    elif cmd == "status":
        set_status(root, sys.argv[3], sys.argv[4], sys.argv[5] if len(sys.argv) > 5 else 0)
    elif cmd == "down":
        down(root)
    else:
        sys.exit(__doc__)
