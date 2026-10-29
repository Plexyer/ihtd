# Shared priority icons

Implementation candidate, 2026-10-29; step 6 / specification item 8.

`app/lib/ui/priority_icon.dart` owns the shared design for Android, Windows and
Linux. Hierarchy rows and item/view-rule priority selectors use it:

| Value | Design | Color |
| --- | --- | --- |
| None (0) | No icon or reserved icon space | — |
| Low (1) | Rounded exclamation mark | Gray `#737B84` |
| Medium (2) | Rounded exclamation mark | Muted amber `#B78324` |
| High (3) | Rounded triangle outline with an exclamation mark | Red `#C44343` |

Material vector glyphs `priority_high_rounded` and `warning_amber_rounded` keep
the outline/mark scalable and consistent across platforms. High has an unfilled
interior and red mark; Medium avoids bright pure yellow. Rows retain their
18-pixel icon size, padding and existing placement. Labels/tooltips identify
the priority without depending only on color. Selectors retain visible text
and exclude decorative icons from their accessible name to avoid duplication.

Future summary counters must reuse `PriorityIcon(priority: ..., size: 14)`
rather than introducing separate artwork. Provide an accessible label for the
complete icon/count pair. Counter computation and layout remain the next task;
this step supplies their visual foundation only.

This is presentation-only: priorities retain their existing 0–3 values and
meaning. No model, storage, sorting, editor-draft or save policy changed, and
no migration or app version increment is needed.

Host verification passed: Flutter analysis, all 187 existing unit/widget tests,
17 Python release/architecture checks and the native Linux UI integration test.
A rendered preview was visually reviewed at 14/18/24/48 pixels. The ARM64
release APK built successfully and passed both native ELF LOAD and APK ZIP
16 KB alignment checks. These checks do not establish physical acceptance.

Before physical acceptance, verify Low/Medium/High in hierarchy rows and both
selectors on Pixel/GrapheneOS, Samsung, Windows and Fedora. Check small-size
legibility, large text, screen-reader labels and that None shows no symbol.
