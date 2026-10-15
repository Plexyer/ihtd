# In-app updates: implementation handoff

Owner decisions recorded 2026-10-15. Shared implementation is now present; see execution evidence below.
Read AGENTS.md, REQUIREMENTS.md, FEATURE_CHECKLIST.md and shared-app-architecture.md.
Work in dependency order; update evidence and outstanding acceptance after each step.

## Approved experience

Move the drawer/menu button from the app header to immediately before the current
view name (including All tasks). Preserve drawer access, keyboard focus, large text
and wide-screen sidebar behavior. Reserve the header's former leading position for
updates. Hide its update icon when no newer compatible stable release is known.

1. New release: blue downward arrow within a light-blue circle.
2. Tap: shared popup shows installed/new versions, release notes, compatible
   package and size, plus Download/Cancel. Render release notes safely; no scripts.
3. Confirm: close popup, then start download. User continues editing. Animate the
   surrounding circle and a downward flow on the arrow; show accessible progress
   when total size is known, indeterminate progress otherwise. Do not fake progress.
4. Only after successful integrity and authenticity verification: stop animation
   and show a green tick within a green circle, labelled Ready to install.
5. Tap green tick on Android: prepare local recovery, then invoke Android's own
   installer. No second IHTD installation confirmation. Use Android's source
   permission/settings prompt if needed; return safely and require a fresh action
   if the OS does not automatically resume the installation flow.
6. Android owns the final confirmation and installation. Cancel/reject/failure
   retains the verified ready package and permits retry. Launching the installer
   is not evidence that installation succeeded. Reopening IHTD reads its actual
   installed version: hide the icon if up to date, or retain/reconcile state if not.
   Android may close the app and may require the user to tap Open/reopen manually;
   do not promise automatic restart or silent installation.

Reduced-motion settings replace motion with static progress/text. Colour must
not be the only status indicator. Errors expose a short explanation and Retry;
verification failure must never produce a green tick. The update indicator must
not replace, clear or obscure document save/recovery warnings.

## Decisions and constraints

- Use published stable GitHub Releases from Plexyer/ihtd after its public-safety
  gate. No embedded GitHub credentials, no user login needed for downloads.
- A master merge is not an update: existing reviewed master -> immutable vX.Y.Z
  tag -> all-platform build -> draft prerelease -> owner review -> published
  stable release remains the release policy. Do not silently change CI triggers.
- User approved public distribution; changing repository visibility still waits
  for the audit and owner's manual action in public-repository-guide.md.
- Stable channel only in this milestone. Do not turn the build-11 download branch
  into an update feed or treat Actions artifacts, drafts or prereleases as stable.
- Proposal for automatic checks: on first eligible start and at most every 24h,
  respecting persisted preference/backoff; Check for updates bypasses the interval.
  Provide an automatic-checks toggle and explain GitHub receives network requests.
  No telemetry or collection data in update requests. Network-free editing remains.
- Owner confirmed: downloads continue when minimized or the phone locks, using
  Android background download facilities and normal system notification. Do not
  claim suspended-process reliability without native background integration.
- Owner has desired license terms but no license selected. Define those terms
  together later and compare suitable licenses; tracked explicitly in the checklist.

## 1. Audit repository before public distribution

- [ ] Follow public-repository-guide.md: full reachable history and all remote
  branches/tags, release assets, artifacts/logs and collaboration metadata.
- [x] Record sanitized findings and a go/no-go report. Never commit discovered
  secrets, raw scanner output, tokens, signing files or private collection data.
- [ ] For any exposure, stop public conversion; rotate/revoke credentials first.
  Permanent Android signing-key exposure requires a separate owner decision:
  replacing it can break updates for installed APKs. Never casually regenerate it.
- [ ] Prepare remediation options (history cleanup or clean repository) and ask
  for approval before destructive history rewrites or repository relocation.
- [ ] After owner changes visibility, verify release metadata/assets anonymously
  with no inherited GH_TOKEN/helper. Public API read success with a token is not
  proof of public availability. Never disclose credential-bearing download URLs.

## 2. Establish release/update contract and trust

- [x] Inspect actual source/version and published releases anew. Authoritative
  app/pubspec.yaml supplies X.Y.Z+BUILD; read installed values from package APIs,
  not a hardcoded Dart constant. Build 11 is a test candidate, not a stable feed.
- [x] Define versioned, bounded update metadata per release: version/build, tag,
  source commit, platform/arch/package format, minimum OS, filename, exact bytes,
  SHA-256, release-notes reference and installer identity. Reject ambiguous assets,
  mismatches, duplicates, unsupported schema, wrong architecture and downgrades.
  Android requires strictly higher versionCode as well as coherent versionName;
  compare semantic versions correctly, not lexicographically. Fetch OS/ABI facts
  through capabilities, including Samsung compatibility; do not infer from brand.
- [x] Extend scripts/assemble-release.py and its tests to produce metadata only
  after every required package passes. Publish metadata with complete assets.
  Preserve pinned Android certificate, ELF/ZIP 16 KB verification and immutable
  tags. Do not mark a partial release stable/latest. Document exact release step.
- [x] Decide and document manifest trust before implementing installation. HTTPS
  and SHA256SUMS from the same server detect corruption, not publisher authenticity.
  Android must cryptographically verify APK signature/certificate against the
  installed app and pinned permanent identity (or explicitly supported signing
  lineage), package ID dev.ihtd.app, versionCode, OS and ABI. Parsing certificate
  metadata alone is not signature verification. Use vetted/native verification;
  document threat model and avoid hand-written cryptography.
- [ ] Windows needs trusted Authenticode signer verification before app-launched
  installer execution; Fedora needs trusted RPM signing verification. A signed
  update manifest with an independently embedded trust key is an option; if chosen,
  design protected signing, rotation and offline recovery, never embed private keys.
  Current unsigned desktop packages are blockers to automatic install handoff;
  show an honest manual release-page fallback until verification is available.
- [x] Handle GitHub pagination/rate limits/cache validators/offline states and
  retry-after. Never interpret an API/network failure as proof the app is current.
  Reject unexpected download schemes/hosts, unsafe filenames/paths, excessive
  metadata/package sizes and redirect loops. Allow documented GitHub asset/CDN
  redirect hosts without forwarding credentials. Bound disk use and timeouts.

## 3. Implement shared update service and adapters

- [x] Add typed contracts under app/lib/services/: release source, installed
  identity, package selector, downloader, verifier, installer adapter, persisted
  update store; select platform adapters only at composition/bootstrap.
- [x] Shared coordinator owns eligibility/version policy, state, progress, errors,
  dialogs and user intent. Suggested states: idle/checking/available/downloading/
  verifying/ready/handed-off/error; distinguish cancellation and installation
  outcomes. Use attempt IDs to reject stale events; single active download.
- [x] Persist selected release/identity, completed private package and verified
  digest atomically. Revalidate cache after restart and before handoff; invalidate
  corrupt, obsolete or incompatible packages. Never trust a stored ready flag.
  Resume partial downloads only with validated server identity/range semantics;
  otherwise safely restart. No unbounded polling or silent re-downloads.
- [x] Switching collection/view does not reset downloads; update storage is
  separate from documents/recovery. Bounded diagnostic events use existing privacy
  principles; never log tokens, document content/paths or signed URL queries.

## 4. Shared UI and safe handoff preparation

- [x] Implement agreed header/view-menu move in app/lib/ui/app_shell.dart and
  shared update widgets/dialogs. Use layout constraints, not OS-name branches.
- [x] Add Check for updates and automatic-check preference to appropriate menu/
  settings. Manual checks explain no update/offline/rate limit/unsupported device.
- [x] Implement approved icon/dialog/progress/error states, screen-reader labels,
  focus order, reduced motion, narrow/large-text and desktop behavior. A download
  should not steal focus or reopen its dismissed popup.
- [x] Before installer handoff, flush debounced edits and active editor drafts
  through existing shared controller/coordinator. Invalid drafts/private write
  failures block handoff with actionable feedback. Unpublished external changes
  must remain durable locally; do not force reconnect, clear save barriers or
  require unsafe publication to install. Add a warning only if necessary to
  explain unresolved data risk, not a redundant routine install confirmation.
- [x] Preserve app support directory, working copies, recovery, document grants
  and schema compatibility. Never uninstall first or delete user data.

## 5. Android adapter: Pixel/GrapheneOS and Samsung

- [x] Audit target SDK and current MainActivity/manifest. Add INTERNET permission
  to release manifest (currently absent); request no broad storage permission.
  Add REQUEST_INSTALL_PACKAGES only for this legitimate user-initiated updater;
  document distribution/store-policy consequences for any future Play release.
- [x] Implement native download/cache handoff and restrictive FileProvider or
  equivalent content URI with temporary read grant and APK MIME type. Never expose
  file://, arbitrary private files, exported writable paths or signing secrets.
- [x] Use an appropriate Android background download
  service with network/lifecycle handling and system notification; verify modern
  Android background restrictions, destination access and privacy. Restore state
  from native work after process death. Describe OS force-stop limitations.
- [x] Check canRequestPackageInstalls; use system source-permission settings,
  handle refusal/back/resume, then native installer intent/PackageInstaller as
  appropriate. Do not prompt for permission before the user requests installation.
- [x] Native verifier/installer reports typed observations; shared service owns
  messages and state. Handle unavailable handler, cancellation, insufficient
  storage, bad signature, version incompatibility and interrupted installation.
- [ ] Build permanent-key upgrade candidates with increasing versionCode, verify
  certificate and 16 KB alignment. Samsung model/OS/ABI must be recorded during
  acceptance; no weakening of GrapheneOS/Samsung security settings or Play dependency.

## 6. Windows and Fedora adapters

- [x] Use the same coordinator/UI. Report actual installation type and capabilities;
  do not auto-select portable replacement for a package-managed installation.
- [ ] Windows: verified signed setup EXE, fixed argument handling (no shell
  interpolation), preserved Inno AppId, graceful handoff/exit and actual post-start
  version reconciliation. Honour OS prompts; restart only if supported/tested.
- [ ] Fedora: verified compatible RPM handed to available graphical package tooling;
  package manager owns authentication/files. If repository-managed, guide to
  DNF/GNOME Software instead. Portable archives remain manual in this milestone.
- [x] If native signing prerequisites are not ready, document the limitation and
  retain safe release-page/manual download flow. Do not claim all-platform
  automatic installation based on Android completion.

## 7. Verification and release acceptance

- [x] Unit/contract tests: versions/builds, asset/OS/ABI selection, draft/prerelease
  exclusion, missing assets, malicious metadata, redirects, trust failures, offline/
  rate limits, progress, retries/cancel, stale events, interrupted downloads,
  persisted recovery, cache tampering, install cancellation and actual-version checks.
- [x] Widget tests: moved menu, exact popup sequence, no duplicate Android confirm,
  blue/progress/green states, large text, screen readers, reduced motion, document
  warning coexistence and install blocked by unflushed/invalid editor state.
- [ ] Native tests verify APK signatures (not just fields), wrong key/package/build,
  provider URI/grants, source permission and OS handoff; desktop checks appropriate
  to enabled capabilities. Run relevant architecture/release checks and native CI.
- [ ] Physical two-build upgrade on Pixel/GrapheneOS AND father's Samsung: public
  anonymous discovery/download, continued editing, background/lock behavior,
  network loss, permission denial, installer cancel, successful in-place upgrade,
  reopen/icon clearing, document/grant/recovery preservation and offline operation.
  Repeat applicable checks on Windows and Fedora before claiming support.
- [ ] Update REQUIREMENTS.md, checklist, architecture, building/release docs and
  create a reusable physical acceptance guide. Keep unchecked evidence honest.
  Commit/push task branch, PR to development; owner merges. Public conversion,
  stable publication and any destructive remediation are separate owner actions.

## Execution evidence (2026-10-15)

Shared coordinator/catalog/UI, production update metadata, native Android
DownloadManager/apksig/installer and unsigned-desktop manual fallback are
implemented. See [implementation and acceptance](update-acceptance.md) and
[publication audit](publication-audit.md). Automated checks cover 126 Flutter
unit/widget tests, clean analysis, production metadata/pin boundary checks,
cryptographic signed/tampered APK JVM verification and real Linux UI integration.

Keep public conversion/license/security-owner review, anonymous feed verification,
physical Pixel/Samsung/desktop acceptance and trusted desktop package signing open.
No visibility change, history rewrite, stable publication or signing-key change
has been performed. Native Android download/installer lifecycle behavior must
still be verified on both actual phones.
