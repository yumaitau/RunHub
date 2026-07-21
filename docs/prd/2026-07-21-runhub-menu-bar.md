# RunHub — Menu Bar Manager for Self-Hosted GitHub Runners

Created: 2026-07-21
Author: josh@luongo.com.au
Agent: Claude Code
Category: Feature
Status: Final
Research: Standard

## Problem Statement

Developers who self-host GitHub Actions runners on their Mac have no ambient, native way to answer the everyday question: *"Are my runners up, and is any of them actually running a job right now?"* Today that means opening a terminal to hunt for the `Runner.Listener` process, run `./svc.sh status`, or tail `_diag` logs.

Worse, the common "always-on" answer — installing runners as launchd services via `svc.sh` — **detaches them from the logged-in GUI session and therefore from the user's unlocked login Keychain**. That breaks any job needing signing certificates, provisioning profiles, or notarization credentials (i.e. most Xcode/macOS build jobs).

RunHub solves both: a lightweight macOS **menu bar app** that **adopts already-configured runner folders**, **supervises them as children of the in-session GUI app** (preserving Keychain + GUI-session access), and shows their live status one click away — with start/stop controls and no terminal required.

## Core User Flows

### Flow 1: Add a runner by folder
1. User clicks the RunHub menu bar icon and chooses **Add Runner**.
2. A folder picker opens; the user selects the directory of an existing, already-configured runner.
3. RunHub validates the folder contains a real runner (`config.sh`, `run.sh`, and a `.runner` file present). If not, it rejects the selection with a clear message.
4. RunHub reads `.runner` for the runner name and GitHub URL, adds the runner to the overview list in the **Stopped** state, and persists it to the tracked-folder list.

### Flow 2: Monitor the overview
1. User opens the menu bar dropdown.
2. Each adopted runner shows one row: **runner name**, the **repo/org** it is registered to, a **status badge** (Stopped / Online-Idle / Busy), and — when Busy — the **current job name**.
3. The menu bar glyph reflects aggregate state (how many runners are online / busy) so the user can read status without opening the menu.

### Flow 3: Start / Stop runners
1. From a runner's row, the user clicks **Start** (or **Stop**).
2. On Start, RunHub spawns the runner's `run.sh` as an in-session child process, tracks its PID, and transitions the badge Stopped → Online-Idle → Busy as jobs come and go.
3. **Start-all** / **Stop-all** actions apply the same operation to every adopted runner.

### Flow 4: Quit with a job running
1. User quits RunHub while a runner is mid-job.
2. RunHub warns that quitting will stop an in-progress job and asks for confirmation.
3. On confirm, RunHub stops every runner it started, then exits.

### Flow 5 (optional): `gh` enrichment
1. If the `gh` CLI is installed and authenticated, RunHub cross-checks authoritative online/busy state via `gh api repos/{owner}/{repo}/actions/runners` (repo or org endpoint per the runner's registration). Note: this endpoint returns runner status/busy only — not a job web URL — so the current job *name* still comes from local stdout parsing.
2. If `gh` is absent or unauthenticated, RunHub silently uses local-only status — no error, no blocking.

## Scope

### In Scope
- **Menu bar app** using `MenuBarExtra` with no Dock icon; aggregate status shown in the menu bar glyph.
- **Overview list** — per runner: name, repo/org (from `.runner`), status badge (Stopped / Online-Idle / Busy), and current job name when Busy.
- **Add runner by folder** — folder picker + validation (`config.sh` + `run.sh` + `.runner` present); reads `.runner` for name + GitHub URL; clear rejection of non-runner folders.
- **In-session supervision** — spawn `run.sh` as a child of the GUI app (cwd = runner folder); track PID; derive idle/busy + current job by parsing the runner's own stdout (`Running job:` / `Job … completed`) and/or the `Runner.Worker` child process. Token-free.
- **Controls** — Start / Stop per runner, plus Start-all / Stop-all.
- **Optional `gh` enrichment** — authoritative online/busy state (repo + org runners) when `gh` is authenticated; degrades cleanly to local-only otherwise.
- **Persistence** — the adopted-folder list survives across launches.
- **Quit = stop all** — quitting stops every runner RunHub started, warning first if a job is mid-run.
- **Remove / untrack** — remove a runner from RunHub's list only; does not delete files or deregister from GitHub.

### Explicitly Out of Scope
- **Provisioning new runners** (download binary, run `config.sh`, registration tokens) — RunHub only adopts already-configured folders; provisioning is the existing `omniaura/mac-runner` tool's lane and would duplicate it.
- **Deregistering / deleting runners from GitHub** — untrack is view-only; no destructive, token-scoped GitHub writes in the MVP.
- **Installing runners as launchd services (`svc.sh`)** — directly contradicts the in-session Keychain rationale that motivates the app.
- **Isolation modes (user/container), headless/GUI toggles** — mac-runner features, not core to folder-adoption + monitoring; YAGNI for MVP.
- **Notifications, scheduled/battery-aware pausing, resource-usage graphs** — deferred to later versions.
- **Editing runner config or labels** — RunHub is read-only with respect to runner configuration.
- **Persist-and-reattach after quit** — the chosen model is stop-all-on-quit; reattaching to surviving PIDs is deferred.
- **Windows / Linux** — macOS menu bar app only.

## Technical Context

Lightweight notes for the implementer; `/spec` owns the full design.

- **Scene type:** Replace the scaffold's `WindowGroup` with `MenuBarExtra` (macOS 13+), using `.menuBarExtraStyle(.window)` for the rich list of rows with badges + buttons. Set `LSUIElement` so RunHub runs as an agent app (no Dock icon, no app-switcher entry).
- **Process supervision:** Launch runners with `Process`, cwd set to the runner folder, inheriting the app's login GUI session so the **unlocked login Keychain is available** to jobs. Track PIDs; capture stdout/stderr for the busy/idle + job-name signal. This in-session ownership is the entire reason for the app — do not fall back to `svc.sh`/launchd.
- **Status detection (local, token-free):** Parse the runner's stdout stream — `Listening for Jobs` (idle), `Running job: <name>` (busy), `Job <name> completed with result: <result>`. Optionally corroborate with a `Runner.Worker` child under the runner's `Runner.Listener`.
- **`.runner` parsing:** JSON file in the runner folder providing runner name, `gitHubUrl`, and agent id. Derive `owner/repo` from `gitHubUrl` for the optional API call.
- **`gh` enrichment:** `gh api repos/{owner}/{repo}/actions/runners`; match the local runner to its API record by name. Feature-detect `gh` + auth; never block core flows on it.
- **Auth/secrets:** RunHub stores **no secrets** — `gh` owns its own authentication. No Keychain writes required.
- **Sandboxing:** Runner supervision (spawning shell scripts), reading arbitrary user-chosen folders, and shelling out to `gh` fight the App Sandbox — plan for a **non-sandboxed** app (matching comparable tools). If sandboxing is later required, folder access needs security-scoped bookmarks.
- **Persistence:** Store the adopted-folder list (paths + cached `.runner`-derived metadata) across launches.
- **Prior art:** `omniaura/mac-runner` (Swift 6/SwiftUI menu bar + CLI) is close but uses full provisioning via `gh`; RunHub's differentiator is folder adoption + explicit in-session Keychain preservation.

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Why an app, not a launchd service | Supervise runners as in-session GUI-app children | launchd/`svc.sh` runners lose the unlocked login Keychain + GUI session, breaking signing/notarization jobs. In-session supervision preserves both. |
| Runner onboarding model | Adopt existing, already-configured folders only | Matches the "specify their folders" intent, needs no GitHub token to onboard, and differentiates from `mac-runner`'s full provisioning. |
| Status source | Local process/stdout supervision, with optional `gh` API enrichment | Local path is token-free and yields idle/busy + job name; `gh` adds authoritative online/busy state as optional polish, never a gate. |
| Control surface (MVP) | View + Add + Start/Stop (incl. Start-all/Stop-all) | Start/stop is nearly free once the app owns the processes; deregister/provision are deferred to avoid destructive/token-scoped scope. |
| GitHub auth | Reuse the `gh` CLI | Zero manual token handling, avoids PAT scope confusion, matches how developers already authenticate. |
| Quit behavior | Stop all runners on quit (warn if a job is mid-run) | Simple, predictable supervisor model; 24/7 uptime is achieved via launch-at-login rather than surviving-PID reattachment. |
| Untrack semantics | Remove from RunHub's list only | Non-destructive: does not delete runner files or deregister from GitHub, so no admin-scoped writes are needed in MVP. |
| Sandboxing | Non-sandboxed | Spawning shell scripts, reading arbitrary folders, and calling `gh` are incompatible with the App Sandbox without heavy workarounds. |

## Research Findings

**Sources**
- GitHub Docs — [Configuring the self-hosted runner application as a service](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/configure-the-application), [Monitoring and troubleshooting self-hosted runners](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/monitor-and-troubleshoot), [REST API endpoints for self-hosted runners](https://docs.github.com/en/rest/actions/self-hosted-runners)
- Prior art — [`omniaura/mac-runner`](https://github.com/omniaura/mac-runner) (Swift 6/SwiftUI menu bar app + CLI)
- Apple — [`MenuBarExtra`](https://developer.apple.com/documentation/swiftui/menubarextra)

**Key findings**
- A configured runner folder contains `config.sh`, `run.sh`, `svc.sh`, a `.runner` JSON config (name, `gitHubUrl`, agent id, work folder), `.credentials`, a `_diag/` log dir, and — when installed as a service — a `.service` file naming the launchd label `actions.runner.<org>-<repo>.<name>`.
- Runner liveness/busyness is observable locally: `Runner.Listener` alive = online/connected; a `Runner.Worker` child = a job is running. The runner's stdout also emits explicit `Running job:` / `Job … completed` lines, giving the current job name without any token.
- The REST API (`/repos/{owner}/{repo}/actions/runners`, and the org variant) returns authoritative `online`/`busy` status but requires an admin/`repo`-scoped token; the `gh` CLI supplies this without manual PAT handling.
- `MenuBarExtra` (SwiftUI-native, macOS 13+) is the correct scene type; `.menuBarExtraStyle(.window)` supports a rich interactive panel.
- Prior art (`mac-runner`) confirms the pattern is viable but occupies the *provisioning* niche — leaving folder-adoption + explicit Keychain-preservation as RunHub's distinct position.
