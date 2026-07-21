# RunHub

A macOS menu bar app for managing your **self-hosted GitHub Actions runners**.

RunHub adopts runner folders you've *already configured* and supervises them as
**in-session child processes** — so their jobs keep access to your unlocked login
Keychain (signing certificates, notarization credentials, provisioning profiles).
Runner status is one click away in the menu bar, with Start/Stop controls and no
terminal required.

## Why in-session supervision?

The usual "always-on" setup installs runners as launchd services (`svc.sh install`).
That detaches them from your logged-in GUI session and, with it, your **unlocked login
Keychain** — which breaks most Xcode/macOS code-signing and notarization jobs.

RunHub takes the opposite approach: it launches each runner's `run.sh` as a child of
the in-session GUI app, so the runner (and the jobs it runs) inherit your Keychain and
GUI session. The menu bar icon reflects this at a glance — **solid** while a runner is
actively running a job, **hollow** otherwise.

## Features

- **Adopt by folder** — point RunHub at a folder that already contains a configured
  runner (`config.sh` + `run.sh` + `.runner`). No GitHub token needed to onboard.
- **Live status** — each runner shows **Stopped / Idle / Busy** plus the current job
  name, derived locally from the runner's own output (no token required).
- **Start / Stop** — per runner, plus Start-all / Stop-all.
- **Auto-resume** — runners that were running when you quit are restarted on next launch;
  ones you explicitly stopped stay stopped.
- **Quit-safe** — quitting stops every runner it started (and warns first if a job is
  mid-run), then tears down the whole process group so nothing is orphaned.
- **Optional `gh` enrichment** — when the [`gh` CLI](https://cli.github.com/) is installed
  and authenticated, RunHub cross-checks authoritative online/busy state for repo- and
  org-level runners. It degrades cleanly to local-only when `gh` is absent.
- **Launch at login** — a toggle (via `SMAppService`) to keep runners up 24/7.
- **Menu bar only** — no Dock icon, no window; just the status item.

## Requirements

- macOS 26.5+
- Xcode 26 (Swift 6 toolchain)
- One or more self-hosted runners **already configured** in their own folders (i.e. you
  have run `./config.sh` for each). See
  [GitHub's docs](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners)
  for setting a runner up.
- Optional: the [`gh` CLI](https://cli.github.com/), authenticated with `gh auth login`,
  for authoritative status enrichment.

## Build & run

```bash
# Build
xcodebuild -project RunHub.xcodeproj -scheme RunHub -destination 'platform=macOS' build

# Run the test suite
xcodebuild test -project RunHub.xcodeproj -scheme RunHub -destination 'platform=macOS'
```

Or open `RunHub.xcodeproj` in Xcode and run the **RunHub** scheme. The app appears in the
menu bar (no Dock icon).

> **Note:** RunHub is **not sandboxed** — it spawns `run.sh`, reads user-selected folders,
> and shells out to `gh`, none of which are compatible with the App Sandbox.

## Usage

1. Launch RunHub — its icon appears in the menu bar.
2. Click the icon and choose **Add Runner**, then select a configured runner folder.
   RunHub validates it and shows it in the list as **Stopped**.
3. Click **Start** on a runner (or **Start All**). The badge moves to **Idle** once it's
   listening, and to **Busy** with the job name while a workflow runs.
4. Toggle **Launch RunHub at login** to keep runners available across restarts.

If a folder's runner is currently installed as a launchd service (a `.service` file is
present), RunHub warns you — run `./svc.sh uninstall` in that folder so RunHub can
supervise it in-session instead.

## How it works

- **Local status is token-free.** RunHub parses the runner's stdout — `Listening for Jobs`
  (idle), `Running job: <name>` (busy), `Job <name> completed with result: <result>`
  (idle) — to derive status and the current job name. `gh` enrichment is purely additive.
- **Process-group ownership.** Each runner is launched in its own process group
  (`setsid`), so on Stop / Quit the entire tree (`Runner.Listener` and any `Runner.Worker`
  children) is signalled and torn down together — no orphaned job processes.
- **Intent vs. shutdown are separate.** Explicit Start/Stop records your *intent*
  (persisted), which is what auto-resume reads. Quitting stops the *processes* without
  changing that intent, so relaunching restores exactly what you left running.

## What RunHub does *not* do

- **Provision runners** — it adopts already-configured folders; it never downloads the
  runner binary or runs `config.sh`.
- **Deregister from GitHub** — "Remove" untracks a runner from RunHub only; it never
  deletes files or removes the runner on GitHub's side.
- **Install runners as launchd services** — that's the exact thing that breaks Keychain
  access.
- Isolation modes, notifications, enterprise-level API enrichment, or Windows/Linux.

## Project layout

```
RunHub/
  RunHubApp.swift              App entry: status item, popover, termination handling
  Models/
    RunnerConfig.swift         Parses .runner; classifies repo / org / enterprise
    RunnerFolder.swift         Validates a folder is a configured runner
    RunnerStatus.swift         Status model + stdout-line parser
  Services/
    RunnerProcess.swift        Spawns/supervises run.sh; process-group teardown
    RunnerStore.swift          Persists adopted runners (Application Support)
    RunnerManager.swift        Coordinator the UI binds to
    GitHubEnrichment.swift     Optional gh-based authoritative status
    LoginItem.swift            Launch-at-login (SMAppService)
  Views/
    MenuContentView.swift      The menu bar panel
    RunnerRowView.swift        One runner row
RunHubTests/                   Swift Testing suites
```
