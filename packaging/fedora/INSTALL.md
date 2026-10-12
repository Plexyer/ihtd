# IHTD 0.2.1 for Fedora 44 (Intel/AMD, x86-64)

Copy `ihtd-0.2.1-1.fc44.x86_64.rpm` to your Fedora laptop. In a terminal opened
in the folder containing it, run:

```sh
sudo dnf install ./ihtd-0.2.1-1.fc44.x86_64.rpm
```

Launch **IHTD** from the application menu, or run `ihtd` in a terminal.
Choose **Open collection** and select your `.ihtd` file. Your rclone-mounted
Google Drive is an ordinary folder for this purpose. Edit on one device at a
time and allow the mount/sync client to finish before switching devices.

Flutter and Rust are included in the compiled application; you do not need to
install development tools. DNF installs the system libraries the app needs.
This prototype RPM is unsigned and is intended for local installation.

## Portable alternative

Extract `IHTD-0.2.1-fedora44-x86_64.tar.gz` and run `IHTD/ihtd`. Keep the entire
`IHTD` folder together, including `lib` and `data`. This bundle targets Fedora 44
and still requires its system libraries; the RPM is the recommended option
because it installs those dependencies automatically.

## Check the downloaded files

If you also copied `SHA256SUMS` and both package files into the same directory:

```sh
sha256sum -c SHA256SUMS
```

For a laptop check, open a collection, add a task, move it into a folder, close
and reopen the app, then verify the saved task. Native file-picker behavior,
Wayland, display scaling, and your rclone mount should be checked on the laptop.

To uninstall the application, run `sudo dnf remove ihtd`. Your `.ihtd` files
are stored separately and are not part of the installed package.
