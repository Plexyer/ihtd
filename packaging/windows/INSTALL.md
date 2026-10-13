# IHTD @VERSION@ for Windows 11 x64

## Installer (recommended)

Download `IHTD-@VERSION@-windows-x64-setup.exe`, check its SHA-256 against
`SHA256SUMS`, and run it. Setup installs for the current Windows user under
`%LOCALAPPDATA%\Programs\IHTD` by default, without needing administrator rights.
It adds a Start Menu shortcut and offers an optional desktop shortcut and
registration for `.ihtd` collection files.

To open a collection from Explorer, use **Open with → IHTD**. Windows may ask
you to choose the application the first time; choose IHTD as the default if
desired. Setup does not replace another program's chosen default. Paths with
spaces or non-English characters are supported. Opening a document starts a
new IHTD window; avoid opening the same collection in two editing windows.

Close IHTD after its edits have saved before upgrading. Run the newer installer;
it reuses the installation directory and prior shortcut/registration choices.
Collections and recovery data are preserved. Remove IHTD through **Settings →
Apps → Installed apps**. Uninstall removes the program and its integration but
keeps collections, exports and application support/recovery data. Keep your own
backups; retained data is not a backup guarantee.

The installer, uninstaller and application are currently **unsigned**. Windows
SmartScreen may warn about an unknown publisher. Trusted Windows code signing
is a separate pending task; checksums detect corruption, not publisher identity.

## Portable ZIP

Extract `IHTD-@VERSION@-windows-x64.zip` and open `IHTD-@VERSION@/ihtd.exe`.
Keep the entire folder together, including the DLLs and `data` directory.
No Flutter, Rust or separate C++ runtime installation is needed: Microsoft's
redistributable runtime DLLs are included beside the executable. This option
does not add shortcuts or file registration. Application recovery data still
uses the user's application support directory, as with the installed version.

Choose Open collection to open an existing `.ihtd` file. Documents remain
separate from the application folder. Back them up before switching versions,
and edit on one device at a time.

Version 0.2.1 includes the descendant-move rule: moving an item into its own
descendant promotes direct children to its former parent/top level, then places
the moved item under the destination. Their subtrees and IDs are preserved.

Verify either download's SHA-256 using `Get-FileHash -Algorithm SHA256` and
compare it with `SHA256SUMS`. The portable application is also unsigned.
