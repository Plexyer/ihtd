# Making IHTD public safely: owner and implementation guide

**Owner steps completed and verified on 2026-10-15:** repository public,
branch/tag patterns corrected, AGPLv3 selected. See the verification section
below; remaining release/signing/phone checks are separate.

Prepared 2026-10-15. No visibility change or secret audit has happened as part of
this planning task. Public source and public releases allow anonymous in-app
update discovery/download. GitHub Actions secrets remain private after a visibility
change, but that does not make committed history or build outputs safe.

## 1. Keep it private until the audit is complete

The implementing model must audit first and give you a sanitized report stating
what was inspected, limitations, findings and whether public conversion is ready.
Do not paste credentials into chat or commit audit output. Keep independent
private backups of the repository and permanent signing key/password. Confirm
that your home backups can be recovered; never upload these as release assets.

Audit scope:

- Fetch and enumerate all remote branches/tags and full reachable history, not
  just the current checkout. Inspect deleted/renamed files and old commits with
  a reputable history secret scanner plus targeted review for private keys,
  keystores/P12/JKS/PEM, passwords, tokens, service credentials, .env files,
  personal .ihtd collections/SQLite data, exports, logs and personal information.
  Scanner detection is evidence, not a guarantee; review false positives safely.
- Inspect every branch, including codex/android-build11-download, and the APK
  contents/resources/native configuration for embedded credentials or private
  files. An APK necessarily contains public certificate/application information;
  the private signing key must not be inside it.
- Review workflow files and historical build logs/artifacts/caches, Releases and
  assets, issues/PRs/comments/attachments, wiki/discussions if enabled, and linked
  hosting/integrations. Some hidden/unreachable or pull-request refs, cached views,
  deleted assets and forks may not be covered by a normal clone: state gaps and
  consult current GitHub sensitive-data-removal documentation/support as needed.
- Check Actions trust boundaries: no untrusted fork code gets signing secrets;
  no unsafe pull_request_target checkout/execution, token permissions minimized,
  publishing restricted, third-party actions reviewed/pinned as appropriate,
  protected android-release environment and release tags/rules verified. Verify
  actual settings rather than relying on old checklist assumptions.

## 2. If confidential material is found

Keep the repository private. Revoke/rotate exposed service credentials even if
history will be cleaned: deleting a file does not invalidate a credential.
For Android permanent signing-key exposure, stop and discuss installed-user
compatibility and signing migration with the owner before replacing anything.
Do not disclose secret values in issues, PRs or scanner reports.

Choose remediation after reviewing findings:

1. **Clean existing history:** an approved git-filter-repo-style rewrite can
   remove sensitive blobs across affected refs. This changes commit hashes,
   invalidates signatures/links and requires coordinated force pushes and fresh
   clones. Copies, caches, PR refs and forks may remain; follow GitHub's removal
   procedure and contact Support where necessary. Existing release tags must not
   be casually moved or reused. Plan release provenance explicitly.
2. **Create a clean public repository:** import a reviewed clean snapshot without
   old Git history, migrate only sanitized docs/issues/assets, retain the old repo
   privately and update origin/workflow/update-feed references. Recreate secret
   settings privately through GitHub, not as committed files. Preserve app IDs,
   package IDs, signing identity, versions and support/recovery directory identity
   so installed apps can still upgrade. A new repo does not revoke exposed keys.

The model must prepare a concrete remediation proposal for your approval before
rewriting history, force-pushing, deleting refs or relocating the project.

## Required correction found during the audit

The 2026-10-15 audit found literal double quotes in the existing GitHub ref
patterns. Correct these before public conversion/release; removing quotes in a
document does not change GitHub settings.

1. In **Settings → Rules → Rulesets**, edit the master ruleset (currently named
   `mater branch`). Change its target branch pattern from `"master"` to `master`
   **without quotation marks**, retain required PR/check/force-push/deletion rules,
   and save. The API representation should be `refs/heads/master`.
2. Edit the development ruleset: `"development"` → `development`, without quotes;
   API include `refs/heads/development`. Keep Development checks required.
3. Edit the version release tag ruleset: `"v*"` → `v*`, without quotes; API include
   `refs/tags/v*`. Retain update/deletion protection for immutable release tags.
4. In **Settings → Environments → android-release**, edit the deployment tag
   pattern `"v*"` to `v*`, without quotes. Keep its type **Tag**, rather than Branch;
   do not broaden deployment access to arbitrary branches/PRs.
5. Verify the rules actually apply to master/development and version tags, and
   that protected tag signing can run for an approved reviewed release. If needed,
   ask the model to recheck the APIs after saving. Keep keys/secrets unchanged.

## 3. Choose how others may use the code

Choose and add an open-source LICENSE before announcing the project as open
source. Public visibility alone lets people view code but does not grant a full
open-source license. MIT/Apache-2.0 offer permissive reuse; GPLv3 requires covered
distributed derivatives to retain its source/license obligations. Have the model
explain tradeoffs if undecided; do not pick a license on your behalf. Verify
third-party notices for Flutter/Rust/native dependencies and bundled runtimes.
Review README/support instructions and remove unintended personal information.

## 4. Change visibility yourself, after a clean go/no-go report

1. Sign in to GitHub as an administrator of Plexyer/ihtd.
2. Open repository **Settings → General → Danger Zone → Change repository
   visibility** (labels may change), choose **Public**, read GitHub's warnings
   and complete the repository-name confirmation.
3. Recheck master/development protections and release-tag rules, Actions token
   defaults, fork-workflow approval policy, protected android-release environment,
   secret scopes and required reviewers/deployment restrictions. Visibility/plan
   changes can affect protections/features: verify the actual controls available.
4. Enable available secret scanning/push protection and dependency/security alerts.
   These complement, rather than replace, the history audit and credential rotation.
5. Tell the implementing model the change is complete. It should verify access
   anonymously and update stale documentation that calls the repo private.

Secrets stored through GitHub's Secrets interface are not made public by this
change. Workflow source, commits, branches, public collaboration history, release
assets and potentially Actions logs/artifacts become accessible under GitHub's
rules. Never rely on log masking to protect a secret deliberately printed by code.
Do not put a GitHub token into the app to work around access failures.

## 5. Publish the first usable update

1. Finish signing backups/settings and required physical acceptance. Signing
   configuration may already have been performed: verify current state rather
   than re-uploading or regenerating keys unnecessarily.
2. Merge reviewed work into development, then a release candidate into master.
   Select a version higher than installed test candidates: Android build numbers
   must exceed all APKs you intend to update (the shared candidate was build 11).
3. Create a matching new immutable vX.Y.Z tag on the reviewed master commit;
   let the coordinated workflow build and assemble all platforms into its draft.
4. Review every installer, signature, update metadata, checksum and release note.
   Publish as a **stable release**, clearing prerelease status, and set latest
   consistently with the updater's stable-selection contract. Missing or failed
   packages must not be advertised as ready. Do not overwrite distributed tags.
5. In a signed-out/private browser, verify release and direct package downloads.
   Then test the updater-enabled app on both phones and applicable desktops.

Existing build-11 installations have no updater yet. Install the first
updater-enabled, same-key/higher-build APK manually once on each phone; subsequent
published compatible releases can follow the in-app workflow. Do not uninstall
first. Public releases do not require permanently committing binary APKs to Git;
use Releases for normal distribution. Keep the temporary download branch out of
source integration branches.

## What you need to do manually

- Keep independent signing backups and confirm recovery.
- Review the model's sanitized audit/remediation report and approve any destructive
  cleanup or repository replacement if needed.
- Choose the source license.
- Change visibility only after the audit is cleared; verify administrator-only
  security/protection settings and signing secrets as required.
- Review/publish the stable release and perform physical upgrade acceptance.

The model can prepare source changes, metadata, audits and PRs. This guide does
not authorize it to change visibility, rewrite history or publish a stable release
without the corresponding explicit owner action/approval.

## Verification after owner changes (2026-10-15)

- Public repository metadata confirms visibility=public; signed-out GitHub web
  pages expose the repository and published release, while draft releases stay
  absent from that signed-out release page.
- All three rulesets now target unquoted refs/heads/master,
  refs/heads/development and refs/tags/v*. Both actual branches have effective
  PR/status/deletion/force-push rules; required checks match the workflow names.
- android-release deployment restriction is type Tag, pattern v*, without quotes.
- Public published-release checksum/RPM downloads succeed and the RPM SHA-256
  matches the published checksums. Source README is publicly readable.
- The cloud API connection automatically authenticates requests (even with no
  user-supplied token header); public-access conclusions therefore also use the
  signed-out web state and visibility metadata, not API HTTP 200 alone. Drafts
  seen through this authenticated API are not evidence of public draft exposure.
- Only an old prerelease is published. No stable update.json/APK feed exists yet;
  merge/release review and actual two-phone upgrade tests remain necessary.
- Owner explicitly chose AGPLv3 with its network-interaction condition; adopt
  AGPL-3.0-only. Its LICENSE/metadata/notice changes must reach master before the
  default repository page detects the license and new official packages include it.

The original remediation/visibility instructions above are retained for reference;
the quoted-pattern correction and visibility change are now completed.
