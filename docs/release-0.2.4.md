# IHTD 0.2.4 release preparation

The owner merged development into master through PR #20. The resulting commit
`defa21ad94dc78aeb091581083b8b13cb35489ff` is tagged `v0.2.3` (build 12).
[The tagged run](https://github.com/Plexyer/ihtd/actions/runs/38722977957) passed
the Android, Windows and Fedora build/test/package jobs, including native layout,
Windows installer upgrade/uninstall, and installed Fedora RPM verification.

## Why no 0.2.3 release was published

The separate protected Android signing job failed with
`Required Android signing secrets are missing`. All three values resolved to
empty strings. The owner reconfirmed the three names under the `android-release`
environment; the version-tag policy is correctly `v*` with type Tag.

GitHub requires a reusable-workflow caller to pass environment secrets, even
when the called job names that environment. The original caller omitted this
handoff. The correction passes exactly the three named signing secrets and
declares them optional on `workflow_call`, so unsigned PR/branch builds continue
without secrets. Only the production tag-gated `sign` job selects `android-release`
and exposes their values to the signing step. No secrets are copied into Git,
repository-level secrets, or normal build steps. See
[GitHub's documented behavior](https://docs.github.com/en/actions/sharing-automations/reusing-workflows#using-inputs-and-secrets-in-a-reusable-workflow).

Recovery also verified the CI APK locally using the existing permanent key,
including its package/version/build and native/ZIP 16 KB alignment. All eleven
assembled assets, ten checksums, source/license pointers and update metadata
passed local verification. They remain outside Git. Uploading those files from
this cloud session failed with HTTP 401 at `uploads.github.com`; the integration
also cannot inspect/manage environment secrets (HTTP 403). The empty draft
created during that attempt was removed; the immutable `v0.2.3` tag is retained.
No old release, key or distributed tag was replaced.

## Finish through normal review

1. Review/merge the release-fix PR into `master`. This is a small hotfix from
   master; merge it back into `development` as well to retain the correction and
   version bump. Master PRs must pass `All platforms validated`.
2. Pull master and confirm `python3 scripts/release-version.py --tag v0.2.4`
   reports version 0.2.4, build 13. Use a new immutable tag, not a moved v0.2.3.
3. Push `v0.2.4` on the reviewed master commit. Actions rebuilds all platforms,
   signs Android in the protected environment and uses its own Actions token to
   upload the complete draft. Branch/PR/manual tests cannot prove production
   secret access; check the actual `android / sign` job on this tag.
4. Verify the permanent APK certificate, version/build, complete asset names,
   hashes and `update.json` commit/package identities. Leave the draft unpublished
   until reviewed. An upload failure may leave a partial draft; remove only that
   failed draft before rerunning, without changing its tag.
5. Complete the physical phone/desktop acceptance and native dependency notice
   inventory before stable publication. Install this first updater-enabled APK
   manually over the same-key older build, without uninstalling. A later higher
   compatible stable release can then appear through the app's updater.

Planned files: Android ARM64 APK; Windows x64 setup EXE and portable ZIP; Fedora
44 x86-64 RPM and portable tar.gz; three installation guides; public Android
certificate fingerprint; `SHA256SUMS`; `update.json`. Drafts/prereleases remain
excluded from update discovery.
