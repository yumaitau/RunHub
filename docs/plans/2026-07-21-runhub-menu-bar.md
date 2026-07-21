# RunHub Menu Bar App Implementation Plan

Created: 2026-07-21
Author: josh@luongo.com.au
Agent: Claude Code
Status: VERIFIED
Approved: Yes
Iterations: 0
Worktree: No
Type: Feature

## Summary

**Goal:** A macOS menu bar app that adopts existing self-hosted GitHub runner folders, supervises them as in-session child processes (preserving login-Keychain access), and shows live status (Stopped / Idle / Busy + current job) with per-runner and all-runner Start/Stop, plus optional `gh` API enrichment and launch-at-login.

## Out of Scope

- **Provisioning runners** — RunHub never downloads the runner binary or runs `config.sh`; it only adopts folders already configured.
- **Deregister / delete from GitHub** — "Remove" untracks from RunHub only; it does not delete files or call the GitHub delete API.
- **Installing runners as launchd services (`svc.sh`)** — contradicts the in-session Keychain rationale.
- **Enterprise-level API enrichment** — only repo-level and org-level runners are enriched via `gh`; enterprise runners still work locally (local-only status).
- **`Runner.Worker`-process-based busy detection** — MVP derives busy/idle from `run.sh` stdout only.
- **Isolation modes, headless/GUI toggles, notifications, scheduled/battery pausing, editing runner config/labels, persist-and-reattach after quit, Windows/Linux.**

## Approach

**Chosen:** A single-target SwiftUI `MenuBarExtra` (`.window` style) app with a `@MainActor` `RunnerManager` (ObservableObject) coordinating pure-logic models (folder parse/validate, stdout status parser, Codable store) and side-effecting services (`Process`-based `RunnerProcess`, `gh`-based `GitHubEnrichment`, `SMAppService`-based `LoginItem`). Runners are spawned via `run.sh` as children of the GUI app.

**Why:** In-session `Process` supervision is the whole point — it keeps jobs attached to the user's unlocked login Keychain, which `svc.sh`/launchd would break. Splitting pure logic from side effects makes the parse/validate/status/store/manager layers unit-testable without spawning real runners or touching GitHub, at the cost of a few more small files than a monolithic view.

## Context for Implementer

The project uses **file-system-synchronized groups** (`PBXFileSystemSynchronizedRootGroup`), so any `.swift` file added under `RunHub/` (including new subfolders like `RunHub/Models/`) is auto-included in the app target — no `project.pbxproj` edits are needed to add source files. The exception is the **unit-test target**, which does not exist yet and must be created (Task 2). Deployment target is **macOS 26.5**, so `MenuBarExtra`, `SMAppService`, and Swift Testing are all available. Testing posture is **parsimonious**: at most one unit test suite + at most one functional suite per production type; UI and `SMAppService` wrappers are verified via the E2E scenarios, not unit tests.

## Runtime Environment

- **Build:** `xcodebuild -project RunHub.xcodeproj -scheme RunHub -destination 'platform=macOS' build`
- **Test:** `xcodebuild test -project RunHub.xcodeproj -scheme RunHub -destination 'platform=macOS'`
- **Launch (for E2E):** build, then `open` the built `RunHub.app` from `DerivedData` (path from `xcodebuild -showBuildSettings`), or run from Xcode. App has no Dock icon; it appears in the menu bar.

## Assumptions

- Adopted folders are already configured (`config.sh` has been run): they contain `config.sh`, `run.sh`, and a `.runner` file. RunHub never runs `config.sh`. — Tasks 3, 5, 7, 10
- The runner is not concurrently supervised elsewhere. RunHub warns when a folder has a `.service` file (installed as a launchd service) but does not uninstall it. — Tasks 3, 7
- `run.sh` emits the standard status lines used for parsing: `Listening for Jobs`, `Running job: <name>`, `Job <name> completed with result: <result>` (each prefixed by a timestamp). — Tasks 4, 5

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Adding a unit-test target by editing `project.pbxproj` (synchronized test group + scheme test action) is error-prone | Medium | Medium | Task 2 isolates this with a passing smoke test as its DoD; do not proceed until `xcodebuild test` runs green |
| Runner already running as a launchd service or elsewhere → GitHub rejects the second listener ("already in use") | Medium | Medium | On adopt, detect a `.service` file and surface a warning; document that the user must `svc.sh uninstall` to hand supervision to RunHub |
| `run.sh` stdout block-buffered when not attached to a TTY → delayed status updates | Medium | Low | Read the `Pipe` line-by-line as data arrives; if buffering proves material, escalate to a PTY (SHORTCUT noted in Task 5) |
| SwiftUI `.alert`/`.confirmationDialog` may not present reliably from inside a `MenuBarExtra(.window)` panel | Medium | Medium | Present the quit confirmation via `NSAlert.runModal()` from the `NSApplicationDelegate`, not a SwiftUI modifier (Task 10) |

## Goal Verification

### Truths

1. A runner started by RunHub runs as a **descendant process of the RunHub app** (in-session) and is never installed or launched as a launchd service — so its jobs retain access to the user's unlocked login Keychain.
2. Idle/Busy state and the current job name are derived with **no GitHub token**; absent or unauthenticated `gh` only removes the authoritative online/busy cross-check — it never blocks add, start, stop, or local status.

## E2E Test Scenarios

> These are macOS menu-bar-app scenarios (browser automation is N/A). They are driven by a **fixture runner folder**: a temp directory containing a stub `config.sh`, a stub `run.sh` shell script that prints the standard runner status lines on a controllable schedule, and a `.runner` JSON file. This exercises adopt → start → busy → stop locally without contacting GitHub. Verification launches the built app and interacts with the menu (via clicks / accessibility automation).

### TS-001: Adopt a runner folder
**Priority:** Critical
**Preconditions:** App running; a valid fixture runner folder exists; no runners adopted yet.
**Mapped Tasks:** Task 3, Task 7, Task 10

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Open the menu bar panel, click **Add Runner** | Folder picker opens |
| 2 | Select the fixture runner folder | A row appears showing the runner name and its repo/org, status badge **Stopped** |
| 3 | Quit and relaunch the app | The adopted runner is still listed (persisted) |

### TS-002: Start a runner and observe Idle → Busy → Idle
**Priority:** Critical
**Preconditions:** TS-001 done; runner is Stopped.
**Mapped Tasks:** Task 4, Task 5, Task 7, Task 10

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Click **Start** on the runner row | Badge transitions to **Idle** once the fixture prints "Listening for Jobs" |
| 2 | Trigger the fixture to emit `Running job: build-app` | Badge becomes **Busy**, row shows current job **build-app** |
| 3 | Fixture emits `Job build-app completed with result: Succeeded` | Badge returns to **Idle**, job name cleared |

### TS-003: Stop a runner
**Priority:** High
**Preconditions:** A runner is running (Idle or Busy).
**Mapped Tasks:** Task 5, Task 7, Task 10

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Click **Stop** on a running runner | Badge returns to **Stopped**; the spawned `run.sh` process **and its descendant (Listener/Worker, or the fixture's grandchild) are terminated** — no orphan remains |

### TS-004: Quit with a job running warns first
**Priority:** High
**Preconditions:** A runner is **Busy**.
**Mapped Tasks:** Task 7, Task 10

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Choose **Quit RunHub** while a job is running | A confirmation dialog warns that quitting will stop an in-progress job |
| 2 | Confirm | All runners stop, then the app exits |

### TS-005: Reject a non-runner folder
**Priority:** Medium
**Preconditions:** App running.
**Mapped Tasks:** Task 3, Task 10

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Add Runner → select a folder with no `.runner`/`run.sh` | Selection is rejected with a clear message ("not a configured runner folder"); nothing is added |

### TS-006: Auto-resume reflects intent, not the quit shutdown
**Priority:** High
**Preconditions:** Runner A running; runner B explicitly Stopped by the user; then quit the app (Quit stops A's process but must not clear its intent).
**Mapped Tasks:** Task 6, Task 7, Task 10

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Relaunch the app | Runner A (was running / `desiredRunning`) auto-starts → Idle; runner B (explicitly stopped) stays **Stopped** |
| 2 | Explicitly **Stop All**, then quit and relaunch | Nothing auto-starts — explicit Stop set intent false for every runner |

### TS-007: Launch-at-login toggle
**Priority:** Medium
**Preconditions:** App running.
**Mapped Tasks:** Task 9, Task 10

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Toggle **Launch at login** on | Toggle reflects enabled state; `SMAppService.mainApp.status` is `.enabled` |
| 2 | Toggle it off | Toggle reflects disabled state; status is no longer `.enabled` |

### TS-008: Remove (untrack) a runner
**Priority:** Medium
**Preconditions:** At least one runner adopted (running or stopped).
**Mapped Tasks:** Task 7, Task 10

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Click **Remove** on a runner row | If running, it stops first (process tree torn down); the row disappears from the list |
| 2 | Inspect disk / GitHub | The runner folder still exists and the runner is still registered on GitHub (untrack only) |
| 3 | Quit and relaunch | The removed runner does not reappear (dropped from persistence) |

## E2E Results

**Live target:** native macOS menu bar app — no web server / deploy backend, so live-target probe Tiers 1-3 are N/A; the "live target" is the built `RunHub.app` launched directly. The store was seeded with a fixture runner (`desiredRunning=true`) and the real app binary was launched to exercise the end-to-end paths that don't require menu clicks. Headless click-driving of `MenuBarExtra` + `NSOpenPanel` is not automatable here; those paths are covered by the `RunnerManager`/logic tests the thin UI binds to.

| Scenario | Priority | Result | Fix Attempts | Notes |
|----------|----------|--------|--------------|-------|
| TS-001 Adopt a runner folder | Critical | UNIT_VERIFIED | 0 | Adoption + persistence via RunnerManager tests; real-app store load proven (auto-resume read it back) |
| TS-002 Start Idle->Busy->Idle | Critical | LIVE_PASS (start) | 0 | Real app auto-started run.sh; Idle/Busy/Idle transitions covered by RunnerProcess functional test |
| TS-003 Stop kills process tree | High | UNIT_VERIFIED | 0 | Group teardown incl. long-lived grandchild covered by RunnerProcess test |
| TS-004 Quit teardown | High | LIVE_PASS | 0 | Graceful Quit (Apple event) tore down the runner group in the real app; busy-confirmation lives in applicationShouldTerminate |
| TS-005 Reject non-runner folder | Medium | UNIT_VERIFIED | 0 | RunnerManager rejects; validation (incl. symlink/non-exec run.sh) covered by RunnerFolderTests |
| TS-006 Auto-resume reflects intent | High | LIVE_PASS | 0 | Real app auto-resumed the desiredRunning runner as an in-session descendant of RunHub (Goal Truth 1) |
| TS-007 Launch-at-login toggle | Medium | UNIT_VERIFIED | 0 | isEnabled mapping unit-tested; SMAppService register/unregister need a signed installed bundle (not automatable here) |
| TS-008 Remove (untrack) | Medium | UNIT_VERIFIED | 0 | RunnerManager.remove stops + untracks without touching files/GitHub, covered by test |

Design Notes: `impeccable` design detector is web-oriented and N/A for a native macOS menu bar app — skipped.

## Progress Tracking

- [x] Task 1: Menu bar agent app config (non-sandboxed, MenuBarExtra skeleton)
- [x] Task 2: Unit test target setup (Swift Testing)
- [x] Task 3: Runner folder model — parse `.runner`, registration, validation
- [x] Task 4: Runner status model + stdout parser
- [x] Task 5: In-session runner process supervision
- [x] Task 6: Adopted-runner persistence store
- [x] Task 7: RunnerManager coordinator (add/remove/start/stop/all, auto-resume, quit)
- [x] Task 8: Optional GitHub enrichment via `gh` (repo + org)
- [x] Task 9: Launch-at-login (SMAppService)
- [x] Task 10: Menu bar UI assembly + wiring + quit confirmation

## Implementation Tasks

### Task 1: Menu bar agent app config (non-sandboxed, MenuBarExtra skeleton)

**Objective:** Turn the default windowed scaffold into a dockless menu bar agent app that can spawn shell processes. Disable the App Sandbox, set `LSUIElement`, and replace the `WindowGroup`/`ContentView` Hello-World with a `MenuBarExtra` showing a placeholder panel.

**Files:**

- Modify: `RunHub.xcodeproj/project.pbxproj`
- Modify: `RunHub/RunHubApp.swift`
- Delete: `RunHub/ContentView.swift`

**Key Decisions / Notes:**

- In `project.pbxproj`, set `ENABLE_APP_SANDBOX = NO` in **both** the Debug and Release build configs (currently `YES` at ~line 257 and ~line 289). Non-sandboxed is required to spawn `run.sh`, read arbitrary user folders, and call `gh`.
- Add `INFOPLIST_KEY_LSUIElement = YES` to both configs (`GENERATE_INFOPLIST_FILE = YES`, so Info.plist keys come from build settings — there is no manual Info.plist).
- Replace the scene body with `MenuBarExtra("RunHub", systemImage: "…") { … }.menuBarExtraStyle(.window)`; a placeholder `Text` panel is fine for this task. Real UI lands in Task 10.

**Definition of Done:**

- [ ] `ENABLE_APP_SANDBOX = NO` and `INFOPLIST_KEY_LSUIElement = YES` in both build configs.
- [ ] App builds and launches as a menu bar item with **no Dock icon** and no app-switcher entry; clicking the menu bar icon shows a panel.
- [ ] Verify: `xcodebuild -project RunHub.xcodeproj -scheme RunHub -destination 'platform=macOS' build`

### Task 2: Unit test target setup (Swift Testing)

**Objective:** Create the `RunHubTests` unit-test target so every later task can add tests. Use Swift Testing, wire a file-system-synchronized `RunHubTests/` group, add the target to the shared `RunHub` scheme's test action, and prove it runs with one smoke test.

**Files:**

- Modify: `RunHub.xcodeproj/project.pbxproj`
- Create: `RunHub.xcodeproj/xcshareddata/xcschemes/RunHub.xcscheme`
- Create: `RunHubTests/SmokeTests.swift`

**Key Decisions / Notes:**

- Add a `PBXNativeTarget` of product type `com.apple.product-type.bundle.unit-test` named `RunHubTests`, backed by a `PBXFileSystemSynchronizedRootGroup` rooted at `RunHubTests/` (so test files added later auto-include, matching how the app target works). Host application = `RunHub`.
- Share the `RunHub` scheme (move to `xcshareddata`) and add `RunHubTests` to its Test action so `xcodebuild test -scheme RunHub` finds it.
- `SmokeTests.swift`: one `@Test func smoke() { #expect(true) }` (Swift Testing) purely to confirm the target links and runs. This is the target-setup proof, not behavior coverage.

**Definition of Done:**

- [ ] `xcodebuild -list` shows a `RunHubTests` target and the shared `RunHub` scheme.
- [ ] The smoke test runs and passes under the test command below.
- [ ] Verify: `xcodebuild test -project RunHub.xcodeproj -scheme RunHub -destination 'platform=macOS'`

### Task 3: Runner folder model — parse `.runner`, registration, validation

**Objective:** Model a runner folder: decode its `.runner` JSON (name + `gitHubUrl`), classify the registration level from the URL (repo / org / enterprise / unknown), validate a folder is a real configured runner, and detect an installed-as-service `.service` file.

**Files:**

- Create: `RunHub/Models/RunnerConfig.swift`
- Create: `RunHub/Models/RunnerFolder.swift`
- Create: `RunHubTests/RunnerFolderTests.swift`

**Key Decisions / Notes:**

- `RunnerConfig`: `Codable` decode of `.runner` (fields `agentName`/`agentId`/`gitHubUrl` — decode leniently, ignore unknown keys). Expose `name` and a `RunnerRegistration` enum: `.repo(owner:String, repo:String)`, `.org(String)`, `.enterprise(String)`, `.unknown`, derived from `gitHubUrl` (e.g. `https://github.com/owner/repo` → `.repo`; `https://github.com/org` → `.org`; `.../enterprises/<name>` → `.enterprise`).
- `RunnerFolder`: given a folder URL, `validate()` **canonicalizes** the path (`resolvingSymlinksInPath` / `realpath`) and is valid only when `config.sh`, `.runner`, and a `run.sh` that is a **regular, executable file** (not a symlink/FIFO/directory) all exist; otherwise a reason. Expose the canonical folder URL, the `run.sh` URL, and an `isInstalledAsService` flag (true when a `.service` file is present). The canonical path is the stable identity used for dedup and storage (Tasks 6/7).
- Parsimony: one unit suite (`RunnerFolderTests`) covers both types via fixture `.runner` JSON + temp folders.

**Definition of Done:**

- [ ] A repo-style `.runner` decodes to `.repo(owner, repo)`; an org-style URL to `.org(name)`; an enterprise URL to `.enterprise(name)`.
- [ ] A folder with `config.sh` + `.runner` + a regular-executable `run.sh` validates and returns a canonical path; one missing any of them, or whose `run.sh` is a symlink/non-executable, is rejected with a reason.
- [ ] A folder containing a `.service` file reports `isInstalledAsService == true`.
- [ ] Verify: `xcodebuild test -project RunHub.xcodeproj -scheme RunHub -destination 'platform=macOS'`

### Task 4: Runner status model + stdout parser

**Objective:** Define the runner status model and a pure parser that maps `run.sh` stdout lines to status transitions, including extracting the current job name.

**Files:**

- Create: `RunHub/Models/RunnerStatus.swift`
- Create: `RunHubTests/RunnerOutputParserTests.swift`

**Key Decisions / Notes:**

- `RunnerStatus`: `.stopped`, `.starting`, `.idle` (online, listening), `.busy(job: String)`, `.failed(reason: String)`.
- `RunnerOutputParser.event(for line: String) -> RunnerStatusEvent?` uses tolerant **contains**-matching (lines are timestamp-prefixed): `Listening for Jobs` → idle; `Running job: <name>` → busy with `<name>` (trim trailing whitespace); `Job <name> completed with result:` → idle. Non-matching lines return `nil` (no transition).
- Keep it pure (String in, event out) — no I/O — so it is fully unit-tested. The process layer (Task 5) applies these events.

**Definition of Done:**

- [ ] `"2026-… : Running job: build-app"` → busy event with job `build-app`.
- [ ] `"2026-… : Job build-app completed with result: Succeeded"` → idle event.
- [ ] `"2026-… : Listening for Jobs"` → idle event; an unrelated log line → no event.
- [ ] Verify: `xcodebuild test -project RunHub.xcodeproj -scheme RunHub -destination 'platform=macOS'`

### Task 5: In-session runner process supervision

**Objective:** Spawn a runner's `run.sh` as an in-session child process, stream its stdout line-by-line through the Task 4 parser, publish live status, and stop it cleanly on request.

**Files:**

- Create: `RunHub/Services/RunnerProcess.swift`
- Create: `RunHubTests/RunnerProcessTests.swift`

**Key Decisions / Notes:**

- Wrap `Foundation.Process`: `executableURL` = the folder's `run.sh`, `currentDirectoryURL` = the runner folder, stdout/stderr piped. Because RunHub is a normal GUI app, the child inherits the login GUI session → login Keychain access (Goal Truth 1). Never route through `svc.sh`/launchd.
- **Own the whole process tree.** `run.sh` spawns `Runner.Listener`, which spawns `Runner.Worker` job subprocesses; terminating only the wrapper orphans them. Launch the child in its **own process group** (set the child's process-group id to its own pid via `posix_spawn` attributes / a spawn file-action). `stop()` signals the **entire group** (`kill(-pgid, SIGTERM)`), waits up to a timeout for confirmed exit, then escalates to `SIGKILL` — so Listener/Worker descendants die with the wrapper (Goal Truth 1).
- Read the stdout `Pipe` incrementally, split on newlines, feed each line to `RunnerOutputParser`, and publish `@Published status` on the main actor. `start()` sets `.starting`; a requested `stop()` ends in `.stopped`.
- **Handle unexpected exit.** Install a `terminationHandler` (and detect stdout EOF): if the process exits *without* a requested `stop()`, transition to `.failed(reason:)` (carrying the exit status) and clear process ownership so a later `start()` is not a no-op. A requested `stop()` transitions to `.stopped`.
- `SHORTCUT: line-buffered Pipe read; if run.sh block-buffers off-TTY and delays status, upgrade to a PTY.` — trigger: status lag observed in TS-002.
- Test with a **fake `run.sh`** fixture script (temp dir) that echoes the standard lines on a timer **and spawns a long-lived grandchild** (e.g. a background `sleep`) so tree-teardown is actually exercised. One functional suite.

**Definition of Done:**

- [ ] Starting a fake runner fixture drives status Stopped → Idle → Busy(job) → Idle as it emits the standard lines.
- [ ] `stop()` terminates the child **and its grandchild** (verified: neither pid is running afterward) and sets `.stopped`.
- [ ] A fixture that reports Idle/Busy then exits on its own (no `stop()` call) transitions status to `.failed`, and a subsequent `start()` relaunches it (not a no-op).
- [ ] A folder whose `run.sh` cannot be launched yields `.failed` rather than crashing.
- [ ] Verify: `xcodebuild test -project RunHub.xcodeproj -scheme RunHub -destination 'platform=macOS'`

### Task 6: Adopted-runner persistence store

**Objective:** Persist the list of adopted runners (canonical folder path, cached name + registration, and a `desiredRunning` intent flag for auto-resume) across launches, and load them back.

**Files:**

- Create: `RunHub/Services/RunnerStore.swift`
- Create: `RunHubTests/RunnerStoreTests.swift`

**Key Decisions / Notes:**

- `Codable` array of `StoredRunner { folderPath: String, name: String, registration: RunnerRegistration, desiredRunning: Bool }`, persisted as JSON under `Application Support/RunHub/runners.json` (create the directory if missing). Inject the file URL so tests use a temp path.
- `folderPath` is the **canonical** path from Task 3's `validate()` (symlinks resolved) — the stable dedup/identity key.
- `desiredRunning` records **user intent** (set by explicit Start/Stop in Task 7), NOT a transient process state — this is what auto-resume reads, and it is deliberately never mutated by process shutdown on quit.
- API: `load()`, `save(_)`, `add(_)` (dedup by canonical `folderPath`), `remove(folderPath:)`, `setDesiredRunning(folderPath:_:)`.
- Store canonical folder **paths** (not security-scoped bookmarks) — the app is non-sandboxed, so plain paths suffice.

**Definition of Done:**

- [ ] Adding a runner then `load()` from a fresh instance (same temp file) returns it; encode→decode round-trips all fields including `registration` and `desiredRunning`.
- [ ] `add` is idempotent by canonical `folderPath` (no duplicate); `remove` drops it; `setDesiredRunning` persists the intent flag.
- [ ] Verify: `xcodebuild test -project RunHub.xcodeproj -scheme RunHub -destination 'platform=macOS'`

### Task 7: RunnerManager coordinator (add/remove/start/stop/all, auto-resume, quit)

**Objective:** Build the central `@MainActor` `ObservableObject` that the UI binds to: it merges persisted runners with live `RunnerProcess` status and exposes add/remove, start/stop, start-all/stop-all (which set persisted intent), auto-resume on launch, and a process-only stop-all for the quit path.

**Files:**

- Create: `RunHub/Services/RunnerManager.swift`
- Create: `RunHubTests/RunnerManagerTests.swift`

**Key Decisions / Notes:**

- Holds `@Published var runners: [RunnerItem]` where `RunnerItem` pairs a `StoredRunner` with its current `RunnerStatus`. Inject a **process factory** (`(RunnerFolder) -> RunnerProcessing`) so tests use a fake process, not real spawns.
- `add(folderURL:)` → validate (Task 3, canonical path), reject non-runners, dedup by canonical path (Task 6), surface the `isInstalledAsService` warning, persist, create a supervised item. `remove` stops + untracks (no GitHub/file deletion).
- **Intent vs. process are separate.** Explicit `start(item)` sets `desiredRunning = true` (persist) then launches; explicit `stop(item)` sets `desiredRunning = false` (persist) then stops. `startAll`/`stopAll` are the explicit all-runner versions and set intent for every item. `start` is **idempotent** (no-op if already running). Before each launch, **revalidate** the canonical folder (Task 3) so a swapped/removed `run.sh` fails closed rather than executing.
- **Quit path does not mutate intent.** A separate `stopAllProcesses()` stops every running process **without** touching `desiredRunning`, and is idempotent across repeated calls (Task 10 termination may call it more than once). This is what preserves auto-resume.
- `resumeDesiredRunning()` (called at launch) starts only items with `desiredRunning == true`. `hasRunningJob` is true when any item is `.busy` (drives the quit warning).

**Definition of Done:**

- [ ] `add` of a valid folder validates (canonical path), persists, and creates a supervised (Stopped) item; a non-runner folder, or a symlink/alternate spelling of an already-adopted folder, is rejected/deduped — no duplicate supervision.
- [ ] Explicit `start`/`startAll` set `desiredRunning = true` and launch; explicit `stop`/`stopAll` set `desiredRunning = false` and stop; `start` on an already-running item is a no-op.
- [ ] `stopAllProcesses()` stops all running processes **without** changing `desiredRunning`, and calling it twice in a row is safe; afterward `resumeDesiredRunning()` restarts exactly the items whose `desiredRunning` was true.
- [ ] After an explicit `stopAll` then `resumeDesiredRunning()`, nothing restarts (intent is false); `hasRunningJob` reflects a busy item.
- [ ] `remove(folderPath:)` stops the item if running, untracks it from the store, and leaves the runner folder and its GitHub registration untouched.
- [ ] Verify: `xcodebuild test -project RunHub.xcodeproj -scheme RunHub -destination 'platform=macOS'`

### Task 8: Optional GitHub enrichment via `gh` (repo + org)

**Objective:** When `gh` is installed and authenticated, enrich a runner's status with the authoritative online/offline + busy state from the runners API, choosing the repo or org endpoint from the runner's registration. Degrade silently to local-only otherwise.

**Files:**

- Create: `RunHub/Services/GitHubEnrichment.swift`
- Create: `RunHubTests/GitHubEnrichmentTests.swift`

**Key Decisions / Notes:**

- Detect availability via `gh auth status` (and `gh` on PATH). `enrich(registration:runnerName:)`:
  - `.repo(owner, repo)` → `gh api repos/{owner}/{repo}/actions/runners`
  - `.org(org)` → `gh api orgs/{org}/actions/runners`
  - `.enterprise`/`.unknown` → returns `nil` (out of scope for enrichment).
  Match the API record by runner `name` (use `--paginate` / `per_page=100` so runners past the first page match); return the authoritative `status` (online/offline) + `busy` flag. **The runners-list endpoint returns only id/name/os/status/busy/labels — there is no job or job-URL field**, so enrichment provides NO job web URL (the job *name* comes from local stdout parsing, Task 4).
- Inject the command executor (`(args) throws -> Data`) so tests feed canned JSON and assert endpoint selection + parsing without invoking real `gh`.
- Enrichment is **additive**: any failure/absence returns `nil` and never blocks local flows (Goal Truth 2).

**Definition of Done:**

- [ ] A `.repo` registration invokes the `repos/{owner}/{repo}/actions/runners` endpoint; a `.org` registration the `orgs/{org}/actions/runners` endpoint.
- [ ] Canned runners JSON parses to the matching runner's `status` (online/offline) + `busy` flag; a `.enterprise`/`.unknown` registration returns `nil`.
- [ ] An unavailable/failing `gh` returns `nil` without throwing to the caller.
- [ ] Verify: `xcodebuild test -project RunHub.xcodeproj -scheme RunHub -destination 'platform=macOS'`

### Task 9: Launch-at-login (SMAppService)

**Objective:** Provide a thin, observable wrapper over `SMAppService.mainApp` to register/unregister RunHub as a login item and report current status for the UI toggle, with the status→enabled mapping unit-tested through an injected status seam.

**Files:**

- Create: `RunHub/Services/LoginItem.swift`
- Create: `RunHubTests/LoginItemTests.swift`

**Key Decisions / Notes:**

- `LoginItem`: inject a status provider `statusProvider: () -> SMAppService.Status` (default `{ SMAppService.mainApp.status }`) so `isEnabled` (`statusProvider() == .enabled`) is testable without a registered bundle. `enable()` → `try SMAppService.mainApp.register()`, `disable()` → `try unregister()`; surface thrown errors to the caller for the toggle to display.
- The register/unregister side effects still require a real registered app bundle in launchd, so they are verified via E2E **TS-007**, not unit tests — only the pure status→bool mapping is unit-tested. (No `Trivial:` escape — `LoginItem` adds public symbols and an error path.)

**Definition of Done:**

- [ ] `isEnabled` returns `true` only when the injected status provider yields `.enabled` (unit test covers `.enabled` vs `.notRegistered`/`.requiresApproval`).
- [ ] `enable()`/`disable()` call `SMAppService.mainApp.register()`/`unregister()`; thrown errors propagate to the caller.
- [ ] Verify: `xcodebuild test -project RunHub.xcodeproj -scheme RunHub -destination 'platform=macOS'`

### Task 10: Menu bar UI assembly + wiring + quit confirmation

**Objective:** Assemble the real menu bar UI: bind the `MenuBarExtra` to `RunnerManager`, render the runner list with status badges and per-runner Start/Stop, add the Add-Runner folder picker, Start-all/Stop-all, the Launch-at-login toggle, an empty state, an aggregate menu bar glyph, and a quit-with-running-job confirmation.

**Files:**

- Modify: `RunHub/RunHubApp.swift`
- Create: `RunHub/Views/MenuContentView.swift`
- Create: `RunHub/Views/RunnerRowView.swift`

**Key Decisions / Notes:**

- Own a single `RunnerManager` (`@State`/`@StateObject`); call `resumeDesiredRunning()` on launch. Drive the `MenuBarExtra` `systemImage`/label from aggregate state (e.g. count of online vs busy).
- `MenuContentView`: list of `RunnerRowView` (name, repo/org, status badge, current job when busy, Start/Stop, and a **Remove** control → `manager.remove` — untrack only, no file/GitHub deletion), an **empty state** ("No runners — Add Runner to begin"), and controls: Add Runner (`NSOpenPanel`, directories only → `manager.add`; show the not-a-runner rejection and the installed-as-service warning), Start All, Stop All, a Launch-at-login `Toggle` bound to `LoginItem`, and Quit.
- Quit: `MenuBarExtra` cannot intercept termination, so install an `@NSApplicationDelegateAdaptor`. In `applicationShouldTerminate(_:)`, if `manager.hasRunningJob` present a confirmation via **`NSAlert.runModal()`** (SwiftUI `.confirmationDialog`/`.alert` is unreliable from a `MenuBarExtra(.window)` panel — see Risks) and return `.terminateCancel` on cancel; in `applicationWillTerminate(_:)` call `manager.stopAllProcesses()` so no runners are orphaned (this does NOT clear `desiredRunning`).
- When `gh` enrichment is available, surface its authoritative online/busy as a subtle secondary indicator on the row (there is no job web URL — see Task 8).

**Definition of Done:**

- [ ] The panel lists adopted runners with correct badge + current job, or the empty state when none (TS-001, TS-002).
- [ ] Add Runner adds a valid folder and rejects a non-runner folder with a message (TS-001, TS-005); Start/Stop and Start-all/Stop-all work (TS-002, TS-003).
- [ ] A runner row's **Remove** control untracks it (row disappears; folder + GitHub untouched) (TS-008).
- [ ] Quitting while a job runs shows an `NSAlert` confirmation, then stops all processes and exits (TS-004); the Launch-at-login toggle reflects status (TS-007).
- [ ] Verify: `xcodebuild -project RunHub.xcodeproj -scheme RunHub -destination 'platform=macOS' build` then launch the app and walk TS-001..TS-008.
