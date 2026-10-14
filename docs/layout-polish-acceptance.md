# Clipping and surface acceptance

Use a disposable collection. The candidate is 0.2.2 build 9; it uses the
existing permanent Android identity and can update permanent-key build 8 without
uninstalling. Keep production collections and retained recovery copies intact.
Source/candidate provenance and verification results are recorded in
`layout-polish-plan.md`: native run 38552777010, source `e9d1346`. The signed
`IHTD-0.2.2-build9-android-arm64-test.apk` passes permanent-certificate, ELF and
ZIP alignment verification. These steps are physical acceptance, not completed
automatically by a successful native build or host screenshot.

## Pixel 9 Pro / GrapheneOS

1. Install the candidate over the existing app. Open the test collection; confirm
   the selected file, tasks and any pending-save warning still survive the update.
2. With the drawer closed, inspect the area behind the clock/status icons: it
   should continue the white header. The gesture area should continue the task
   canvas. Status and bottom areas may have different colors to match their
   respective adjacent surfaces.
3. Open/close the drawer several times, including slowly dragging it. Its top and
   bottom inset regions should match the sidebar. The main area remains dimmed
   by the usual drawer scrim. No extra system strip should appear at either end.
   Confirm MY COLLECTION and footer text remain clear of system controls.
4. Create a task and then a folder. With Title focused and the keyboard open,
   inspect the complete floating label and outline. Type, dismiss/reopen the
   keyboard, focus Notes, and scroll to the last fields. Create/Cancel must be
   reachable, and typed input must survive these transitions. Try an empty
   title once to check the validation message and then enter a valid title.
5. Edit a view with several conditions, including a group containing another
   group. Scroll completely to both ends. View name, the first rule label/card,
   the final condition and Add condition should each be fully readable when
   brought into view. Partly visible rows while scrolling are expected. Save
   a name/rule change, reopen it and confirm it was retained.
6. Repeat the editors in landscape and with larger OS font settings (including
   the largest practical setting). On short screens/large text, the header and
   actions scroll with the form; scroll down to Save/Create/Cancel. No controls
   should become unreachable or overlap the keyboard.
7. Check with OS light/dark appearance, keyboard opening/closing, and both
   gesture/three-button navigation if available. The app currently keeps its
   light palette. Clock/status/navigation icons should remain legible, including
   during dialogs and after they close. The keyboard controls its own navigation
   area while visible; IHTD should restore its surfaces after dismissal.
8. Open the save-warning details popup if a test warning is available; confirm
   the dialog still works, and saving/reconnection behavior is unchanged.

Record APK versionCode, GrapheneOS/Android versions, font/display scaling,
navigation mode and screenshots of any remaining seam/clipping. Physical
acceptance stays unchecked until these observations are supplied.

## Windows and Fedora

1. Try both editors in narrow and wide windows, then reduce the window height.
   Check first/last fields, nested conditions, wrapped actions and keyboard Tab
   navigation. Repeat with increased display/text scaling.
2. Create/edit/cancel tasks and views; confirm creation and filter semantics
   have not changed. Open the resulting collection again to verify saved edits.
3. Check the drawer at narrow widths and permanent sidebar at wider widths.
   Their surfaces should match the shared palette without altering task accents.
4. On Fedora, include the actual Wayland session; on Windows, test a normal
   installation upgrade. Keep file/recovery data during installer testing.

## Automated evidence

`test/layout_polish_test.dart` checks label paint clearance, reachable complete
controls across seven viewport/text/keyboard combinations and rendered safe-area
pixels. `integration_test/phone_layout_test.dart` includes actual Rust-backed
view edits and task creation with simulated keyboard insets, alongside its
existing editing/scrolling/dragging checks. Neither can reproduce Android's
native status/navigation bars, IME, device scaling or compositor exactly.

Optional host screenshots use the same layout tests, with the Navigator included
inside a RepaintBoundary so dialogs and scrims are captured. Pass
`--dart-define=LAYOUT_CAPTURE=/absolute/output/directory`. For readable text
instead of the test font, also pass `--dart-define=LAYOUT_FONT=/path/to/font.ttf`;
the test loads that font as the theme family and loads the built-in icon asset.
This is test-only and does not change the packaged app's fonts.
