<p align="center">
  <img src="Sources/FrameApp/Resources/dewShot.iconset/icon_256x256.png" alt="dewShot app icon" width="96" height="96">
</p>

<h1 align="center">dewShot</h1>

<p align="center">
  A native macOS app for screenshots and screen recordings you can edit, save,
  or share right after capture.
</p>

<p align="center">
  <a href="README_ZH.md">中文</a>
</p>

dewShot helps when you need to show something quickly: a bug, an idea, a setting,
a layout, or a short interaction. Press the shortcut, choose what you need, and
then copy, save, edit, pin, or find it again later.

Everything stays on your Mac. dewShot does not need an account and does not upload
your screenshots or recordings.

## How It Feels

dewShot lives in the menu bar instead of opening a large window. After each
screenshot or recording, a small preview appears in the corner of your screen.
From there you can copy it, save it, edit it, keep it visible, or close it.
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
- Capture a window.
- Capture long content by scrolling, with a fixed side preview that follows
  successfully stitched progress while capture is running, fast Finish without
  restitching the whole capture. Automatic scrolling waits for each frame.
  dewShot explains when scrolling stops and lets you finish with the captured portion.
- Use dewShot on multiple displays.
- Save screenshots as PNG files.

### Use The Preview

- Copy a screenshot or recording.
- Save it to a folder.
- Drag a screenshot into another app.
- Open a larger preview.
- Pin an image so it stays visible while you work.
- Recognize text and copy it from a selectable full-text or block view.

### Edit

- Open a screenshot, a local image, or an image from the clipboard.
- Adjust the current tool or selected object in a collapsible right inspector.
- Crop on the canvas, resize in pixels or percent, rotate, and flip. See the
  current pixel dimensions and switch between Fit and 100% zoom.
- Edit shapes, arrows, text, highlights, and brush marks. Add numbered stamps,
  a spotlight, and other images. Use mosaic, blur, or solid redaction.
- Adjust exposure, contrast, and saturation. Extend the canvas or remove the
  background.
- Undo image adjustments and annotations together. Save a local editable
  project to reopen the current image and its annotations.
- Copy or export PNG, JPEG, HEIC, or TIFF from the editor. Use Save Current
  to replace the history image or keep the original and save a new one.

### Record

- Record a selected area as MP4 or GIF.
- Choose whether to show the cursor, clicks, and pressed keys.
- Stop, restart, or delete a recording.
- Trim MP4 recordings and export faster or slower versions. Longer recordings
  show a few preview frames in the timeline.

### Find Recent Items

- Double-click a recent screenshot to edit it or a recording to play it.
- Replace a history screenshot with its edited version or save a separate copy.
- Bring an older item back into the corner preview.
- Choose how long dewShot keeps recent items.

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
