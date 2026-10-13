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
Only its final job has release-write permission. It creates one **draft
prerelease** with generated notes and all packages. A failed build creates no
release. An upload failure can leave a partial draft; inspect and remove only
that failed draft before rerunning. Existing releases are never overwritten.

Review all files and notes before publishing. Permanent Android signing and
physical-device validation are still required before stable public distribution.
The development APK may not update previously installed APKs. Checksums detect
corruption but do not replace publisher signatures. The repository is private:
downloads require repository access until public distribution is configured.

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
