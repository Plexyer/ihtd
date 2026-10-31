# Upgrade acceptance results

Candidate target: 0.3.0+15. Baseline: v0.2.5+14.
Record the exact tested commit/package checksum; a build check is not a device result.

## Automated evidence

| Check | Result | Evidence |
| --- | --- | --- |
| Released v0.2.5 producer/provenance and SQLite preservation | Passed on Linux host | Historical producer, old-reader and fixture integrity/hash checks |
| Shared core/storage, Dart analysis and unit suites | Passed on Linux host | 117 Rust, 217 Flutter, 26 Python tests; Dart analysis clean |
| Native combined-feature upgrade/disconnect/restart | Passed on Linux host | Actual Rust/storage + Flutter, all three opening/migration cases, update draft barriers |
| Windows actual 0.2.5 installer → candidate, upgrade/removal/data | Pending native CI | Draft release PR |
| Fedora actual 0.2.5 RPM → candidate, upgrade/removal/private data | Pending native CI | Draft release PR |
| Android resources/native/provider tests and alignment | Pending native CI | Draft release PR |
| Permanent signing / complete tag assets | Pending reviewed master/tag run | Required before phone in-place testing |

## Device/package identity

| Target | Exact model / OS / API | From version/build | Candidate commit/hash | Result |
| --- | --- | --- | --- | --- |
| Pixel 9 Pro / GrapheneOS | Pending | Pending | Pending | Not run |
| Father's Samsung / Android | Pending | Pending | Pending | Not run |
| Windows 11 PC | Pending | Pending | Pending | Not run |
| Fedora 44 laptop / Wayland / rclone | Pending | Pending | Pending | Not run |

## Physical checks

Use Pass / Fail / Not run / Not available, plus notes. Do not check off other
platforms because one phone or a CI container passed.

| Case | Pixel | Samsung | Windows | Fedora | Notes/log reference |
| --- | --- | --- | --- | --- | --- |
| In-place installation and retained data/access | Not run | Not run | Not run | Not run | |
| Intact/customized/deleted-default opening | Not run | Not run | Not run | Not run | |
| Verified backup / cancelled permission / failure recovery | Not run | Not run | Not run | Not run | |
| Shared links, copying, unlink/delete and preserved children | Not run | Not run | Not run | Not run | |
| Draft Save/Cancel, cursor, exit prompts and restore | Not run | Not run | Not run | Not run | |
| Top Create / keyboard / short windows / large text | Not run | Not run | Not run | Not run | |
| Sorting / filtered drag / shared-parent protection | Not run | Not run | Not run | Not run | |
| Indicators / inheritance / tag search and popularity | Not run | Not run | Not run | Not run | |
| Rename/replacement/revoked access and pending restart | Not run | Not run | Not run | Not run | |
| Branding / startup / installed icons | Not run | Not run | Not run | Not run | |
| Stable updater states / OS handoff on a later release | Not run | Not run | Manual desktop | Manual desktop | Prereleases stay excluded |
| Native file picker / display scaling / provider or mount | Not run | Not run | Not run | Not run | |

## Issues and release decision

- Issue / reproduction steps:
- Expected / observed behavior:
- Synthetic test file / provider:
- Redacted log filename:
- Fix commit and retest:
- Stable promotion decision: **Pending physical acceptance and owner review**.
