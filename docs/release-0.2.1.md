# IHTD 0.2.1 release preparation

All platform branches share the Android implementation and descendant-move
changes. Merge the Android pull request first, followed by the Windows and
Fedora packaging pull requests. Each pull request targets `master`.

| Platform | Branch | Build location |
| --- | --- | --- |
| Android | `codex/pixel-grapheneos-android` | Cloud workspace, ARM64/API 35+ |
| Windows | `codex/windows-release-0.2.1` | GitHub Actions Windows 2022 runner |
| Fedora | `codex/fedora-release-0.2.1` | Disposable Fedora 44 container |

Android uses a development signing key. Export collections before uninstalling;
APKs built in a different workspace may use a different key and cannot update
the current installation. Durable signing remains unfinished.

Platform workflows keep compiled packages out of source control. Successful
push builds upload downloadable workflow artifacts and draft prereleases with
checksums. Draft releases must be reviewed before publication. Pull-request
builds validate and upload artifacts but do not create releases.

Pull requests targeting `master` are open:

- Android/shared changes: https://github.com/Plexyer/ihtd/pull/2
- Windows packaging: https://github.com/Plexyer/ihtd/pull/1
- Fedora packaging: https://github.com/Plexyer/ihtd/pull/3

On 2026-10-08, Android CI passed and uploaded its APK, installation guide and
checksums to the draft `v0.2.1-android-test` release. Fedora CI passed core,
adapter and UI tests, installed/verified the RPM and exercised release launch;
its RPM, portable tar.gz, instructions and checksums are in draft
`v0.2.1-fedora`. Check the native Windows workflow result before merging its PR.

The local Android 0.2.1 APK also passed signature and alignment verification and
retains the development key used by earlier APKs from this chat. The downloaded
CI APK was verified to use a different key. Use the local APK to update the
existing installation; export collections before changing signing keys.

GitHub API access recovered after the initial proxy refusals. Local release-asset
upload still returned `401 Bad credentials`, so the same-key workspace APK has
not been uploaded. A secure `IHTD_RELEASE_TOKEN` requirement is saved in the
environment draft for that operation; CI uploads use their own Actions token.
The draft also includes the Actions log-download host. Review/save pending
settings before retrying affected operations; a draft save is not publication.

The local Fedora builder installed and verified its SDK, but Docker's VFS copies
filled the 32 GB workspace before a build container could start. Disposable
build caches were removed to recover space. Native Fedora CI produced the
verified packages using the repository's container recipe.
