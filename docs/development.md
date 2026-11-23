# Development

```mermaid
flowchart TD
    Edit[Edit code] --> Verify[swift test and swift build]
    Verify --> DevPackage[Package dewShot Dev]
    DevPackage --> DevSign[Stable local or Apple Development signing]
    DevSign --> DevInstall[Install dewShot Dev.app]
    DevInstall --> Smoke[Manual screenshot smoke test]
    Verify --> Production[Package production dewShot.app]
```

dewShot development uses SwiftPM for verification, a local packaging script for app bundle creation, and a stable local signing path for repeat GUI testing without unnecessary Screen Recording permission churn.

## Requirements

- macOS 26 or later
- Swift 6.2 toolchain
- Xcode command line tools with the macOS 26 SDK or later
- Apple Developer Program membership only for Apple Development and public distribution signing

## Verify

Run these before merging or opening a PR:

```sh
swift test
swift build
scripts/package-app.sh
```

`scripts/package-app.sh` writes `Info.plist`, copies the release executable, and signs the bundle. It uses ad-hoc signing by default so CI and fresh machines work without account setup.

## App Variants

The packaging script owns the registered app identity mapping. Callers select a variant instead of entering bundle identifiers manually:

| Variant | App name | Bundle identifier | Output |
| --- | --- | --- | --- |
| `production` (default) | dewShot | `dev.deweyou.frame` | `.build/app/dewShot.app` |
| `development` | dewShot Dev | `dev.deweyou.frame.dev` | `.build/app/dewShot Dev.app` |

Inspect the resolved configuration without building:

```sh
scripts/package-app.sh --print-configuration
FRAME_APP_VARIANT=development scripts/package-app.sh --print-configuration
```

The release tooling always requests the `production` variant, even if the calling shell has another `FRAME_APP_VARIANT` value.

The different bundle identifiers isolate `UserDefaults` and macOS TCC permissions. Each variant keeps its existing capture history across the rename. Production uses `Application Support/Frame/History` and development uses `Application Support/Frame Dev/History`.

The packaging script also copies app resources from `Sources/FrameApp/Resources` into the app bundle. `dewShot.icns` is written to `Contents/Resources` and referenced by `CFBundleIconFile`; menu bar PNG assets are copied so `StatusItemController` can load `FrameStatusIconTemplate` as a template image.

For local GUI testing, sign the development variant with the exact Apple
Development identity listed by `security find-identity -v -p codesigning`.
See the [local installation flow](#manual-smoke-test) and
[signing setup for a new Mac](signing-and-device-migration.md#set-up-a-new-development-mac).

## Manual Beta Release

dewShot's first release path is a manual beta download. It produces a DMG, a ZIP,
and SHA-256 checksums, but it does not notarize the app and does not configure
automatic updates.

### GitHub Actions

Use the `Manual Release` workflow from the GitHub Actions UI for the normal beta
release path. It is triggered manually with `workflow_dispatch` and asks for:

- `version_bump`: `patch`, `minor`, `major`, or `custom`.
- `custom_version`: required only when `version_bump` is `custom`.
- `create_github_release`: whether to create a GitHub Release after packaging.

The workflow runs `scripts/prepare-release-version.sh`, which computes the next
semantic version from `Sources/FrameCore/FrameVersion.swift`, increments the
build number by one, and delegates the actual file updates to
`scripts/bump-version.sh`.

After the version is prepared, the workflow runs tests, builds, creates release
artifacts, verifies checksums and the DMG, commits the version/changelog changes,
tags `v<version>`, pushes the commit and tag, and uploads the DMG, ZIP, and
`SHA256SUMS` as workflow artifacts. If `create_github_release` is enabled, it
also creates a GitHub Release with the same files and release notes extracted
from `CHANGELOG.md`.

### Local Release

Before bumping the version, write user-facing release notes under
`CHANGELOG.md`'s `Unreleased` section. Then run:

```sh
scripts/bump-version.sh 0.2.0 2
```

The first argument is `CFBundleShortVersionString`, and the second argument is
`CFBundleVersion`. The build number must be a positive integer greater than the
current build.

To use the same bump choices as GitHub Actions locally, run:

```sh
scripts/prepare-release-version.sh patch
scripts/prepare-release-version.sh minor
scripts/prepare-release-version.sh major
scripts/prepare-release-version.sh custom 0.2.0
```

Verify the app before creating downloadable artifacts:

```sh
swift test
swift build
scripts/package-app.sh
```

Create release artifacts:

```sh
scripts/package-release.sh
```

The output is written to:

```text
.build/release/dewShot-<version>-build.<build>/
```

The directory contains:

- `dewShot-<version>-build.<build>.zip`
- `dewShot-<version>-build.<build>.dmg`
- `SHA256SUMS`

Use `FRAME_RELEASE_CODESIGN_IDENTITY` when intentionally testing a release
signing identity:

```sh
FRAME_RELEASE_CODESIGN_IDENTITY="dewShot Beta Release" scripts/package-release.sh
```

If no release identity is supplied, `scripts/package-release.sh` falls back to
the existing ad-hoc package behavior and prints a warning. Without Developer ID
signing and notarization, public beta users should be told to copy `dewShot.app`
to `/Applications`, open it from there, use macOS `Open Anyway` when prompted,
grant Screen Recording permission, and relaunch the app. Do not ask users to run
dewShot directly from the mounted DMG.

## Manual Smoke Test

1. Choose an Apple Development signing identity from
   `security find-identity -v -p codesigning`, then package the development build:

   ```sh
   FRAME_APP_VARIANT=development \
   FRAME_CODESIGN_IDENTITY="Apple Development: Your Name (IDENTIFIER)" \
   scripts/package-app.sh
   ```

2. Quit the installed development app, replace it at `~/Applications/dewShot Dev.app`,
   then verify the signature before opening it:

   ```sh
   mkdir -p "$HOME/Applications"
   frame_previous=$(mktemp -d "$HOME/Applications/.frame-update.XXXXXXXX")
   if [ -d "$HOME/Applications/dewShot Dev.app" ]; then
       mv "$HOME/Applications/dewShot Dev.app" "$frame_previous/dewShot Dev.app"
   fi
   if [ -d "$HOME/Applications/Frame Dev.app" ]; then
       mv "$HOME/Applications/Frame Dev.app" "$frame_previous/Frame Dev.app"
   fi
   ditto ".build/app/dewShot Dev.app" "$HOME/Applications/dewShot Dev.app"
   codesign --verify --strict --deep "$HOME/Applications/dewShot Dev.app"
   codesign -dv --verbose=4 "$HOME/Applications/dewShot Dev.app" 2>&1
   open "$HOME/Applications/dewShot Dev.app"
   ```

   Check for an Apple Development authority, a Team ID, and
   `Identifier=dev.deweyou.frame.dev`. The directory in `frame_previous`
   holds the previous bundle for rollback.

3. Grant Screen Recording permission when prompted.
4. Quit and reopen `~/Applications/dewShot Dev.app`.
5. Open `dewShot -> 设置...` / `dewShot -> Settings...`. Switch among General, Capture, History, and Permissions and confirm the controls match the selected pane. Reopen Settings from another display and confirm it centers on that display.
6. Change the language between Follow System, 中文, and English. Confirm the menu, settings window labels, permission alerts opened after the change, Quick Access tooltips, and capture placeholder use the selected language. In General, turn Launch at Login on and confirm dewShot appears under System Settings > General > Login Items & Extensions; turn it off and confirm the login item is removed. If macOS reports that approval is required, confirm Settings explains where to approve it. In Permissions, verify that granted rows show a checkmark and missing rows link to the matching macOS settings pane. Return to dewShot from System Settings and confirm the states refresh. With a dedicated test app that lacks optional access, verify that automatic scrolling offers Settings and allows manual scrolling, and that recording can start with keystroke hints disabled.
7. In General, switch between the Light, Dark, and Follow System appearance previews. Confirm the Settings window updates immediately and both screenshot HUD capsules, icons, dimensions, and tooltips remain readable over light and dark content. Quit and reopen dewShot to confirm the choice persists. Also verify that a custom screenshot save folder persists.
8. In Settings, change Window screenshot style between Soft Backdrop, Canvas Glow, Transparent Shadow, and Original. Confirm the labels localize and the selected value persists after reopening Settings.
9. Reset the screenshot save folder and confirm it returns to Desktop.
10. Confirm the menu has separate Capture Screenshot and Record Screen items, displays configured shortcuts, and keeps Record Screen available when its shortcut is unset. Start each flow from its menu item or configured keyboard shortcut.
    In the shortcut recorder, try a single modifier, a duplicate dewShot shortcut,
    an enabled macOS shortcut, and a common app shortcut such as Command+A.
    Confirm that dismissing a conflict or warning preserves the saved shortcut.
11. With no previous selection, confirm the active display shows a centered placeholder instead of a `0 x 0` HUD. After confirming a window capture, quit and reopen dewShot, then start capture again within ten minutes. Confirm the same live window restores as the initial selection without hover preselection, even after moving the window. After confirming a region capture, reopen the overlay and confirm the same rectangle restores without hover preselection. A full-screen capture, closing a remembered window, or waiting for expiry returns to the empty state.
12. Drag to create, move, or resize the region.
13. Press Enter to capture.
14. Confirm the `180x120` preview appears at the active screen's bottom-left corner with equal left and bottom padding.
15. With multiple displays, trigger capture while the active window is on one display and the pointer is on another. Confirm the first preview opens on the active display. Move the pointer between displays and switch focus to another app. Confirm the preview remains on its original display. Dismiss all previews and capture again from the other display to verify that a new stack uses the new active display.
16. Take multiple screenshots and confirm previews stack upward from the bottom-left corner.
17. Confirm the Quick Access preview cannot be moved by dragging its background.
18. Drag the preview image into a rich-text TextEdit document or Notes note and confirm the target receives image content.
19. Hover the preview and confirm icon-only save, copy, open in default app, pin, and close actions appear in a stable deep-glass action overlay while the captured pixels stay unchanged. Try OCR on a region with no text and confirm the result is centered in the screenshot card, clear of the toolbar, and dismisses automatically.
20. Confirm copy places an image on the pasteboard.
21. Confirm save writes `dewShot yyyy-MM-dd HH.mm.ss.png` to the configured screenshot folder, or Desktop after reset.
22. Double-click an eligible app window, capture it, and confirm the output uses the selected window screenshot style. Confirm Original keeps the cropped raw window output without an added background canvas while region screenshots remain undecorated.
23. Choose Open in Default App on a screenshot. Confirm macOS opens a PNG copy, then double-click a screenshot in Capture History and verify it also opens externally.
24. Confirm pin closes the originating Quick Access card and opens a persistent image-only pinned window.
25. Confirm the pinned window has no toolbar or visible output buttons, keeps the image edge-to-edge, stays open after focus changes, and closes with the native red traffic-light close button.
26. Right-click the pinned window and confirm Copy and Download work without closing it.
27. Right-click the pinned window and confirm Open in Default App opens a PNG copy while the pinned window stays visible.
28. Use the screenshot shortcut again, draw a region, click the recording HUD button, and confirm the HUD switches into recording setup without closing the overlay.
29. Record a short MP4 with cursor enabled. Confirm start shows a brief preparation/loading state instead of a countdown, then switches to elapsed-time recording controls; stop finalizes the file, restart discards the current take and records the same area again, and delete requires confirmation before discarding without Quick Access.
30. Confirm the menu bar icon becomes a red recording dot while recording and its Stop Recording menu item stops the same active session.
31. Confirm the completed recording appears in a bottom-left Quick Access card with Download, Copy, a centered play control, Open in Default App, and Close.
32. Confirm MP4 playback uses native play, pause, and seek controls with Copy and Download. Choose Open in Default App from the recording card and verify macOS opens a copy.
33. Confirm Copy places the recording file URL on the pasteboard and Download writes `dewShot yyyy-MM-dd HH.mm.ss.mp4` to the configured screenshot folder.
34. Repeat with GIF selected and confirm `dewShot yyyy-MM-dd HH.mm.ss.gif` output is produced.
35. Select an entire single display as the recording region and confirm the recording HUD remains usable but is absent from the output.
36. Confirm local capture history lists recordings separately, opens playable recording files, copies file URLs, saves files, and deletes cached recording records.

Keep using the same `FRAME_CODESIGN_IDENTITY`, the `development` variant, and the same `~/Applications/dewShot Dev.app` path while iterating. Changing any of them can make macOS ask for Screen Recording permission again.

## CI

GitHub Actions runs on macOS and verifies:

- AppKit component E2E with `swift test --filter HUDSizeControlTests`
- `swift test`
- `swift build`
- `scripts/package-app.sh`
- generated app bundle existence
- generated `Info.plist` validity
- generated app bundle signature metadata

CI does not grant Screen Recording permission or run full desktop GUI smoke tests. Live ScreenCaptureKit recording, HUD exclusion from output, and full-screen selection recording must be verified through the stable local app smoke flow above. See `docs/testing.md` for the component E2E boundary and expectations for new interactive requirements.

## Local Permission Reset

When testing repeated local builds, reset the app permission entry:

```sh
tccutil reset ScreenCapture dev.deweyou.frame.dev
```

Then reopen the exact app bundle you want to authorize.

---
*Last updated: 2026-09-02 | Reason: separate development and production app identities and add device-migration guidance*
