# Development and releases

`master` holds reviewed release candidates. `development` integrates the next
version. Create short-lived `feature/*` or `fix/*` branches from `development`
(Codex task branches use `codex/*`) and open pull requests back into it.
When integration is ready, open a `development` → `master` pull request.

For longer stabilization, branch `release/x.y.z` from `development`, allow only
release fixes, merge it into `master`, then merge its fixes into `development`.
Urgent `hotfix/*` branches start from `master` and merge into both branches.
Delete completed task/release branches. Platform packaging lives together in
the same source tree; permanent platform branches are unnecessary.

## Version contract

`app/pubspec.yaml` is authoritative: `X.Y.Z+BUILD`. Increment the public version
for each new release and Android BUILD for every distributed update. Keep the
Fedora spec's Version field equal to X.Y.Z; validation rejects mismatches.
Run `python3 scripts/release-version.py` before building. Validate a planned tag
with `python3 scripts/release-version.py --tag vX.Y.Z`.
Flutter derives Android versionName/versionCode and Windows resource versions
from pubspec. Packaging derives names and rendered installation guides from it.
Historical release documents retain their original version numbers.

## CI and release process

Pull requests targeting `development` run `Development validation`: version
checks, Rust core/storage tests, Flutter analysis, and Dart adapter tests on one
Linux runner. This creates no installation packages. New commits to an open PR
rerun its checks and cancel a superseded run.

Pull requests targeting `master` run `Release validation`: the reusable Android,
Windows and Fedora workflows build the checked-out commit with read-only
permissions, then verify all three Actions artifacts together. Artifacts expire
after 14 days. Manual dispatch can also build any selected branch. Neither kind
of pull request creates a GitHub Release. Ordinary pushes/merges into master or
development trigger no automatic workflow, avoiding duplicate native builds.

After merging a reviewed release into `master`, create an immutable `vX.Y.Z`
tag on the chosen master commit and push it. The tag must match pubspec and its
commit must be reachable from master. Do not move or reuse a distributed tag.
The coordinator waits for all platforms, verifies expected filenames and each
checksum, and stages unique installation guides and one combined SHA256SUMS.
Windows contributes both the setup EXE and the complete portable ZIP. The
Windows workflow also supports a manual single-platform build on a task branch
for testing installer changes without waiting on other platforms.
Only its final job has release-write permission. It creates one **draft
prerelease** with generated notes and all packages. A failed build creates no
release. An upload failure can leave a partial draft; inspect and remove only
that failed draft before rerunning. Existing releases are never overwritten.

Review all files and notes before publishing. Android tag builds require the
protected signing environment and pinned release certificate described in
[Android signing](android-signing.md). Owner backups, secret activation and
physical-device update validation are required before stable public distribution.
The first permanent-key APK cannot update old development-key APKs. Checksums detect
corruption but do not replace publisher signatures. The repository is public (verified 2026-10-15); published release assets can be
downloaded without signing in. Draft releases remain private to authorized users.

## GitHub administrator settings

Protect master and development with pull requests, blocked force pushes and
deletions. Require `All platforms validated` on master and `Development checks`
on development. Remove `All platforms validated` from development's required
checks when adopting this policy: it no longer runs for development PRs and
would otherwise leave them waiting indefinitely. Require branches to be up to
date before merging. For a solo maintainer, approval count can remain
zero; enable reviewer approval when another maintainer can review. Set branch
protection after these checks have run so the names are available to select.
Prefer a tag ruleset preventing updates/deletion of `v*` tags.

The current integration credential returns HTTP 403 for branch-protection API
access. Apply these settings through an administrator account in GitHub's
Settings → Branches/Rules. This document describes intended protection; it does
not claim that protection has been enabled.

## Update discovery

Production coordinated assembly generates update.json (schema 1) after verifying
all packages and includes its SHA-256 in SHA256SUMS. The manifest records package
identities/minimum target, size/hash and source commit. It does not supply a
publisher signature: Android independently verifies APK cryptographic signatures
against its installed/pinned permanent identity. Desktop unsigned packages remain
manual. Only published stable, complete releases are advertised by the updater;
review the draft, clear prerelease status and publish as latest when ready.
Changing visibility requires the [audit and owner steps](public-repository-guide.md).
See [implementation/acceptance](update-acceptance.md) for first manual migration
and two-build test. No new push/merge workflows were introduced for updates.

## Upgrade candidate acceptance

The next stabilization candidate is 0.3.0+15. Step 12 adds actual pinned 0.2.5
installer upgrades, released-encoder fixtures and the separate
`upgrade-acceptance-kit` artifact. The tag release includes the synthetic ZIP
and checksum alongside existing complete runtime packages. Its presence does
not change updater package selection or publication triggers.

Review the task PR into development and the draft release/0.3.0 PR into master.
A permanently signed phone candidate still requires the normal reviewed master
tag. Publish that candidate as a **prerelease**, without latest, for direct
asset downloads during acceptance; stable discovery must ignore it. Promote
the exact tested assets only after physical acceptance and owner review.
See [instructions/results](upgrade-acceptance.md). Never replace an existing
distributed tag/package or use a differently signed APK to bypass this process.
