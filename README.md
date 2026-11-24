<p align="center">
  <img src="Sources/FrameApp/Resources/dewShot.iconset/icon_256x256.png" alt="dewShot app icon" width="96" height="96">
</p>

<h1 align="center">DewShot</h1>

<p align="center">
  A native macOS app to capture, preview, copy, and save screenshots and screen recordings.
</p>

<p align="center">
  <a href="README_ZH.md">中文</a>
</p>

## Install and get started

Requires macOS 26 or later. If you received a DewShot beta invitation, open it on your Mac and install the app through TestFlight. Earlier versions were published as Frame on [GitHub Releases](https://github.com/deweyou/frame/releases).

1. Open the app and follow the welcome window to grant Screen Recording access. Set the screenshot and recording shortcuts there too. A conflict is shown beside the affected shortcut. Take a Screenshot becomes available once screen access is granted and both shortcuts are ready.
2. Press `⌘⇧A` for a screenshot or `⌘⇧R` to start a recording. Both actions are also in the menu bar.
3. Use the corner preview to copy or save the result. The TestFlight build asks you to choose a folder on the first save.

Screenshots and recordings are processed on your Mac. No account is required to use DewShot.

You can opt in to share feature usage, operation timings, and crash diagnostics on the welcome screen or in General settings. Sharing is off by default.

## Menu bar and previews

On multiple displays, previews follow the active window's display. Moving the pointer alone leaves them in place.
By default, dewShot also copies the finished screenshot or recording to the clipboard.
You can turn this off in Settings → Capture.
Corner previews close after 30 seconds by default once the capture has been
copied or saved in history. Change the delay in the same settings pane.
The menu keeps Capture Screenshot and Record Screen as separate direct actions
and shows each configured shortcut beside its action.
Record Screen defaults to `Command+Shift+R`.
Customize these shortcuts in General settings with Command, Option, or Control
and a letter or number. dewShot checks for known conflicts before saving.

## What You Can Do

### Screenshot

- Select an area with `Command+Shift+A`.
- Capture a window or the full screen.
- Capture long content with scrolling screenshots and a live side preview.
- Use dewShot on multiple displays.
- Save screenshots as PNG files.

### Record

- Record a selected area as MP4 or GIF.
- Choose whether to show the cursor, clicks, and pressed keys.
- Stop, restart, or discard a recording. Play it from the corner preview.

### Preview, Copy, and Save

- Copy a screenshot or recording, or save it to your chosen folder.
- Hover to see a larger preview, pin a screenshot, or drag it into another app.
- Double-click a corner preview or choose **Open in Default App** to open a copy in the app macOS selects for that file type.
- Open a recent screenshot or replay a recent recording from Capture History.
- Clear cached captures from the More Actions menu in Capture History.

### Appearance

- In Settings → General, choose Follow System, Light, or Dark. The screenshot
  toolbar uses Liquid Glass and follows the selected appearance. The Capture pane
  groups screenshot, recording, and text recognition settings.

### Start Automatically

- Turn on Launch at Login in Settings to keep dewShot available from the menu bar
  after signing in to your Mac.

## Permissions

dewShot needs the macOS Screen Recording permission so it can see what is on your
screen when you take a screenshot or recording. The name sounds broader than
screenshots, but macOS uses this permission for screenshot apps too.
On first launch without access, the welcome window guides you through this
permission and checks that both shortcuts are available before your first capture.
If System Settings opens, the dewShot guide shows how to enable it or drag
the app into the list when it is missing.

The welcome window and Settings list Accessibility and Input Monitoring as
optional permissions for automatic scrolling and live keyboard hints. Their
status refreshes after you return from System Settings.

See [macOS Permissions](docs/permissions.md) for more detail.

## Development

See the [development guide](DEVELOPMENT.md) for setup, change-specific checks, and the project knowledge base.
