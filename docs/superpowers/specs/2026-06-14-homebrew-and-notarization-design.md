# Homebrew distribution & Apple notarization — design

**Status:** Approved (2026-06-14). Pending implementation plan.

## Goal

Ship `Claude Resource Indicator` so a user on a clean Mac can run:

```sh
brew tap amsterdamse-software-makkerij/tap
brew install --cask claude-resource-indicator
```

…and the app opens straight into the menu bar with **no Gatekeeper warning**,
no quarantine-bit manual unblock, and no first-launch security dialog.

A tagged push (`vX.Y.Z`) is the only trigger required to cut a release.
Everything from signing to publishing the Homebrew cask is automated.

## Non-goals (v1)

- In-app auto-update (Sparkle). Homebrew handles updates via `brew upgrade`.
- Mac App Store submission. Different cert, sandbox required, our keychain-read
  pattern would not pass review.
- Pre-release / beta channel. Pipeline rejects `v*-*` tags; can be added later.
- Submission to mainline `homebrew/homebrew-cask`. Personal tap only for now.

## High-level shape

```
git tag v1.0.1 → push
        │
        ▼
┌──────────────────────────────────────────────────────────┐
│ amsterdamse-software-makkerij/claude-resource-indicator  │
│   .github/workflows/release.yml                          │
│  ├─ extract version from tag                             │
│  ├─ stamp Info.plist (CFBundleShortVersionString/Version)│
│  ├─ swift build universal (arm64 + x86_64, lipo)         │
│  ├─ import Developer ID Application cert (.p12 secret)   │
│  ├─ codesign --options runtime --timestamp               │
│  │            --entitlements Resources/Entitlements.plist│
│  ├─ build DMG (extended Makefile)                        │
│  ├─ codesign the DMG                                     │
│  ├─ notarytool submit --wait (ASC API key)               │
│  ├─ stapler staple .app && stapler staple .dmg           │
│  ├─ spctl assertion (must print "accepted, Notarized")   │
│  ├─ gh release create v1.0.1 DMG.dmg                     │
│  └─ open PR in homebrew-tap bumping version+sha256       │
└──────────────────────────────────────────────────────────┘
        │
        ▼
┌──────────────────────────────────────────────────────────┐
│ amsterdamse-software-makkerij/homebrew-tap               │
│   Casks/claude-resource-indicator.rb                     │
│   .github/workflows/ci.yml  (brew audit + auto-merge bot)│
└──────────────────────────────────────────────────────────┘
        │
        ▼
   $ brew tap amsterdamse-software-makkerij/tap
   $ brew install --cask claude-resource-indicator
   → opens cleanly, no Gatekeeper warning
```

---

## Section 1 — Apple signing & notarization

### Certificate

- One **Developer ID Application** cert (NOT *Apple Development*).
- Exported as `.p12` with a password.
- Signs both the `.app` bundle and the `.dmg` container.

### Hardened runtime + entitlements

A new committed file: `Resources/Entitlements.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```

Rationale:
- **Not sandboxed** — needs to read the `Claude Code-credentials` keychain
  item created by another app, which the sandbox would block.
- **Network client** — required for `api.anthropic.com` polling.
- **No `cs.disable-library-validation`** — no third-party dylibs are loaded.
- **No keychain entitlement** — generic keychain reads prompt the user on
  first access; no entitlement required.

### Notarization mechanism

`notarytool` with **App Store Connect API key** auth (not app-specific password):

- Key generated once in App Store Connect → Users and Access → Integrations.
- Role: **Developer** (lowest sufficient).
- Stored as a `.p8` file; CI base64-decodes the secret into a tmpfile.
- Revocable and scope-limited; no expiry pressure.

### Signing order (critical, easy to invert)

1. Sign the `.app` bundle (deep, `--options runtime --timestamp`).
2. Build the `.dmg` containing the signed `.app`.
3. Sign the `.dmg`.
4. `xcrun notarytool submit ClaudeResourceIndicator.dmg --wait` against the
   ASC API key.
5. `xcrun stapler staple` on **both** the `.app` inside the DMG mount AND the
   `.dmg` itself, so the ticket works offline.
6. Assertion: `spctl -a -t exec -vv build/Claude\ Resource\ Indicator.app`
   must print `accepted` and `source=Notarized Developer ID`. Workflow fails
   loudly if this assertion does not pass.

### Replaces

The existing `codesign --force --sign -` in the Makefile (ad-hoc signing —
fine for local dev, not acceptable for distribution) is retained for the
`make app` target and replaced for the new `make release` target.

---

## Section 2 — Build & release pipeline

### Makefile additions

```make
sign:        # codesign .app with Developer ID + hardened runtime + entitlements
notarize:    # submit DMG to notarytool, wait, staple both .app and .dmg
release:     # universal → sign → dmg → sign DMG → notarize → staple → spctl assert
```

`make release` requires four env vars:

| Var | Example |
|---|---|
| `SIGNING_IDENTITY` | `Developer ID Application: Andrei Sudarikov (TEAMID)` |
| `AC_API_KEY_ID` | `ABCDE12345` |
| `AC_API_KEY_ISSUER_ID` | `12345678-1234-1234-1234-123456789012` |
| `AC_API_KEY_PATH` | `/tmp/AuthKey_ABCDE12345.p8` |

If any are unset, `make release` fails fast with a clear message. The
existing `make app`, `make dmg`, `make run`, `make install`, `make selftest`
targets continue to work with ad-hoc signing for local development.

### Version stamping

A tiny helper (inline `plutil` calls in the Makefile) reads `RELEASE_VERSION`
and writes:

- `CFBundleShortVersionString` → tag stripped of leading `v` (e.g. `1.0.1`)
- `CFBundleVersion` → `git rev-list --count HEAD` (monotonic build number)

Runs **before** `swift build` so the bundled Info.plist has the right values.

### GitHub Actions workflow

`.github/workflows/release.yml`:

```yaml
on:
  push:
    tags: ['v*']

jobs:
  release:
    runs-on: macos-14   # Apple Silicon, ships with Xcode + notarytool
    steps:
      - uses: actions/checkout@v4
      - name: Validate tag
        run: |
          if [[ "$GITHUB_REF_NAME" =~ - ]]; then
            echo "Pre-release tags not supported in v1"
            exit 1
          fi
          echo "RELEASE_VERSION=${GITHUB_REF_NAME#v}" >> $GITHUB_ENV
      - name: Import cert
        uses: apple-actions/import-codesign-certs@v3
        with:
          p12-file-base64: ${{ secrets.BUILD_CERTIFICATE_P12_BASE64 }}
          p12-password: ${{ secrets.BUILD_CERTIFICATE_P12_PASSWORD }}
          keychain-password: ${{ secrets.KEYCHAIN_PASSWORD }}
      - name: Write ASC API key
        run: |
          echo "${{ secrets.AC_API_KEY_P8_BASE64 }}" | base64 -d \
            > "$RUNNER_TEMP/asc_api_key.p8"
          echo "AC_API_KEY_PATH=$RUNNER_TEMP/asc_api_key.p8" >> $GITHUB_ENV
      - name: Build, sign, notarize, staple, assert
        env:
          SIGNING_IDENTITY: ${{ secrets.SIGNING_IDENTITY }}
          AC_API_KEY_ID:    ${{ secrets.AC_API_KEY_ID }}
          AC_API_KEY_ISSUER_ID: ${{ secrets.AC_API_KEY_ISSUER_ID }}
        run: make release
      - name: Publish GitHub release
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          gh release create "$GITHUB_REF_NAME" \
            "build/ClaudeResourceIndicator.dmg" \
            --generate-notes
      - name: Open cask bump PR
        env:
          GH_TOKEN: ${{ secrets.TAP_REPO_TOKEN }}
        run: ./.github/scripts/bump-cask.sh
```

### Third-party action audit

- `actions/checkout@v4` — official.
- `apple-actions/import-codesign-certs@v3` — Apple-maintained; thin wrapper
  that decodes the p12 into a transient keychain. Approved.

All other steps (`codesign`, `notarytool`, `stapler`, `spctl`, `gh`, `make`)
are direct shell calls — every step is auditable and reproducible locally.

### Expected CI time

~3–5 min including notarization wait for a small app like this.

---

## Section 3 — GitHub org & repo layout

**Already completed by user (2026-06-14):**
- Org `amsterdamse-software-makkerij` created (Free plan).
- Repo transferred: `amsterdamse-software-makkerij/claude-resource-indicator`.
- Empty repo created: `amsterdamse-software-makkerij/homebrew-tap`.
- Local clone remote updated to the new origin.

### Cross-repo PR auth

The release workflow in `claude-resource-indicator` needs to push to
`homebrew-tap`. The default `GITHUB_TOKEN` cannot write to other repos.

**Chosen approach: fine-grained Personal Access Token.**

- Scoped only to `amsterdamse-software-makkerij/homebrew-tap`.
- Permissions: `Contents: write`, `Pull requests: write`.
- Stored as `TAP_REPO_TOKEN` secret in `claude-resource-indicator`.
- 1-year expiry; rotation reminder added to `docs/superpowers/specs/`.

Alternatives rejected:
- GitHub App — cleaner for orgs at scale; overkill for one bot, one tap.
- Deploy key — can push but cannot open PRs cleanly via `gh`.

### Bundle ID change

`Resources/Info.plist`:
`com.andrei.claude-resource-indicator` → `com.amsterdamse-software-makkerij.claude-resource-indicator`

Side effects:
- `SMAppService.mainApp` keys off the bundle ID. Any pre-existing local
  LaunchAgent registration for `com.andrei.claude-resource-indicator`
  becomes orphaned.
- Add a one-time cleanup in `AppDelegate.swift` that, on startup, checks for
  and unregisters the legacy ID's LaunchAgent if present (`launchctl bootout`
  or `SMAppService(plistName:)`). Safe no-op when absent. Can be removed in
  a future release once the user base has rolled forward.

---

## Section 4 — Homebrew tap structure

```
amsterdamse-software-makkerij/homebrew-tap/
├── Casks/
│   └── claude-resource-indicator.rb
├── README.md
└── .github/workflows/ci.yml      # brew audit + auto-merge bot
```

### Cask file

`Casks/claude-resource-indicator.rb`:

```ruby
cask "claude-resource-indicator" do
  version "1.0.1"
  sha256 "abc123…"  # of the DMG

  url "https://github.com/amsterdamse-software-makkerij/claude-resource-indicator/releases/download/v#{version}/ClaudeResourceIndicator.dmg",
      verified: "github.com/amsterdamse-software-makkerij/claude-resource-indicator/"
  name "Claude Resource Indicator"
  desc "Menu bar app showing Claude subscription usage"
  homepage "https://github.com/amsterdamse-software-makkerij/claude-resource-indicator"

  depends_on macos: ">= :ventura"

  app "Claude Resource Indicator.app"

  uninstall quit:      "com.amsterdamse-software-makkerij.claude-resource-indicator",
            launchctl: "com.amsterdamse-software-makkerij.claude-resource-indicator"

  zap trash: [
    "~/Library/LaunchAgents/com.amsterdamse-software-makkerij.claude-resource-indicator.plist",
    "~/Library/Preferences/com.amsterdamse-software-makkerij.claude-resource-indicator.plist",
    "~/Library/Saved Application State/com.amsterdamse-software-makkerij.claude-resource-indicator.savedState",
  ]
end
```

### Cask details that matter

- `quit:` — menu bar app is running at uninstall time; without this `brew
  uninstall` fails to delete a running `.app`.
- `launchctl:` — `SMAppService.mainApp.register()` creates a LaunchAgent
  under the bundle ID. Unloads it cleanly so the next reboot doesn't try to
  spawn a deleted binary.
- `zap` — only runs on `brew uninstall --zap`. Standard etiquette: don't
  delete user data unless asked. The three paths are the only ones macOS
  touches for this app (verified against source: no `UserDefaults`,
  `FileManager` writes, or caching code; the LaunchAgent plist is the only
  intentional persistent state).
- **No `livecheck` block** — the release bot updates the cask explicitly.
  `brew livecheck` can still infer GitHub-releases polling from the URL.

### Tap CI

`.github/workflows/ci.yml`:

- On every PR: `brew style Casks/` and
  `brew audit --new --online --strict Casks/claude-resource-indicator.rb`.
- **Auto-merge** if all of:
  1. PR author is the release bot (matched by PAT-owner login),
  2. Diff only touches `version` + `sha256` lines (or creates the file from
     scratch on the very first release),
  3. `brew audit` passes.
- Manual review required for any other change.

### Release bot's PR

Opened from `claude-resource-indicator`'s release workflow via
`.github/scripts/bump-cask.sh`:

- Branch: `bump/v1.0.1`
- Body: links to the triggering GitHub Release, includes new sha256,
  references the workflow run URL for traceability.
- Authed with `TAP_REPO_TOKEN`.

### First release special case

Very first time, no cask exists. The bot detects "file not found" and
creates `Casks/claude-resource-indicator.rb` from a template committed at
`release/cask-template.rb` in the main repo. Subsequent releases only edit
the `version` and `sha256` lines.

---

## Section 5 — Versioning, secrets, and rollout

### Secrets in `amsterdamse-software-makkerij/claude-resource-indicator`

| Secret | Contents | Rotation |
|---|---|---|
| `BUILD_CERTIFICATE_P12_BASE64` | `base64 -i DeveloperID.p12` | Re-export, re-encode |
| `BUILD_CERTIFICATE_P12_PASSWORD` | The `.p12` export password | Re-export with new password |
| `KEYCHAIN_PASSWORD` | Random string for transient keychain | Anytime |
| `SIGNING_IDENTITY` | `Developer ID Application: … (TEAMID)` | When cert is rotated |
| `AC_API_KEY_ID` | 10-char ASC key ID | Generate new key in ASC |
| `AC_API_KEY_ISSUER_ID` | UUID, ASC team's issuer ID | Stays constant |
| `AC_API_KEY_P8_BASE64` | `base64 -i AuthKey_*.p8` | Generate new, revoke old |
| `TAP_REPO_TOKEN` | Fine-grained PAT, tap repo, write Contents+PRs | GH settings, 1-year cycle |

All eight go into **Actions secrets** scope (not Codespaces/Dependabot). The
workflow loads them into env vars at the start of the job; nothing is
echoed.

### Versioning rule

- Tags follow `vMAJOR.MINOR.PATCH` (semver).
- `CFBundleShortVersionString` mirrors the tag without `v`.
- `CFBundleVersion` is `git rev-list --count HEAD` — guaranteed monotonic.
- Pre-releases (e.g. `v1.1.0-beta.1`) are explicitly **rejected** by the v1
  workflow. Trivial to add later by branching the publish step.

### First release walkthrough

1. **Generate Developer ID cert** in Apple Developer portal. Export `.p12`
   with password. Also generate App Store Connect API key (Developer role),
   download `.p8`.
2. **Test locally:** set the four env vars, run `make release`. Should
   produce a notarized, stapled `build/ClaudeResourceIndicator.dmg`.
   Install it on a fresh-ish Mac and confirm: no Gatekeeper prompt, opens
   straight into the menu bar.
3. **Push all 8 secrets** to
   `amsterdamse-software-makkerij/claude-resource-indicator`
   Actions-secrets scope.
4. **Land the implementation PR** containing: bundle-ID rename, legacy
   LaunchAgent cleanup in `AppDelegate.swift`, `Resources/Entitlements.plist`,
   Makefile changes, `.github/workflows/release.yml`,
   `.github/scripts/bump-cask.sh`, `release/cask-template.rb`, README
   updates. Merge to `main`.
5. **Land tap CI PR** in `homebrew-tap` containing
   `.github/workflows/ci.yml` and `README.md`. (Done by hand once; tap
   stays small thereafter.)
6. **Tag `v1.0.0`** (the current Info.plist version), push. Watch the
   workflow.
7. **CI opens `bump/v1.0.0`** in `homebrew-tap`. Since no cask file exists
   yet, the workflow creates it from the template; the auto-merge bot lands
   it once `brew audit` passes.
8. **Verify from a clean Mac:**
   ```sh
   brew tap amsterdamse-software-makkerij/tap
   brew install --cask claude-resource-indicator
   open -a "Claude Resource Indicator"
   ```
   No Gatekeeper prompt. App appears in the menu bar.

### Verification command

`spctl -a -t exec -vv build/Claude\ Resource\ Indicator.app`

Must print `accepted` and `source=Notarized Developer ID`. Added to
`make release` as the final assertion so a failed notarization cannot
silently produce a broken DMG.

---

## Files affected

### New
- `Resources/Entitlements.plist`
- `.github/workflows/release.yml`
- `.github/scripts/bump-cask.sh`
- `release/cask-template.rb`

### Modified
- `Resources/Info.plist` — bundle ID rename
- `Makefile` — add `sign`, `notarize`, `release` targets; version stamping
- `Sources/ClaudeResourceIndicator/AppDelegate.swift` — legacy LaunchAgent
  cleanup
- `README.md` — install instructions, drop the `xattr` workaround,
  document tagged-release flow

### In separate repo (`amsterdamse-software-makkerij/homebrew-tap`)
- `Casks/claude-resource-indicator.rb` (created by first release bot run)
- `.github/workflows/ci.yml` (committed by hand)
- `README.md` (committed by hand)

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Notarization fails silently → broken DMG ships | `spctl` assertion in `make release`; CI fails before publish if it doesn't pass |
| PAT expires unnoticed → tap PRs stop opening | Calendar reminder; failure surfaces in Actions logs immediately |
| `apple-actions/import-codesign-certs` becomes unmaintained | Thin enough to inline as a shell step if needed |
| Existing local installs (com.andrei.*) orphan their LaunchAgent | One-time cleanup on first launch of the renamed app |
| First-time user has Claude Code unsigned-in → app shows error | Already handled by existing code (keychain-miss path) |
| User runs `brew uninstall` while app is running | `quit:` stanza handles it |
| GH Actions macOS runner image drift breaks `notarytool` path | Pin to `macos-14`; revisit yearly |

## Open questions

None — all design decisions confirmed during brainstorming on 2026-06-14.
