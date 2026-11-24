# Build, install, and release DewShot

For prerequisites and change-specific checks, see the [development guide](../DEVELOPMENT.md)
or [中文开发指南](../DEVELOPMENT_ZH.md).

## App Variants

The packaging script owns the registered app identity mapping. Callers select a variant instead of entering bundle identifiers manually:

| Variant | App name | Bundle identifier | Output |
| --- | --- | --- | --- |
| `production` (default) | dewShot | `dev.deweyou.dewshot` | `.build/app/dewShot.app` |
| `development` | dewShot Dev | `dev.deweyou.dewshot.dev` | `.build/app/dewShot Dev.app` |

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

Production candidates follow the [release and patch SOP](release.md).

## Mac App Store and TestFlight

The Store package uses the production App ID `dev.deweyou.dewshot` with
App Sandbox enabled. Have the App Store Connect app record and these signing
assets ready before building for TestFlight:

- An `Apple Distribution` or `Mac App Distribution` identity and private key.
- A `Mac Installer Distribution` identity and private key. Keychain may show it
  as `3rd Party Mac Developer Installer`.
- A `Mac App Store Connect` provisioning profile for the production App ID and
  its app-signing certificate.

```sh
FRAME_APP_STORE_APP_IDENTITY="Apple Distribution: Your Team (TEAMID)" \
FRAME_APP_STORE_INSTALLER_IDENTITY="3rd Party Mac Developer Installer: Your Team (TEAMID)" \
FRAME_APP_STORE_PROFILE="/path/to/dewShot.provisionprofile" \
scripts/package-app-store.sh
```

Use the exact identity names from `security find-identity -v` and keep the
profile and private keys outside the repository. The script creates a signed
`.pkg` in `.build/app-store/` for validation and upload in Transporter.
For release acceptance, install the selected version and build through TestFlight.
Run that copy, record its version and build, then check capture, saving from History,
and playback of a saved recording. For first-run testing use a fresh test account
or Mac where the production app has not yet requested access. The
bundled privacy manifest declares local app preferences and elapsed-time APIs.

See Apple's [provisioning profile instructions](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile)
and [Mac packaging instructions](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution).

## Sandbox Smoke Test

Build with the existing Apple Development identity:

```sh
FRAME_APP_SANDBOX=1 FRAME_APP_VARIANT=development \
FRAME_CODESIGN_IDENTITY="Apple Development: Your Name (IDENTIFIER)" \
scripts/package-app.sh
frame_dev_source=".build/app-sandbox/dewShot Dev.app"
```

The bundle uses the development App ID and writes its own settings and history
in the sandbox container. To test it at the stable development-app path, follow
step 2 of the [manual smoke test](#manual-smoke-test) in the same shell. Grant Screen Recording if requested, then relaunch.

When testing a first launch without Screen Recording access, confirm the welcome
window shows the configured screenshot and recording shortcuts. Confirm the
menu bar item is absent and the shortcuts do not start captures. Close the
window and relaunch the app to resume setup. Start permission setup, confirm the
guide opens beside System Settings, and drag the app into the list if it is
missing. Enable access and follow any system prompt to relaunch. The welcome
window should resume with its screenshot action available. Test the drag in the
signed app because the destination is a system-owned privacy control.
Confirm that the two optional welcome rows open their respective settings pages
and that the screenshot action is available with both optional permissions off.

1. Capture a region using the global shortcut. Save from Quick Access and choose
   a folder outside the app container. Canceling the picker should leave the
   capture available to save again.
2. Quit and reopen the app. Save another screenshot and a short recording.
   Both should land in the same chosen folder without a second picker.
3. Reset the save location in Settings. The next save should ask for a folder again.
4. With Accessibility and Input Monitoring off, verify manual scrolling capture
   and recording with keystroke hints off. Check automatic scrolling and
   keystroke hints separately if their permissions are granted.

The folder picker, security-scoped bookmark lifecycle, and system permissions
require the installed signed bundle for end-to-end verification.

## Switching between production and Dev

### Local GUI test SOP

The agent owns the app switch whenever a task needs the signed local Dev app
on a Mac with production installed. A website preview or a unit test alone
does not require an app switch.

1. **Start.** Identify the signed Dev build under test and the running production
   app's path (normally `/Applications/dewShot.app`). If a recording is in
   progress, wait for it to finish before switching. Run
   `scripts/dev-session.swift start "<verified Dev app path>"` in a retained
   terminal session. The helper requests a normal quit and waits for production
   to exit before launching Dev. For settings review, pass `--settings` to
   `start` to open General on launch after onboarding. Verify the running Dev path before testing.
2. **Test or hand off.** Exercise the requested behavior. If the user is trying
   the UI, leave Dev open and retain the session until they indicate they are
   finished. For agent-only tests, proceed directly to cleanup, including after
   a failed test.
3. **Restore.** Run `scripts/dev-session.swift stop` in a separate terminal.
   This also works if the start terminal has closed. It quits Dev and reopens
   the recorded production copy, falling back to `/Applications/dewShot.app`
   when no production path was recorded. Honor an explicit request to leave
   an app open or keep all apps closed.
4. **Verify and report.** Check the running application paths. Confirm that
   Dev has exited and the intended production app is running before reporting
   restoration. If normal quit or launch fails, inspect the remaining processes
   and retry safely. Report any unresolved blocker and the actual running
   state. Only ask the user to intervene when their action is necessary.

## Manual Smoke Test

1. Choose an Apple Development signing identity from
   `security find-identity -v -p codesigning`, then package the development build:

   ```sh
   FRAME_APP_VARIANT=development \
   FRAME_CODESIGN_IDENTITY="Apple Development: Your Name (IDENTIFIER)" \
   scripts/package-app.sh
   frame_dev_source=".build/app/dewShot Dev.app"
   ```

2. Quit the installed development app, replace it at `~/Applications/dewShot Dev.app`,
   then verify the signature before opening it:

   ```sh
   (
       set -eu
       : "${frame_dev_source:?Select the Dev bundle from the packaging step first}"
       installed="$HOME/Applications/dewShot Dev.app"
       codesign --verify --strict --deep "$frame_dev_source"
       mkdir -p "$HOME/Applications"
       if [ -d "$installed" ]; then
           backup=$(mktemp -d "$HOME/Applications/.frame-update.XXXXXXXX")
           mv "$installed" "$backup/"
           echo "Previous app saved in $backup"
       fi
       ditto "$frame_dev_source" "$installed"
       codesign --verify --strict --deep "$installed"
       codesign -dv --verbose=4 "$installed" 2>&1
   )
   ```

   Confirm an Apple Development authority, the expected Team ID, and
   `Identifier=dev.deweyou.dewshot.dev`. For a sandbox test, also run the
   following command and confirm it prints `True` before opening the app:

   ```sh
   codesign -d --entitlements - --xml "$HOME/Applications/dewShot Dev.app" 2>/dev/null |
       python3 -c 'import plistlib, sys; print(plistlib.loads(sys.stdin.buffer.read())["com.apple.security.app-sandbox"])'
   ```

   Once verified, launch the installed build using the [local GUI test SOP](#local-gui-test-sop).

3. Grant Screen Recording permission when prompted.
4. If a relaunch is required for permission changes, resume the same installed Dev build through the session helper.
5. Open `dewShot -> 设置...` / `dewShot -> Settings...`. Switch among General, Capture, History, and Privacy & Permissions and confirm the controls match the selected pane. Reopen Settings from another display and confirm it centers on that display.
6. Change the language between Follow System, 中文, and English. Confirm the menu, settings window labels, permission alerts opened after the change, Quick Access tooltips, and capture placeholder use the selected language. In General, turn Launch at Login on and confirm dewShot appears under System Settings > General > Login Items & Extensions; turn it off and confirm the login item is removed. If macOS reports that approval is required, confirm Settings explains where to approve it. In Privacy & Permissions, verify that granted rows show a checkmark and missing rows link to the matching macOS settings pane. Return to dewShot from System Settings and confirm the states refresh. With a dedicated test app that lacks optional access, verify that automatic scrolling offers Settings and allows manual scrolling, and that recording can start with keystroke hints disabled.
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
15. With multiple displays, trigger capture while the active window is on one display and the pointer is on another. Confirm the first preview opens on the active display. Move only the pointer across displays and confirm the preview stays in place. Focus a window on the other display and confirm the existing stack moves together. Repeat with two windows of the same app on different displays.
16. Take multiple screenshots and confirm previews stack upward from the bottom-left corner.
17. Confirm the Quick Access preview cannot be moved by dragging its background.
18. Drag the preview image into a rich-text TextEdit document or Notes note and confirm the target receives image content.
19. Hover the preview and confirm icon-only save, copy, open in default app, pin, and close actions appear in a stable deep-glass action overlay while the captured pixels stay unchanged. Try OCR on a region with no text and confirm the result is centered in the screenshot card, clear of the toolbar, and dismisses automatically.
20. Confirm copy places an image on the pasteboard.
21. Confirm save writes `dewShot yyyy-MM-dd HH.mm.ss.png` to the configured screenshot folder, or Desktop after reset.
22. Double-click an eligible app window, capture it, and confirm the output uses the selected window screenshot style. Confirm Original keeps the cropped raw window output without an added background canvas while region screenshots remain undecorated.
23. Double-click the screenshot in Quick Access and confirm macOS opens a PNG copy. Repeat with Open in Default App and with a double-click in Capture History.
24. Confirm pin closes the originating Quick Access card and opens a persistent image-only pinned window.
25. Confirm the pinned window has no toolbar or visible output buttons, keeps the image edge-to-edge, stays open after focus changes, and closes with the native red traffic-light close button.
26. Right-click the pinned window and confirm Copy and Download work without closing it.
27. Right-click the pinned window and confirm Open in Default App opens a PNG copy while the pinned window stays visible.
28. Use the screenshot shortcut again, draw a region, click the recording HUD button, and confirm the HUD switches into recording setup without closing the overlay.
29. Record a short MP4 with cursor enabled. Confirm start shows a brief preparation/loading state instead of a countdown, then switches to elapsed-time recording controls; stop finalizes the file, restart discards the current take and records the same area again, and delete requires confirmation before discarding without Quick Access.
30. Confirm the menu bar icon becomes a red recording dot while recording and its Stop Recording menu item stops the same active session.
31. Confirm the completed recording appears in a bottom-left Quick Access card with Open in Default App, Save, and Copy in that order, a centered play control, and Close in the corner.
32. Click the recording card's center play control once and confirm the built-in player opens with native play, pause, and seek controls, plus Copy and Download. Close the player, double-click the same spot, and confirm only the default app opens a copy. Repeat using Open in Default App from the toolbar.
33. Confirm Copy places the recording file URL on the pasteboard and Download writes `dewShot yyyy-MM-dd HH.mm.ss.mp4` to the configured screenshot folder.
34. Repeat with GIF selected and confirm `dewShot yyyy-MM-dd HH.mm.ss.gif` output is produced.
35. Select an entire single display as the recording region and confirm the recording HUD remains usable but is absent from the output.
36. Confirm local capture history lists recordings separately, opens playable recording files, copies file URLs, saves files, and deletes cached recording records.

Keep using the same `FRAME_CODESIGN_IDENTITY`, the `development` variant, and the same `~/Applications/dewShot Dev.app` path while iterating. Changing any of them can make macOS ask for Screen Recording permission again.

## CI

On pull requests and pushes to `main`, [CI](../.github/workflows/ci.yml) runs
the stable Swift suite, builds the app, packages the production variant, and
checks the executable, Info.plist values and signature metadata. Review the PR
result before merging. For the three local-only AppKit suites and desktop
checks, see [testing](testing.md#ci-expectations).

## Local Permission Reset

Keep existing permissions during routine rebuilds. For first-run testing or a
confirmed stale Dev entry, see [Reset Permission](permissions.md#reset-permission).

### Usage analytics and diagnostics

The optional sharing switch controls Firebase Analytics and Sentry. Local Dev
uses GA4 property 565657202 and Sentry project `dewshot-macos-dev`. TestFlight
uses a separate Apple stream in that GA4 property and the same Sentry project.
App Store installations use property 565664100 and `dewshot-macos`. The
production bundle verifies its StoreKit app transaction before selecting a
destination. An unknown distribution environment leaves telemetry disabled.

Keep the three Firebase client plists in `.local/telemetry/` as
`GoogleService-development.plist`, `GoogleService-testflight.plist`, and
`GoogleService-production.plist`. Keep the two public client DSNs there as
`sentry-development.txt` and `sentry-production.txt`. CI can point
`FRAME_TELEMETRY_ROOT` at a provisioned directory instead. Store packages
require all five files. Apple Development signed sandbox builds also use a Mac
development profile for the Dev bundle ID. Set `FRAME_DEV_PROFILE` or place it
at `development.provisionprofile` in the telemetry directory for Keychain access. Normal source builds can run without telemetry.
The packager validates the registered app IDs, bundle IDs and Sentry project IDs
before signing. Never place an administrative token in this directory.

Every ordinary launch of the local Dev app starts with sharing off, including
after a previous connectivity test. To test delivery, start Dev with
`-FIRDebugEnabled` and turn on sharing in the welcome window or General
settings. This enables both SDKs for that run. For a crash test that needs
collection on the following launch too, explicitly launch the Dev app with
`-shareUsageAndDiagnostics YES` on both runs. Inspect the Dev property's DebugView. Verify the
three custom event names and their documented parameters. Use the identical
build's dSYM when checking Sentry symbolication. TestFlight receipt routing
requires an installation delivered through TestFlight.

The App Store packaging script archives the matching dSYM next to the installer.
With a release-upload credential, upload the archive to both Sentry projects so
the same binary can be symbolicated on TestFlight and in production:

```sh
sentry-cli debug-files upload --org dewey-ou --project dewshot-macos-dev "$DEWSHOT_DSYM_ARCHIVE"
sentry-cli debug-files upload --org dewey-ou --project dewshot-macos "$DEWSHOT_DSYM_ARCHIVE"
```


## Product website

The Cloudflare Worker `dewshot` serves the static files in `website/public/`.
Preview them from the repository root with `python3 -m http.server --directory website/public`.
After checking the home page, support email link, and privacy link, deploy with
`npx wrangler deploy --config website/wrangler.jsonc` using an account with Workers write access.
Website deployments are independent of the macOS release.
