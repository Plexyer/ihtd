# IHTD 0.2.1 for Windows 11 x64

Extract `IHTD-0.2.1-windows-x64.zip` and open `IHTD-0.2.1/ihtd.exe`.
Keep the entire folder together, including the DLLs and `data` directory.
No Flutter or Rust installation is needed. If a VCRUNTIME/MSVCP DLL is missing,
install Microsoft's Visual C++ x64 Redistributable.

Choose Open collection to open an existing `.ihtd` file. Documents remain
separate from the application folder. Back them up before switching versions,
and edit on one device at a time.

Version 0.2.1 includes the descendant-move rule: moving an item into its own
descendant promotes direct children to its former parent/top level, then places
the moved item under the destination. Their subtrees and IDs are preserved.

Verify the ZIP's SHA-256 using `Get-FileHash -Algorithm SHA256` and compare it
with `SHA256SUMS`. The portable application is not Authenticode-signed.
