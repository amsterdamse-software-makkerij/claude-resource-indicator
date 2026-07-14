# Code Review — Optimizations & Improvements

**Date:** 2026-07-13 · **Scope:** full source tree (~1,300 lines Swift) · **Method:** four parallel subagent reviews (polling/lifecycle, networking/data, UI/rendering, build/packaging), each read-only, then hand-vetted against the source.

This started as a *review-before-implement* document. It was **implemented on 2026-07-13** across six reviewed batches — see [Implementation status](#implementation-status) for the per-finding outcome and the decisions taken along the way. The original review text is preserved as written; the statuses are annotations layered on top.

## TL;DR

The app is small, well-structured, and already thoughtful about the things that matter for a menu-bar utility (read-only credential access, backoff, keeping last-known data visible). The highest-value work is a cluster of **energy/redraw** wins (it runs all day) and a handful of **reliability edge cases** in the polling/backoff state machine. Most other findings are cheap hardening or polish.

One reviewer finding — "menu-bar image is blurry on Retina" — did **not** survive vetting; see [Investigated & rejected](#investigated--rejected).

## Implementation status

Worked through in the batch order below. 28 unit tests were added (there were none before); every batch was build-verified and the app was launched and eyeballed after the UI batch. **Done** = implemented and verified · **Partial** = core done, remainder deferred · **Deferred** = intentionally postponed (low value, or belongs to the separate release-pipeline effort) · **Accepted** = reviewed and left as-is · **Rejected** = did not survive vetting.

| Finding | Status   | Note                                   |
| ------- | -------- | -------------------------------------- |
| R1      | Done     | readFailed vs notFound (+empty-exit-0) |
| R2      | Done     | reset backoff on any non-rateLimited   |
| R3      | Done     | single cancellable retry task          |
| R4      | Done     | defer releases inFlight                |
| R5      | Done     | 5-min dormant stretch; watcher deferred |
| R6      | Done     | pendingRefresh honored mid-flight      |
| E1      | Done     | icon-layer cache, not Equatable dedup  |
| E2      | Done     | timer gated to menu-open (b skipped)   |
| E3      | Done     | timer.tolerance = 10%                  |
| E4      | Deferred | low; screen-sleep behavior defensible  |
| E5      | Deferred | low; already debounced                 |
| D1      | Done     | clamp in MetricValue.init              |
| D2      | Done     | parseExpiry ms/sec/ISO/string          |
| D3      | Done     | retryAfterSeconds int + HTTP-date      |
| D4      | Done     | looksLikeJSONBody guard on 200         |
| D5      | Done     | isExpired(skew:); server authoritative |
| S1      | Done     | private ephemeral URLSession           |
| S2      | Accepted | token in String, per threat model      |
| B1      | Done     | diagnostics behind #if DEBUG           |
| B2      | Done     | local plumbing; pipeline deferred      |
| B3      | Done     | per-arch bin paths computed once       |
| B4      | Done     | codesign --verify after signing        |
| B5      | Deferred | version stamping -> release pipeline   |
| B6      | Done     | copyright + LSApplicationCategoryType  |
| B7      | Partial  | test target + CI; release CI deferred  |
| B8      | Open     | MakeIcon try? hardening                |
| B9      | Done     | plutil injects CFBundleExecutable      |
| U1      | Done     | warning symbol at red threshold        |
| U2      | Done     | @ScaledMetric rings/fonts; width fixed |
| U3/U4   | Done     | alert + open Login Items               |
| U5      | Done     | 0.15s knob slide + crossfade           |
| Q1      | Done     | Metric.windowLabel                     |
| Q2      | Done     | single MetricValue.fraction            |
| Blur    | Rejected | resolution-independent NSImage         |

### Decisions of note

- **E1 — icon cache, not `Equatable` state dedup.** A `fetchedAt`-inclusive `Equatable` would never dedup a steady poll (the timestamp advances each fetch); a `fetchedAt`-*excluding* one would freeze the retained state's clock and make `staleNote` falsely show "Waiting for sync…" after 150s while polling succeeds. The controller instead caches the rendered ring fractions + tooltip and skips the redraw when unchanged — same energy win, no state-semantics damage.
- **E2 — part (a) only.** The countdown ticker is mounted (and its `Timer` therefore alive) only while `model.isMenuOpen`. Part (b) — pushing `now` into a leaf caption / `Text(timerInterval:)` — was skipped: marginal once the timer only runs while visibly open, and it would turn the caption into a live ticking counter (unwanted).
- **R5 — stretch, not full pause.** `.expired`/`.notSignedIn` back the auto-poll off to 5 min; menu-open, wake, and network-restored still refresh immediately. The optional keychain-change watcher was skipped (deprecated APIs + fragility for marginal gain over menu-open recovery).
- **R6 — pending only while in-flight.** A dropped trigger is remembered only when a fetch is running; backoff-drops are left to R3's retry task, and a spacing-drop with no fetch in flight is correct coalescing (data is <1s old).
- **R1 — empty-output extra.** A zero-exit `security` call with empty output is now `readFailed` (found-but-empty is an anomaly, not "never signed in").
- **U batch.** U1: warning glyph at the red threshold only, palette unchanged. U2: scale rings + fonts but keep the fixed 264-pt width (and unify the previously duplicated constant). U5: knob slide added.
- **B2 — local plumbing only.** `Resources/Entitlements.plist` + parameterized `SIGNING_IDENTITY` + `sign`/`notarize`/`release` targets (hardened runtime, timestamp, entitlements, `spctl` assert) are in. The broader pipeline from the [notarization design doc](../superpowers/specs/2026-06-14-homebrew-and-notarization-design.md) — bundle-ID rename + legacy LaunchAgent migration, `release.yml`, the Homebrew tap/cask, secrets, version stamping — remains that effort's work. The signing/notarization path is spec-aligned but **not run end-to-end** (no Developer ID cert in the dev environment).

### Operational note

The repo lives under a file-provider-synced folder (iCloud Documents). Its daemon asynchronously re-stamps `com.apple.FinderInfo` onto `build/…app` and races the `xattr -cr` in the Makefile, so `make app` / `make run` intermittently fail `codesign` with "resource fork … not allowed." Fix by excluding `build/` from sync or adding a clear→sign retry loop to the bundle targets.

### Still open

- **B5** (version single-source), **B7** (full tagged-release CI), **B8** (`MakeIcon.swift` `try?` hardening) — not yet done.
- **E4 / E5 / S2** — deferred or accepted as low-value, per the findings themselves.

## Recommended priority

| Tier   | Theme                                  | Why now                                                                 |
| ------ | -------------------------------------- | ----------------------------------------------------------------------- |
| **P1** | Energy & redraw waste; backoff bugs    | Runs 24/7; a few small fixes cut all-day CPU/wakeups and fix real edges |
| **P2** | Data robustness, security hardening    | Cheap insurance against an undocumented endpoint drifting               |
| **P3** | Build/packaging, accessibility, polish | Matters for distribution (ties into the notarization design doc) and UX |

Suggested first batch (all small, high-confidence, low-risk): **R2, R4, E1, E3, D1**. Then **E2, R5, R3, R6**. Then P2/P3 as appetite allows.

---

## P1 — Reliability & energy

### R1 — A locked/failed keychain reads as "Not signed in"

- **Where:** `Keychain.swift:44-49` · **Severity:** medium · **Effort:** small
- **What:** Any non-zero exit from `/usr/bin/security` — a locked keychain, an ACL/prompt timeout, a transient error — is mapped to `KeychainError.notFound`, which the UI renders as "Not signed in. Sign in with Claude Code." A signed-in user with a momentarily locked keychain is told, incorrectly, that they never signed in.
- **Fix:** Distinguish `security`'s exit code 44 (`errSecItemNotFound`) → `notFound` from other non-zero statuses → a new `readFailed` case surfaced as `.error(...)` (which preserves last-known data), not `.notSignedIn`.

### R2 — Backoff counter only resets on `.loaded`

- **Where:** `AppModel.swift:64-81` · **Severity:** medium · **Effort:** small
- **What:** `currentBackoff` is reset to 0 only in the `.loaded` branch. If the app hits a 429 (backoff grows), then bounces through `.offline`/`.error`/`.expired` and back to another 429 without ever landing on `.loaded` in between, the backoff keeps doubling from its stale value. Server-provided `Retry-After` also bypasses `nextBackoff()`, so that path never advances *or* clears the counter.
- **Fix:** Reset `currentBackoff = 0` on any successful HTTP round-trip (i.e. whenever `apply` receives anything other than `.rateLimited`), not just `.loaded`.

### R3 — Backoff retries are uncancellable and can stack

- **Where:** `AppModel.swift:83-87` · **Severity:** medium · **Effort:** medium
- **What:** `scheduleBackoffRetry` fires a bare `DispatchQueue.main.asyncAfter` with no handle. Repeated 429s (or a 429 followed by wake/network refreshes that also 429) each enqueue an independent, uncancellable delayed retry, so multiple overlapping retries pile up and wake the app redundantly once backoff expires.
- **Fix:** Hold the pending retry as a single `Task`/`DispatchWorkItem`, cancel any existing one before scheduling a new one — or fold the retry into the existing 60s timer path guarded by `backoffUntil` so there's only ever one scheduler.

### R4 — `inFlight` can wedge with no recovery

- **Where:** `AppModel.swift:57-61` · **Severity:** medium · **Effort:** small
- **What:** `inFlight = false` is the last line of the fetch `Task`, after `apply`. `UsageService.fetch` never throws today, so it's safe *now* — but there's no `defer`. Any future throw/cancel between setting `inFlight = true` and the reset leaves it stuck `true`, permanently blocking all polling with no self-heal.
- **Fix:** `defer { self.inFlight = false }` inside the `Task`, guaranteeing release regardless of outcome.

### R5 — Expired token is re-polled every 60s forever

- **Where:** `AppModel.swift:64-76`, `UsageService.swift:47-48` · **Severity:** medium · **Effort:** small
- **What:** On 401/403 → `.expired`, `apply` falls to `default` (no backoff), so the 60s timer keeps hammering the endpoint with a known-bad token indefinitely until the user re-authenticates elsewhere. Wasted network/energy and a needless rate-limit risk.
- **Fix:** On `.expired`/`.notSignedIn`, pause the fast poll or stretch the interval substantially, resuming on menu-open or a keychain change. (A keychain-change trigger would also make re-login feel instant.)

### R6 — Wake/open triggers silently dropped

- **Where:** `AppModel.swift:41-52` · **Severity:** medium · **Effort:** medium
- **What:** When a refresh is rejected for `minRequestSpacing`, `backoffUntil`, or `inFlight`, the trigger is discarded outright. A wake or network-restored event landing inside the 1s coalescing window, or during an in-flight request, produces no eventual refresh — the user can stare at stale data until the next 60s tick. The timer is the only safety net.
- **Fix:** When dropping due to `inFlight`/spacing, set a `pendingRefresh` flag and re-run once the current fetch completes or spacing elapses, instead of dropping.

### E1 — State republished (and icon redrawn) even when nothing changed

- **Where:** `AppModel.swift:64-65`, `StatusItemController.swift:27-30, 80-84` · **Severity:** medium–high · **Effort:** medium
- **What:** `state = newState` fires `@Published`/`objectWillChange` on *every* fetch, even when a steady `.loaded` snapshot carries identical utilization. That re-triggers `renderStatusIcon`, which unconditionally rebuilds the menu-bar `NSImage` (a full off-screen CoreGraphics draw of N arcs) and recomputes the tooltip — every 60s, all day, for zero visual change. `LoadState` isn't `Equatable`, so nothing dedupes.
- **Fix:** Make `LoadState`/`UsageSnapshot`/`MetricValue` `Equatable` and skip the assignment when `newState == state`; and/or cache the last `[RingSpec]` + tooltip in the controller and early-return when they're unchanged. (Two layers of the same idea — the `Equatable` dedupe alone covers most of it.)

### E2 — Countdown timer runs while the menu is closed and recomputes the whole view

- **Where:** `MenuContentView.swift:9, 16-40` · **Severity:** medium · **Effort:** medium
- **What:** `Timer.publish(every: 30…).autoconnect()` lives for the hosting view's lifetime — which is built into the menu once and never torn down — so it keeps firing every 30s even while the dropdown is hidden, waking the run loop and mutating `now`. Each tick recomputes the entire `MenuContentView.body` (rings, bars, percentages, plan pill) although `now` only affects the small "resets in…" caption and the staleness note.
- **Fix:** Two independent wins: (a) gate the ticking to menu-open only (start/stop via `menuWillOpen`/`menuDidClose`); (b) push `now` down into a small dedicated caption subview (or use `Text(timerInterval:)`) so a tick doesn't invalidate the parent body.

### E3 — Poll timer has no tolerance (no wakeup coalescing)

- **Where:** `AppModel.swift:93-96` · **Severity:** low · **Effort:** small
- **What:** The repeating `Timer` sets no `tolerance`, so the kernel wakes precisely every 60s and can't batch the wakeup with other scheduled work — a small but real all-day battery cost.
- **Fix:** `t.tolerance = pollInterval * 0.1` (~6s). Trivial, pure win for a background utility.

### E4 — Sleep detection keys on *screen* sleep, not *system* sleep

- **Where:** `AppModel.swift:100-118` · **Severity:** low · **Effort:** small
- **What:** `isAsleep` is driven by `screensDidSleep/WakeNotification` (display sleep), not `willSleep/didWake` (system power sleep). This matches the README's stated "pauses while the display is asleep" behavior, and real system sleep pauses the timer anyway — but display-sleep-while-system-awake (clamshell + external display, "prevent display sleep") is an imperfect proxy for "user away."
- **Fix:** If the intent is truly "pause when the user is away," observe `NSWorkspace.willSleepNotification`/`didWakeNotification` for the asleep flag and keep `screensDidWake` only as an extra refresh nudge. Low priority — current behavior is defensible.

### E5 — Network path changes can burst refreshes

- **Where:** `AppModel.swift:124-132` · **Severity:** low · **Effort:** small
- **What:** `pathUpdateHandler` fires on many path mutations (Wi-Fi↔cellular, IP/DNS changes). Any brief `.unsatisfied → .satisfied` bounce counts as `cameOnline` and fires a refresh; a flapping network can produce a burst. Each is still gated by `minRequestSpacing`/`backoff`, so it's largely absorbed — hence low severity.
- **Fix:** Route the came-online refresh through the same debounce as other auto triggers; mostly already mitigated.

---

## P2 — Data robustness & security hardening

### D1 — Utilization is never clamped to 0…100

- **Where:** `UsageService.swift:64-72`, `Models.swift:52` · **Severity:** low–medium · **Effort:** small
- **What:** `MetricValue.utilization` is documented `0...100` but the raw endpoint value is passed through unclamped and its unit is *assumed* (percent vs. fraction). If the undocumented endpoint ever returns a 0–1 fraction, a >100 overage, or a negative sentinel, the ring/percent math silently goes wrong. (The rings clamp the *fraction* defensively; `percentText` does not.)
- **Fix:** Clamp with `max(0, min(100, v))` at the normalization site in `UsageService.fetch`. Optionally detect the unit (if every value ≤ 1.0, scale ×100) — but clamping alone removes the sharp edges.

### D2 — `expiresAt` parsed only as a millisecond-epoch number

- **Where:** `Keychain.swift:63-68` · **Severity:** medium · **Effort:** small
- **What:** `expiresAt` is read only as `Double`/`Int` (ms epoch). If Claude Code ever writes it as an ISO-8601 string or seconds-epoch, `expiry` stays `nil`; and `isExpired` returns `false` for a `nil` expiry — so an *expired* token is treated as valid, then fails downstream with a less clear state. Schema drift silently disables local expiry detection.
- **Fix:** Also parse string (ISO-8601) and seconds-vs-ms epoch forms (magnitude heuristic). Related: consider treating the server 401/403 as the real source of truth (see D5).

### D3 — `Retry-After` only handles delta-seconds

- **Where:** `UsageService.swift:50` · **Severity:** low · **Effort:** small
- **What:** `Retry-After` may be an HTTP-date (RFC 7231) rather than an integer; `Double($0)` returns `nil` for that form, silently discarding the server's backoff hint (falling back to local exponential backoff).
- **Fix:** On integer-parse failure, parse an HTTP-date and convert to a delta. Anthropic currently returns integer seconds, so this is defensive.

### D4 — No content-type / empty-body distinction on 200

- **Where:** `UsageService.swift:44-61` · **Severity:** low · **Effort:** small
- **What:** A 200 with an empty body or an HTML captive-portal/proxy page is fed straight to the JSON decoder and surfaces as a generic "Couldn't parse usage," conflating network interception with real schema drift. (Note: an empty JSON object `{}` decodes fine and correctly routes to `.noSubscription`, since all fields are optional — so this is narrowly about non-JSON/empty bodies.)
- **Fix:** Check `Content-Type` contains `json` and special-case empty `data`; treat a non-JSON 200 as `.offline` rather than a parse error.

### D5 — Token expiry trusts the local clock with no skew tolerance

- **Where:** `Keychain.swift:8-11`, `UsageService.swift:19-22` · **Severity:** low–medium · **Effort:** small
- **What:** `isExpired` compares device wall-clock directly to `expiresAt`. A fast-skewed clock short-circuits to `.expired` and never even attempts a request the server would still accept; a slow clock sends a dead token. At the exact boundary it flaps.
- **Fix:** Treat the local expiry check as an *optimization hint* and let the server 401/403 be authoritative — i.e. don't hard-block the request on a marginal local expiry. (Pairs naturally with R5's expired-state backoff.)

### S1 — Uses `URLSession.shared` (shared cache/cookies) for a Bearer-token request

- **Where:** `UsageService.swift:27, 35` · **Severity:** low · **Effort:** medium
- **What:** The token is never logged (good, verified), and access is read-only (verified) — but `URLSession.shared` carries shared cache/cookie/credential storage. An ephemeral session is a cleaner surface for an authenticated request.
- **Fix:** Use a private `URLSession(configuration: .ephemeral)` with `urlCache = nil` and `requestCachePolicy = .reloadIgnoringLocalCacheData`.

### S2 — Access token lives in a plain `String` for the process lifetime *(note, likely accept)*

- **Where:** `Keychain.swift:3-5` · **Severity:** low · **Effort:** medium
- **What:** The token sits in an immutable `String` (heap, not wiped) and is re-read per fetch. Not logged; read-only. Pure memory-hygiene nicety.
- **Fix:** Optionally read per-request and drop after building the header, or wrap in a zeroing type. Reasonable to **accept as-is** given the threat model — listed for completeness.

---

## P3 — Build, packaging, accessibility & polish

### B1 — Test/diagnostic code ships in the release binary

- **Where:** `SelfTest.swift`, `RenderTest.swift`, `main.swift:3-12` · **Severity:** medium · **Effort:** small
- **What:** `SelfTest` and `RenderTest` compile into the shipped binary and are reachable via undocumented `--selftest` / `--render-rings <path>` flags. `--render-rings` writes an arbitrary PNG path and isn't even wired to a Makefile target (dead in the product). Needless diagnostic surface for end users.
- **Fix:** Guard both files plus the `main.swift` dispatch behind `#if DEBUG` (or a `-D SELFTEST` condition), or move them to a separate non-shipped target. `make selftest` would build the debug/flagged variant.

### B2 — No hardened runtime → notarization impossible

- **Where:** `Makefile:22-24, 35-37` · **Severity:** high *(for distribution)* · **Effort:** medium
- **What:** The bundle is ad-hoc signed (`codesign --sign -`) with no `--options runtime`, `--timestamp`, or entitlements, so it can never be notarized and distributed copies are Gatekeeper-blocked (the README documents the manual `xattr` workaround). This is the crux of the existing [notarization design doc](../superpowers/specs/2026-06-14-homebrew-and-notarization-design.md) — cross-referenced, not re-litigated here.
- **Fix:** Parameterize the signing identity (`SIGN_ID ?= -`), add `--options runtime --timestamp` + an entitlements file when a real Developer ID is present, and add notarize/staple + `spctl --assess` verify targets, per the design doc.

### B3 — `universal` rebuilds redundantly via fragile `--show-bin-path` shell-outs

- **Where:** `Makefile:27-39, 41, 45` · **Severity:** medium · **Effort:** small
- **What:** `universal` runs `swift build --arch …` for each arch and then re-invokes `swift build … --show-bin-path` inside command substitution (line 32), and `dist`/`dmg` both re-enter `universal`, so a full pipeline rebuilds several times. The in-recipe `$$(swift build …)` can also silently rebuild if flags drift.
- **Fix:** Compute both per-arch bin paths once into make variables (like `BUILT_BIN`) and reuse them in the `lipo` call.

### B4 — No signature verification after `codesign`

- **Where:** `Makefile:22-24, 35-37` · **Severity:** low · **Effort:** small
- **What:** Nothing runs `codesign --verify` / `spctl --assess` after signing, so a broken signature ships silently.
- **Fix:** Append `codesign --verify --deep --strict "$(BUNDLE)"` (and `spctl -a -vv` for Developer-ID builds) to fail fast.

### B5 — Version numbers hardcoded with no single source

- **Where:** `Info.plist:15-18`, `Makefile` · **Severity:** low · **Effort:** medium
- **What:** `CFBundleShortVersionString`/`CFBundleVersion` are static literals with no make variable or `git describe` derivation — awkward once Homebrew/notarized releases need reliable bumps.
- **Fix:** Drive version from `VERSION ?=` (or `git describe`) and inject into a generated Info.plist at bundle time (`PlistBuddy`/`sed`).

### B6 — Info.plist metadata gaps

- **Where:** `Info.plist:25-30` · **Severity:** low · **Effort:** small
- **What:** `NSHumanReadableCopyright` holds a disclaimer rather than a copyright string, and there's no `LSApplicationCategoryType` (recommended for a distributable/notarized app).
- **Fix:** Put a real copyright in `NSHumanReadableCopyright`, keep the disclaimer in README/About, and add `LSApplicationCategoryType` (e.g. `public.app-category.developer-tools`).

### B7 — No tests, no CI

- **Where:** `Package.swift:7-12` · **Severity:** low · **Effort:** large
- **What:** Only an executable target; the sole "test" is `make selftest`, which needs live network + real keychain creds, so nothing is CI-automatable.
- **Fix:** Add an XCTest target for the pure logic (JSON parsing incl. the ISO-8601 fallbacks, `Theme` thresholds, `ResetFormatter`, D1 clamping) and a GitHub Actions workflow running `swift test` + `make app`. Highest-leverage tests land right on the D1–D4 robustness fixes.

### B8 — `MakeIcon.swift` swallows all errors with `try?`

- **Where:** `Tools/MakeIcon.swift:57, 70, 76` · **Severity:** low · **Effort:** small
- **What:** Dir creation, PNG writes, and `iconutil` invocation all use `try?`, so a failure yields a partial/empty iconset while the script can still print success.
- **Fix:** Use `try` with propagation (a script exits non-zero on throw) and check `iconutil` availability.

### B9 — Bundle executable name not validated against the plist

- **Where:** `Makefile:19-20, 32-33`, `Info.plist:9-10` · **Severity:** low · **Effort:** small
- **What:** The binary is copied as `$(BINNAME)` and `CFBundleExecutable` is hardcoded; they agree today, but renaming `BINNAME` would silently produce a bundle that fails to launch.
- **Fix:** Derive `CFBundleExecutable` from `$(BINNAME)` via plist injection, or assert they match at bundle time.

### U1 — Severity is encoded by color alone (color-blind users)

- **Where:** `Theme.swift:10-20`, `MenuContentView.swift:167, 193, 203` · **Severity:** medium · **Effort:** medium
- **What:** Green/orange/red is the only signal for utilization severity, and the menu-bar rings are monochrome — so a red/green-deficient user (~8% of men) has no reliable cue that a limit is near.
- **Fix:** Add a redundant non-color cue at the red threshold (a warning SF Symbol next to the percentage, bolder weight, or a pattern), and/or shift to a color-blind-safe palette.

### U2 — Fixed point sizes ignore Dynamic Type

- **Where:** `MenuContentView.swift:147-149, 179`, `30, 37` · **Severity:** medium · **Effort:** medium
- **What:** Ring geometry (`outerSize 78`, `lineWidth 9`, `step 21`), the center label (`.system(size: 16)`), and the fixed `width: 264` don't respond to accessibility text sizes, so Larger Text will truncate/collide.
- **Fix:** `@ScaledMetric` for ring sizes/fonts (or relative text styles) and let the width adapt or wrap.

### U3 — "Launch at Login" failures are invisible

- **Where:** `LoginItem.swift:16-31` · **Severity:** medium · **Effort:** medium
- **What:** `set(_:)` catches every error, only `NSLog`s it, then `refreshStatus()` snaps the toggle back. If registration needs user approval (`SMAppService.Status.requiresApproval`, common after the user previously disabled it in System Settings), the switch just flips off with no explanation.
- **Fix:** Detect `requiresApproval` and call `SMAppService.openSystemSettingsLoginItems()` / show an alert; surface the caught error rather than swallowing it.

### U4 — `refreshStatus` collapses all non-enabled states to "off"

- **Where:** `LoginItem.swift:12-14` · **Severity:** low · **Effort:** small
- **What:** `isEnabled = status == .enabled` folds `.requiresApproval` and `.notFound` into "off," masking a pending-approval state. (Same root cause as U3.)
- **Fix:** Model enabled / requiresApproval / notRegistered distinctly and reflect approval-pending in the toggle. Fix alongside U3.

### U5 — `MiniSwitch` toggles with no animation

- **Where:** `ToggleMenuItemView.swift:59-93` · **Severity:** low · **Effort:** small
- **What:** The knob jumps instantly on toggle (no slide), reading as slightly less native than a real `NSSwitch`. Performance is fine (user-driven).
- **Fix:** Optionally animate the knob X; or accept as a deliberate simplification.

### Q1 — Center-label rule is a stringly-typed special case

- **Where:** `MenuContentView.swift:181` · **Severity:** low · **Effort:** small
- **What:** `primary.metric.shortLabel == "S" ? "5h" : primary.metric.shortLabel` buries a display rule in the view and breaks silently if `shortLabel` ever changes; "5h" (window length) is unrelated to `shortLabel` semantics.
- **Fix:** Add a `Metric.windowLabel` (`.session → "5h"`, etc.) and read it, keeping display strings in the model.

### Q2 — `min(1, util/100)` clamping duplicated in four places

- **Where:** `MenuContentView.swift:167, 209`, `StatusItemController.swift:91`, `RingRenderer.swift:52` · **Severity:** low · **Effort:** small
- **What:** The 0–1 fraction conversion is copy-pasted across the watch rings, bars, status-item ring specs, and the renderer, while `percentText`/`Theme.color` are the only shared helpers.
- **Fix:** Add a single clamped `MetricValue.fraction` (0…1) computed property and use it everywhere. Composes cleanly with **D1** (clamp once at the source).

---

## Investigated & rejected

### ✗ "Menu-bar image is blurry on Retina" — not a real issue

One reviewer flagged (as *high* severity) that `RingRenderer.image(for:)` is called with the default `scale: 1` and therefore renders blurry on @2x displays. **This does not hold up.** The image is built with `NSImage(size:flipped:drawingHandler:)`, which produces a *resolution-independent* image: AppKit re-invokes the drawing handler at the destination's backing scale, drawing the arcs as vectors at native @2x/@3x resolution. The `scale:` parameter exists only so `RenderTest` can rasterize an enlarged PNG for offline inspection; it is correctly irrelevant to the live menu-bar rendering. No change needed. (If we ever want to *verify* this empirically, `make` a build and eyeball on a Retina display — but the API contract is clear.)

---

## Cross-cutting notes verified during review

- **Read-only credential guarantee holds.** No write/refresh/keychain-mutation calls exist anywhere; `security find-generic-password … -w` is read-only, token refresh is explicitly avoided (`UsageService.swift:19-22`), and the token appears in no log/print statement. (Confirmed by the networking review.)
- **`Equatable` is the connective tissue for the energy work.** E1 (dedupe publishes), Q2 (`MetricValue.fraction`), and D1 (clamp at source) all touch the model types together — worth doing as one coherent change to `Models.swift`.

## Proposed implementation batches

| Batch | Findings                     | Character                                              |
| ----- | ---------------------------- | ------------------------------------------------------ |
| **1** | R2, R4, E3, D1, Q2           | Tiny, high-confidence, low-risk; mostly one-liners     |
| **2** | E1, E2                       | The main energy win; touches model `Equatable` + timer |
| **3** | R1, R5, R3, R6, D5           | Polling/backoff state-machine hardening                |
| **4** | D2, D3, D4, S1               | Endpoint/data robustness (+ add tests here, B7)        |
| **5** | U1, U2, U3/U4, Q1, U5        | Accessibility & UX polish                              |
| **6** | B1, B3, B4, B6, B9 (then B2) | Build hygiene, then notarization per the design doc    |

**Outcome:** all six batches were implemented on 2026-07-13 in this order; see [Implementation status](#implementation-status) for per-finding results and the handful of items deferred to the release-pipeline effort. Batch 4 introduced the XCTest target (there were no tests before), so the logic-bearing fixes in it and later batches are pinned by tests.
