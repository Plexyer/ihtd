# Public-distribution audit, 2026-10-15

Repository was private at inspection. No credentials were deliberately displayed,
rotated or changed; no history was rewritten. Raw downloaded material and redacted
scanner reports remain in private temporary workspace storage, outside Git.

## Evidence and scope

- Non-shallow checkout; fetched all current remote branches and tags and all 18
  available pull-request head refs. Gitleaks 8.30.1 full `--all` Git-history scan
  reported **zero findings**. Its downloaded archive matched the publisher's
  checksums. Review included historical/local refs, not just today's source tree.
- Targeted full-history path inventory found no tracked P12/JKS/keystore/PEM,
  password-text, .env or personal .ihtd files. Public certificate fingerprints
  are intentional; signing material remains outside the checkout.
- Retrieved repository issue/PR descriptions, issue/review comments and PR reviews,
  metadata for releases/actions, 65 available completed-run log archives,
  23 release assets, and 44 available Actions artifact archives. Inspected archive
  filenames and extracted/scanned small entries. Gitleaks found zero matches in
  the scanned surfaces. No private-key/keystore filenames were found in the
  artifact inventories. Counts describe this point-in-time inspection.
- Inspected workflow trust boundaries: ordinary PR builds have read-only tokens;
  protected production signing remains separated from builds. No
  pull_request_target execution of fork code was found. Three active rulesets
  are visible; android-release reports custom deployment-branch restrictions.

## Limits and owner actions before visibility change

This is evidence of no detected credentials, not proof that every byte is free of
confidential material. Scanner pattern matching cannot rule out encrypted,
obfuscated or custom-format secrets. Large binary entries were not exhaustively
reverse-engineered, nested archives were not exhaustively expanded, and deleted/
unreachable server objects, caches, external links/forks and all historic GitHub
metadata cannot be covered by a clone. Check any wiki/discussions or external
hosting manually if used. The credential could not inspect branch-protection or
secret-scanning APIs; verify actual protection settings as administrator.

Review public-facing personal information: historical setup/build docs include
workstation paths and usernames; author identities and public certificate details
will also be visible. These are not credential findings, but decide whether you
want them public. Removing today's text alone does not remove its history.

No detected secret currently calls for history removal or a new repository.
Finish the owner's desired-license discussion and administrator/manual review
using [the public repository guide](public-repository-guide.md). Keep the repo
private until that review is cleared. Rerun the scan after subsequent changes
and immediately before conversion. If any confidential material is found later,
rotate/revoke affected credentials and discuss cleanup before publication;
never replace the permanent Android key casually.
