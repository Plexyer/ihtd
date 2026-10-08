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

This cloud environment permits Git synchronization but its network proxy
currently refuses connections to `api.github.com`. Opening pull requests,
checking Actions results and uploading local APKs require that API access.
Do not infer a completed build or release upload from a pushed workflow.

The local Android 0.2.1 APK was built and its signature and 16 KB ZIP alignment
verified on 2026-10-08. It retains the workspace's earlier development key.
The Fedora dependency installation was refused by the network proxy; no new
Fedora packages were produced locally. Windows must build on its native Actions
runner. Workflow results and draft release uploads remain unverified here.

An additive network-settings draft includes `api.github.com`,
`uploads.github.com` and `*.fedoraproject.org`, preserving the existing SDK
download domain. Saving a draft does not activate it; review/save those settings
before retrying the blocked operations. Fedora's default metalinks may also
select external mirrors that need their own allowlist entries.
