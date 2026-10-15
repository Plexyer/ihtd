# IHTD licensing and source access

Owner decision, 2026-10-15: GNU Affero General Public License version 3 only,
SPDX `AGPL-3.0-only`. This grants version 3, without an automatic grant of future
AGPL versions. The complete, unmodified license is in [LICENSE](../LICENSE).
[COPYRIGHT](../COPYRIGHT) supplies the project notice. Third-party licenses and
notices continue to apply to their respective components.

## Meaning of this choice

Commercial use, selling copies, modification and redistribution are allowed.
Distributing a derivative/covered combined program requires licensing the covered
work under AGPL and supplying the corresponding source under the license's
conditions. This includes necessary build/install scripts, not just snippets of
changed code. Sections 5/6 describe distribution; section 13 additionally requires
operators of a modified network-interactive version to prominently offer its
corresponding source to the remote users interacting with it.

This is not a requirement to upload every private offline fork to GitHub, to
publish unrelated software or user data, or to contribute changes back to this
repository. Source rights go to recipients/network users under the relevant
conditions; those users may redistribute it. Merely running IHTD, handling .ihtd
files or communicating with a separate independent program does not automatically
put all other software under AGPL. Whether components form one derivative/combined
work depends on how they are integrated; an API boundary alone is not a blanket
exception to copyleft. The license governs when a combination is covered.

GNU GPLv3 has distribution copyleft too; GNU AGPLv3 adds the network-interaction
obligation above. The owner explicitly selected this additional obligation.

## Repository and binary notices

- Root LICENSE/COPYRIGHT cover IHTD's original source; Cargo package metadata and
  the Fedora project license field use AGPL-3.0-only.
- app/LICENSE mirrors root LICENSE so Flutter collects IHTD's license in its
  bundled notices. File → About and licenses provides the no-warranty/copyright
  notice, source link and Flutter's license browser.
- Windows portable ZIP/setup and Fedora portable/RPM packaging include LICENSE,
  COPYRIGHT and SOURCE.txt. Fedora also marks project texts as RPM license files.
- This change does not retroactively replace the notices/terms inside previously
  distributed APKs, ZIPs or RPMs. New licensed packages require a new reviewed
  build; do not overwrite distributed tags/assets to retrofit them.

For official release binaries, the matching immutable tag `vX.Y.Z` gives the
source and build scripts; GitHub's Source code archives contain that revision.
Keep source accessible alongside binary downloads and preserve it after an
update. Desktop packages record their actual source commit, including development/manual
builds. When packaging from a source archive or Docker context without .git,
supply IHTD_SOURCE_REVISION with that exact commit; Fedora CI passes it explicitly. Permanent private signing keys
and service credentials must stay private; supported build steps allow developers
to build and sign their own copies without using our release key.

## Before publishing licensed binaries

- Verify source for the exact distributed revision is available, including build
  scripts, lockfiles and any required generated bindings/installation information.
- Retain dependency licenses/notices, including Flutter/Dart packages, Rust and
  bundled SQLite/native libraries, Google's Android apksig, and platform runtimes.
  Flutter's notices collector covers Dart/Flutter packages; it is not a complete
  inventory of separately linked Rust/JNI/native/runtime components.
- Complete the native dependency notice/license-compatibility inventory before
  stable distribution. The project's AGPL grant does not relicense third-party
  components or remove their notice/redistribution conditions. Microsoft runtime
  files retain Microsoft's redistribution terms; assess applicable system-library
  exceptions and bundling requirements rather than claiming those DLLs are AGPL.
- Preserve existing third-party attributions and prepare package/source notices
  for any future dependency with additional obligations. Do not remove notices
  to make a package appear uniformly AGPL.
- Keep the private Android signing key out of source and release assets. No key
  rotation, tag rewrite, source-history rewrite or binary publication is part of
  this licensing change.

References: [AGPLv3](https://www.gnu.org/licenses/agpl-3.0.html),
[GNU's explanation](https://www.gnu.org/licenses/why-affero-gpl.html),
[GPL FAQ](https://www.gnu.org/licenses/gpl-faq.html).
