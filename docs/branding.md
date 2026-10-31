# Branding, startup and update indicator

Implementation candidate, 2026-10-31. Covers step 11 / owner items 9 and 12.
The owner also chose branded initialization on Windows/Fedora with no added delay.
Physical platform/upgrade acceptance remains separate from host verification.

## One artwork source

`assets/branding/ihtd.svg` is the canonical mark: two solid blue lobes joined
from upper left to lower right, with a white tick in each. It follows the owner's
sketch from Changes.docx, refined into flat vector artwork. The original document
and image-generation working files are not part of the repository.

`scripts/generate-branding.py` generates and fingerprints the committed outputs:

- Shared Flutter transparent PNG for the header, About dialog and startup.
- Windows multi-resolution ICO (16, 24, 32, 48, 64, 128 and 256 pixels), used by
  the existing runner resource and Inno Setup installer.
- Fedora scalable SVG, used by the existing desktop/RPM integration. Linux also
  loads the bundled PNG for portable window icons, independently of working directory.
- Android legacy density PNGs, adaptive foreground/background and Android 13+
  themed monochrome icon. The monochrome path cuts out both ticks with even-odd
  fill. Adaptive control points fit within the documented 66dp safe circle.
- Android native launch and system-splash vectors, using the same geometry and
  conservative padding. Day/night startup themes retain the app's light surfaces
  and existing status/navigation-bar contrast behavior.

Edit the canonical vector, then regenerate; do not hand-edit platform images.
The source intentionally uses one blue and two white flat absolute M/L/C/Z paths.
Flatten transforms/styles when editing it. Generation needs Python, CairoSVG
(with native Cairo) and ImageMagick on PATH; ordinary app builds and `--check`
need none of these extra rendering tools. A Linux regeneration example:

```sh
python3 -m venv /tmp/ihtd-branding
/tmp/ihtd-branding/bin/pip install CairoSVG
/tmp/ihtd-branding/bin/python scripts/generate-branding.py
python3 scripts/generate-branding.py --check
```

The manifest binds the source, generator and complete output inventory; text
fingerprints normalize Windows CRLF while binary fingerprints stay byte-exact. Standard
Python CI tests detect drift, check ICO frames/PNG densities, and validate adaptive
padding, monochrome cutouts and Android splash references. Review the artwork
visually after regeneration; renderer versions can change raster byte encoding.

## Shared initialization and header

`IhtdLogo` is shared Flutter artwork with an accessible label. `IhtdApp` accepts
the real Rust initialization Future; the normal entry point starts Flutter with
the logo/progress screen while it is pending. Model services/AppShell are mounted
only after core initialization succeeds. There is no timer or minimum display
duration: fast startup may show it only briefly. A failed runtime initialization
keeps a branded restart message instead of opening uninitialized model services.
Collection restore/migration and its existing warning/recovery flow remain in
AppController after core startup. Branding does not delay those flows artificially.

The startup screen scrolls at short heights/enlarged text and uses the shared
header surface/overlay contrast. Android supplies the matching native launch
image before Flutter's first frame. Desktop first-frame startup uses the same
Flutter screen; the app/window/installer icons use their generated native formats.
Existing application IDs, support directories, file associations, package names,
installer identity, signing pins and collection formats remain unchanged.

`AppFileBar` shows the brand on the left. `AppUpdateButton` owns a permanent
48-by-48 logical-pixel slot immediately before the top-right file menu. With no
candidate it is empty and has no update action/tooltip. Available, downloading,
verifying, ready and error states all occupy that slot, keeping the filename,
brand and menu positions unchanged. Existing progress/color animation, reduced
motion, dialogs, verification and installation/save barriers are reused.

## Verification and remaining acceptance

Host checks include generated-asset verification, Flutter analysis/unit tests,
header bounds across phone/desktop/enlarged-text layouts and every update state,
initialization completion/failure, and existing update/surface/layout regressions.
Native desktop integration exercises actual Rust initialization before model
services and the new assets; Android build/alignment checks validate resources.

Before release on Pixel/GrapheneOS, Samsung, Windows and Fedora:

1. Verify in-app/About branding, installed launcher/window/taskbar/installer icons
   and startup appearance. Include Android adaptive/themed icons and OS dark mode.
2. Check startup both warm/fast and cold, without an artificial pause; exercise
   keyboard, short windows, safe insets, large text and screen-reader labels.
3. Check available/downloading/verifying/ready/error update states beside the menu,
   no filename movement, existing download/confirmation flow and reduced motion.
4. Upgrade installed copies in place; confirm collection, working/recovery/draft
   data and Android document grants remain intact. Account for OS icon caching
   when inspecting existing desktop shortcuts/launchers; never clear user data
   as an icon-refresh workaround.
