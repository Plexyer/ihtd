# Update implementation and physical acceptance

Implementation candidate: 0.2.3 build 12. This is not a published stable release.
The repository is still private; anonymous update discovery will report public
releases unavailable until the owner clears publication. No credential is embedded
in the app. See [publication audit](publication-audit.md) and
[public conversion guide](public-repository-guide.md).

## Implemented boundaries and trust

`update_contract.dart` defines installed identity, candidate and typed adapters.
`update_catalog.dart` reads bounded anonymous GitHub data, excludes drafts and
prereleases, checks complete update metadata/assets, semantic versions, Android
build codes and OS/architecture compatibility. Requests use timeouts, bounded
redirects/hosts, ETags and rate-limit backoff. Automatic checks are at most daily;
manual checks and a persistent automatic-check switch are in File → Check for updates.

`update_coordinator.dart` owns state, private persisted intent/preferences,
progress, restart reconciliation and verification-before-ready/install. UI is
shared under `ui/app_updates.dart`; platform selection is in
`update_composition.dart`. Native Android `UpdateBridge` uses DownloadManager for
background downloads and restrictive read-only FileProvider handoff. `ApkTrust`
uses Google's apksig verifier plus the pinned permanent certificate. Android also
checks installed signer, package ID, higher versionCode, versionName/minSdk and
ARM64 library presence. Hash/size checks alone are never publisher authentication.

Unsigned update metadata is protected in transit by HTTPS; GitHub/release account
integrity determines discovery/availability/notes. APK cryptographic verification
against the installed/pinned identity supplies independent installer authenticity.
This milestone supports one permanent Android signer, not signing-key rotation.
Compromised GitHub metadata cannot authorize an APK signed by another key, but can
mislead notes or deny discovery. Future desktop automatic installation requires
trusted package signatures (or an independently trusted signed-manifest design).

Windows and Fedora use the same discovery/UI, with **Open release page** for
manual installation because their current packages are unsigned. Fedora RPMs are
offered only on Fedora 44 x64; portable installs stay manual. No desktop automatic
shutdown/restart or signed-installer support is claimed complete.

The Android system handles downloading in the background; progress/verification
and the green icon reconcile when IHTD is active again. Network changes and OS
force-stop/battery restrictions can pause or interrupt work. DownloadManager's
notification is visible during downloading; no completion shortcut bypasses the
app's local-save preparation. Files remain in app-scoped update locations; no
broad storage permission is requested. DownloadManager controls transfers while
IHTD is suspended: the app checks expected size when observing/completing a job,
but cannot enforce a streaming byte limit during suspension. Initial URLs are
fixed official GitHub release URLs; signature verification still blocks untrusted
packages. Failed transfers restart on explicit Retry rather than claiming HTTP
range resume. Caches contain one candidate. No update telemetry is sent.

Before installation, the shared controller flushes valid item drafts and writes
the existing local document checkpoint. Disconnected-file barriers are retained;
external publication is not forced. Invalid/private-persistence-failed edits block
handoff. View-creation dialogs remain modal; they must be finished/cancelled before
header actions are accessible. Android's own source permission/installation UI
supplies confirmation. The app never treats launching it as installation success.

## Release and first installation

The release assembler adds `update.json` and its checksum only for production
all-platform assembly. It records the immutable commit, version/build, exact
package names/sizes/hashes, Android signing identity/minimum API and Fedora target.
All ordinary PR/master/tag trigger behavior remains as documented in
[development policy](development-workflow.md). Only owner-reviewed published
stable releases with complete assets are eligible; drafts/prereleases are not.

Build-11 phones must install the first updater-enabled same-key, higher-build APK
manually once. Do not uninstall. To test actual discovery/upgrade, publish a later
reviewed version with a higher semantic version and Android build number through
the normal release process. Do not reuse distributed tags or replace assets.
Do not publish a dummy test release as stable merely to make an icon appear.

## Required physical acceptance (not yet run)

Record model, Android version/API, installed build/certificate and result for
both Pixel 9 Pro/GrapheneOS and the father's Samsung (must be ARM64, API 35+).
Use disposable collections and independent backups of important data.

- [ ] Install updater-enabled candidate over existing permanently signed IHTD;
  verify document access, views, edits and pending local recovery survive.
- [ ] On a public compatible later stable release, verify blue icon; drafts,
  prereleases, legacy releases without metadata and incompatible builds must
  not be offered as verified in-app updates.
- [ ] Open popup: versions/builds, size and notes are clear. Cancel changes nothing.
  Download closes popup before animation; continue editing a task and using views.
- [ ] Minimize, lock/unlock and reopen during transfer; verify Android downloading
  notification and restored progress. Test process recreation. Test force-stop
  separately and record actual OS behavior without assuming uninterrupted work.
- [ ] Lose/recover network; test failed download, retry, low storage and denied
  roaming network. No failed/unverified package may produce a green tick.
- [ ] Finish download; verify animation stops, green tick is accessible. Tap it:
  flush edits then native source-permission/installer UI, no duplicate IHTD install
  popup. Deny permission, return and tap again; grant it, then cancel installer.
  App/version remain unchanged and installation can be retried.
- [ ] Install successfully without uninstalling. Reopen (or tap system Open):
  installed version is correct; update icon disappears. Check tasks, linked items,
  views, SAF grants, disconnected-file warnings and local working/recovery copies.
- [ ] Attempt handoff with invalid/unsaved item fields and simulated private-save
  failure: block safely; preserve content. With a safely retained external-file
  conflict, preserve its warning/recovery through upgrade without overwriting it.
- [ ] Verify no Play-services requirement and normal offline editing. Disable
  automatic checks, restart, confirm preference persists. Manual offline/rate-limit
  check explains failure rather than claiming the app is current.
- [ ] Inspect drawer menu beside view name, header spacing, blue/progress/green
  states, screen readers, reduced motion, 2x text and portrait/landscape.
- [ ] On Windows 11 and Fedora 44, verify responsive shared UI and correct manual
  release-page/package guidance, browser failure and disabled automatic checks.
  Signed package automatic handoff remains a separate checklist dependency.

Host unit/native tests do not replace these two-phone and desktop acceptance checks.
