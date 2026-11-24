# Changelog

## Unreleased

- Exclude browser download metadata from the provisioning profile embedded in
  Mac App Store packages.

- Reuse the authorized save folder when saving a recording from History in the
  Mac App Store build.

- Assign a filename when taking a screenshot and keep it in History. Reuse an
  identical PNG in the save folder and keep different screenshots with colliding
  filenames as separate files.

- Show the destination folder after saving a capture from History.

- Prepare Mac App Store installer packages and include a privacy manifest.

- Show screenshot and recording shortcuts in the welcome window, with a bottom
  action card for Screen Recording access and a first screenshot.
  Accessibility and Input Monitoring are available as optional setup steps.

- Show a small permission guide beside System Settings when dewShot needs
  Screen Recording access. Drag the dewShot icon into the list if it is missing.
  The guide waits for the Settings window while the system permission prompt is open.

- Add a local App Sandbox test build. It asks for a destination folder on first
  save and remembers permission to save screenshots and recordings there.

- Double-click a screenshot or recording in Quick Access to open it in the macOS default app.

- Align Quick Access screenshot toolbar icons and use a consistent color for enabled actions.

- Put Open in Default App and Save first in Quick Access for screenshots and recordings, with Copy at the end.

- Open Quick Access on the active display and move existing previews together when window focus switches displays.

- Use a continuous outline around the rounded edges of screenshot and recording previews.

- Apply the system accent color to the selected Capture History filter on first open.

- Add Clear History to its own menu alongside the Capture History filters, with confirmation before deleting cached screenshots and recordings.

- Keep Capture History tile actions visible while the pointer is over the tile and hide them immediately when it leaves.

- Use a native unified toolbar and system window controls in Capture History, with compact filters and no duplicate caption.

- Center short text-recognition results in the Quick Access screenshot preview, clear of its toolbar.

- Focus the first release on capture, preview, copy, and save. Open copies of screenshots and recordings in the macOS default app while the built-in editors are deferred.

- Rename the app to dewShot. New captures and release downloads use the new name.

- Automatically dismiss corner previews after 30 seconds by default. Choose
  10 seconds, 30 seconds, 1 minute, or Never in Capture settings.
- Use Command+Shift+R as the default shortcut for starting a recording.
- Allow one modifier for capture shortcuts. Check for enabled macOS shortcuts
  and exclusive reservations, and warn about common app shortcuts before saving.
- Match Settings dropdown arrows to the smaller disclosure arrows and use
  standard-size menu items.
- Automatically copy finished screenshots and screen recordings to the clipboard
  while keeping their corner previews. Turn this off in Capture settings.
- Simplify the recording player header and separate pinned-image window controls
  from the image.
- Give Capture History a window title, clearer tile metadata, and actions that
  match empty, filtered, or disabled history.
- Label scrolling capture’s Start and Finish controls, clarify its toolbar icon,
  and emphasize copy and save in Quick Access.
- Reduce the initial height of short OCR results and soften unselected text
  outlines. Give the recording stop action more visual weight than delete.

- Organize Settings into four panes and preview each appearance before selecting it.
  Use the native macOS split-view sidebar and a unified window header.
- Refine Settings spacing and control styling, with compact appearance previews,
  quieter shortcut fields, and save paths and permission status under their labels.
- Give Settings sidebar items more breathing room and use smaller navigation icons.
- Show permission purposes and granted status in Settings. Provide a single
  Settings link for missing access and explain optional permissions where
  automatic scrolling and recording keystroke hints are used.

- Choose Follow System, Light, or Dark in Settings. Both screenshot HUD capsules
  use untinted Regular Liquid Glass and follow the selected appearance. The desktop
  shows through the capsules while the surrounding selection stays dimmed.
  Use softer icon and dimension colors in both appearances.
- Require macOS 26 or later.

- Open a copy of a history screenshot in the default app or play a recording
  with a double-click or Return.

- Switch OCR results between selectable full text and individual blocks. dewShot
  remembers the last view.

- Explain when scrolling capture stops and how to continue or finish with the
  portion already captured.

- Confirm successful Quick Access copies and show the destination after saving.

- Keep the Start Recording title visible on its red button.

- Add a Launch at Login setting backed by macOS Service Management, with
  approval and failure feedback that reflects the system's real login-item state.
- Separate development and production packaging as `dewShot Dev`
  (`dev.deweyou.dewshot.dev`) and `dewShot` (`dev.deweyou.dewshot`), and document
  signing setup and recovery for a new development Mac. Builds with these
  identifiers require fresh macOS permissions when upgrading from Frame.
- Make screenshot and screen recording discoverable as separate menu actions,
  with native shortcut labels that follow the configured shortcuts.
- Show Screen Recording, Accessibility, and Input Monitoring together in
  Settings, refresh their state after returning from System Settings, and fully
  localize the Screen Recording permission flow.
- Confirm before permanently deleting a capture-history item, and show a native
  vertical scroller for long recognized-text results.
- Keep recognized-text cut labels readable when the OCR panel uses or switches
  to macOS Dark Mode.
- Show a fixed side preview during scrolling screenshots so users can see
  successfully stitched progress and detect interrupted matching before Finish.
- Build the full-resolution result incrementally from raw capture frames, avoid
  per-sample PNG encoding and retained full-frame history, and encode once at
  Finish without restitching the capture.
- Run incremental ingest and final encoding through an explicit background-safe
  worker boundary so starting a scrolling capture cannot violate MainActor
  isolation.
- Keep the last accepted preview and session available when a sample cannot be
  matched, with bounded canvas memory and historical-position fingerprints.
- Make automatic scrolling wait for each classified sample, confirm the bottom
  across three no-motion samples, and stop on historical repeats or unreliable
  overlap instead of bouncing back through the page.
- Keep sparse white-background pages stitchable when only a small amount of
  visible content moves between samples.
- Prevent scrolling screenshots from repeating earlier page sections when the
  captured page jumps back to a previously sampled position.

## 0.1.2 - 2026-07-12

- Improve the screenshot editor with a context-aware header style control, an
  icon-only color swatch selector and tiled palette dropdown, canvas tool
  shortcuts, and double-click object context switching.
- Add a setting for the Save Current default behavior so edited screenshots can
  replace the current preview or save as a new preview without prompting every
  time.
- Refine editor close prompts, expand text sizing through 96 pt, use an opaque
  canvas backdrop, hide selection HUD controls during delayed capture, and
  persist the last confirmed screenshot selection for ten minutes across Frame
  restarts.
- Remove the visible blue resize anchor from selected image annotations while
  retaining the top-right resize target.
- Make the image editor's Save Current, Copy, and Download controls a compact,
  evenly sized group, with Save and Copy / Save and Download tooltips.
- Rework the image editor toolbar with stable dark glass, clearer semantic
  groups, centered normalized icon rendering, and an attached Mosaic split
  control with a larger menu target.
- Align image editing, video preview/editing, and Quick Access control chrome
  around stable deep glass while keeping captured image and video pixels
  unmodified.
- Reduce the recording Quick Access duration badge so it stays legible without
  competing with the preview.

## 0.1.1 - 2026-07-06

- Add manual beta release tooling for version bumps, changelog rollover, DMG/ZIP
  artifacts, and SHA-256 checksums.
- Align recording Quick Access copy/download behavior with screenshot actions by
  dismissing the corner preview after successful actions.

## 0.1.0 - 2026-07-02

- Add the menu bar app shell, first-run Screen Recording permission guidance,
  and configurable screenshot and recording shortcuts.
- Add region, window, full-screen, delayed, and manual scrolling screenshot
  capture, including multi-display selection support and per-display full-screen
  output.
- Add the corner Quick Access preview stack with copy, save, close, drag-out,
  pin, larger preview, and edit entry points for recent captures.
- Add image annotation and editing tools for text, arrows, shapes, highlights,
  brush marks, mosaics, undo/redo, pinning, and saving edited results.
- Add local OCR flows for recognizing text from captures, reviewing recognized
  text, and copying selected text.
- Add selected-area recording as MP4 or GIF with cursor, click, and keyboard
  hint overlays, a visible recording boundary, and active recording controls for
  stop, restart, and delete.
- Add recording Quick Access previews with first-frame thumbnails, larger video
  preview playback, MP4 trim controls, speed export, copy, and download actions.
- Add local capture history for screenshots and recordings, including restore to
  Quick Access and configurable retention/storage cleanup.
- Add English and Simplified Chinese app strings for the primary capture,
  settings, history, OCR, editing, and recording surfaces.
