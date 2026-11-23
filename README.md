<p align="center">
  <img src="Sources/FrameApp/Resources/dewShot.iconset/icon_256x256.png" alt="dewShot app icon" width="96" height="96">
</p>

<h1 align="center">dewShot</h1>

<p align="center">
  A native macOS app to capture, preview, copy, and save screenshots and screen recordings.
</p>

<p align="center">
  <a href="README_ZH.md">中文</a>
</p>

dewShot helps when you need to show something quickly: a bug, an idea, a setting,
a layout, or a short interaction. Press the shortcut, choose what you need, and
then preview, copy, or save the result.

Everything stays on your Mac. dewShot does not need an account and does not upload
your screenshots or recordings.

## How It Feels

dewShot lives in the menu bar instead of opening a large window. After each
screenshot or recording, a small preview appears in the corner of your screen.
From there you can preview, copy, or save it.
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

The goal is simple: capture what you need, then get back to what you were doing.

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
- Use **Open in Default App** to open a copy of a screenshot or recording in the app macOS selects for that file type.
- Open a recent screenshot or replay a recent recording from Capture History.
- Clear cached captures from the More Actions menu in Capture History.

### Appearance

- Requires macOS 26 or later.
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

dewShot also lists Accessibility and Input Monitoring in Settings. Those optional
permissions support automatic scrolling and live keyboard hints; their status
refreshes after you return from System Settings.

See [macOS Permissions](docs/permissions.md) for more detail.
