# Frame Design

Frame is a quiet native macOS utility. Its interface should feel like a small
system tool, not a branded dashboard.

## Product Feel

- Prefer native macOS behavior and system materials over custom-drawn controls.
- Keep permanent UI minimal. Show state and direct manipulation before adding
  buttons.
- Use SF Symbols for compact actions and always provide accessibility labels or
  tooltips.
- Keep copy short, factual, and Chinese-first for user-facing controls.

## Settings

- Use a compact sidebar with General, Capture, History, and Permissions.
  Use small symbols and give each label vertical space. Capture groups
  screenshots, recording, and text recognition. Use an AppKit
  split-view sidebar that extends into the window chrome. Let macOS render its
  material and row selection. Place the page heading and controls on a solid
  detail surface, with safe-area insets around the window controls and sidebar.
- Give each pane one clear heading. Use lightly shaded groups, quiet dividers,
  system typography, and a shared trailing edge for native controls. Place
  supporting details beneath their row labels. Put version and build metadata
  near the bottom of the sidebar.
- In General, show small previews for Follow System, Light, and Dark and mark the
  active appearance on its preview. Keep language, launch at login, the save folder, and
  capture shortcuts in General. Display the abbreviated save path and offer
  reset only for custom locations.
- Use inline shortcut recorders. Accept a letter or number with Command,
  Option, or Control, with Shift available as an additional modifier. Reject
  duplicates within Frame and enabled macOS shortcuts before saving. Use
  exclusive registration to detect other exclusive reservations. Ask for
  confirmation on common application commands such as Command+A.
- Keep separate Screen Recording, Accessibility, and Input Monitoring rows.
  Explain each permission's purpose and show granted status or a single link to
  the corresponding System Settings pane. Recheck when the pane appears or
  Frame becomes active. Explain optional permissions when the user selects
  automatic scrolling or keystroke hints.
- In Capture, show the selected OCR language count and open the language
  chooser as a sheet from the entire row.

## Screenshot Overlay

- The selected region stays undimmed; the area outside the selection is dimmed.
- Selection chrome is border-first: a subtle white outline plus clear corner
  handles.
- Use recognizable resize affordances: L-shaped corner handles and small
  mid-edge handles, kept in the black/white system rather than introducing an
  accent color.
- Cursor shape should explain the next action: crosshair outside the selection,
  move inside a non-fullscreen selection, edge resize on edges, and diagonal
  resize on corners.
- Avoid filling the selected area with color. Users need to inspect the content
  they are selecting.

## Capture HUD

- The menu bar menu exposes Capture Screenshot and Record Screen as separate
  direct actions. Show configured shortcuts using native menu key equivalents;
  use Command+Shift+R as the default for Record Screen, and keep the menu
  action available when the shortcut is unset.

- Use untinted AppKit Regular Liquid Glass for both capture HUD capsules.
  The glass and tooltip follow the app appearance. Pair the native material
  with charcoal icons in light appearance and soft light gray icons in dark
  appearance.
- Keep the HUD small and low-priority. It should not compete with the selected
  content.
- Keep HUD width stable while users edit size, toggle ratio lock, or open ratio
  presets. Avoid adding extra persistent buttons when an inline icon can carry
  the interaction.
- Place compact action icons on the left and the size readout on the right.
  Keep both screenshot HUD capsules 42 pt high and describe icon actions with
  tooltips and accessibility labels. Prefer placing the screenshot HUD outside
  the selection, below when space allows and above for bottom-edge selections.
- Size is persistent in screenshot modes. If a mode cannot edit size, disable
  editing rather than hiding or moving the size position.
- Size editing uses fixed-width numeric fields. Commit edited dimensions on
  Enter, blur, or related control actions; do not apply partial input while the
  user is typing.
- The ratio lock belongs between width and height, replacing the visual `x`
  separator. Ratio presets live behind a compact chevron after the size fields.
- Shift-drag temporarily behaves like ratio lock, then restores the prior lock
  state when Shift is released.
- Do not show a persistent confirmation button. Enter confirms; Esc cancels.
- Prefer direct manipulation. Window capture should primarily use hover
  highlight plus click/Enter, not a heavy button workflow.
- After confirming a screenshot selection, remember it for the next ten minutes,
  including after Frame restarts. A window selection revalidates its window ID
  against the current global window list before restoring it, while a region
  selection restores its saved rectangle. Either valid selection suppresses
  hover-based window preselection. A full-screen capture, a missing remembered
  window, or expiration clears the memory.
- Hover state is a circular background behind the icon, not a full cell or
  whole-toolbar highlight.
- Tooltips should be delayed and owned above the overlay/HUD layer. Default
  placement is below the hovered control, flipping above only when there is not
  enough space.
- Group the two capsules in a native glass container and use the material's own
  edge. Keep the selection scrim around the controls and reveal the desktop
  directly through the glass. Choose icon colors from the app appearance and
  keep hover fills subtle.
- Delay screenshot countdowns are passive: after the user starts the countdown,
  keep a prominent semi-transparent red countdown near the current screen's
  bottom center while letting underlying apps receive mouse interaction. Hide
  the selection HUD for the countdown so it cannot obstruct the desktop. Avoid
  a white outline around the countdown.

## Recording HUD

- The recording setup inherits the screenshot HUD appearance, with compact
  controls and delayed tooltips. Keep the primary recording action red with
  white text.
- The screenshot HUD may switch into recording setup without closing the
  selection overlay. Setup controls stay compact and cover start recording,
  MP4/GIF format, cursor visibility, and keyboard hint visibility. The MP4/GIF
  format toggle shows the selected format as visible short text so GIF is not
  mistaken for MP4.
- Mouse hint color is a recording output preference in Settings. Keep the
  recording setup HUD focused on showing or hiding mouse hints, while Settings
  owns a small curated preset set. In Settings, present it as a quiet preset-only
  swatch picker with a checkmark selected state; avoid custom color wells and
  reset actions for this preference.
- Keyboard hint visibility is retained as a setup option, but recording start
  must not show a static placeholder hint. Reintroduce a keyboard hint overlay
  only when it reflects real key activity.
- Starting a recording enters a short preparation/loading state before frames
  are written, giving Frame time to settle transient HUD state without making
  the user wait through a visible countdown.
- Active recording freezes the selected rectangle and replaces size editing
  with elapsed recording time. The action group contains stop, restart, and
  delete; pause/resume is not shown in the first refined recording HUD.
- During active recording, keep a visible non-interactive mask and selected
  region around the recorded rectangle while allowing desktop apps below it to
  receive mouse and keyboard interaction. Follow the screenshot selection visual
  language instead of switching the selection chrome to red.
- The recording HUD should sit outside the selected region when space allows.
  For full-screen selections it may sit inside the screen so controls remain
  reachable, but Frame-owned HUDs, recording boundaries, and keyboard hint
  overlays must not be recorded into the output.
- Stop actions acknowledge immediately: disable the stop affordance, show a
  stopping state, and keep the app responsive while finalization runs.
- Do not add a stop-recording keyboard shortcut in this version. The HUD and
  red menu bar recording state are the stop surfaces.

## HUD And Workspace Chrome

- HUD-like controls share one visual language across capture, Image Workspace,
  video preview/editing, and Quick Access surfaces.
- Use capsule geometry to group related controls in the capture launcher and
  image editor. Center the editor's markup tools in one quiet capsule. Give
  standalone actions pill backgrounds and keep the window header aligned
  with the native window controls. Center the text and chevron as one group
  inside menu pills, with equal padding at both ends.
- Use short visible labels for starting and finishing scrolling capture, starting
  recording, and the recording format. Keep secondary actions compact and give
  icon-only buttons a tooltip and accessibility label.
- Actions that are visible before their behavior is implemented stay disabled:
  no pointer cursor, no hover fill, and disabled tint.
- Use a circular or capsule-shaped highlight with an accent tint and a light
  glyph for selected tools. Use the same shape for pointer feedback.
- The window action row extends behind the native traffic lights. The
  appearance-aware titlebar surface spans both rows when the compact editing
  row is visible. Keep a small gap between the toolbar and the image.
- Workspace windows should open with the image area matching the screenshot
  aspect ratio so the initial preview does not show letterbox/pillarbox edges.
- Workspace resize keeps the image area at the screenshot aspect ratio while the
  top toolbar keeps a fixed height. This avoids empty preview fill during normal
  window resizing.
- During a live corner resize, keep the initial resize axis stable until the drag
  ends so AppKit and Frame do not alternate competing aspect-ratio corrections.
- Resizable workspace windows must set a minimum width that keeps the full
  toolbar visible at the smallest allowed size.
- Image Workspace panels use the native macOS window shadow because the surface
  behaves like a real movable and resizable window. Avoid custom shadow gutters
  unless the workspace becomes a borderless HUD-like surface again.
- Pinned windows give the image its own surface below the native titlebar.
  Put output actions in the context menu.
- Pinned image windows expose Copy, Download, and Edit through the context menu.
  These actions must not close the pinned window. Edit opens or activates the
  preview/edit workspace for the same screenshot.
- Every icon-only action must keep a tooltip and accessibility label.
- Video Preview output actions follow the workspace's traffic-light-safe header
  pattern: a compact, right-aligned group of fixed-width icon cells with a
  centered hover circle. Keep playback, duration, speed, and the timeline in the
  bottom editor bar. Use a few subdued frames in longer MP4 timelines to help
  users find a position without hiding the trim handles or time labels.

## Quick Access

- Quick Access is a small fixed post-capture preview with icon-only hover
  actions for copy, save, workspace, pin, and close. Lead with copy and save,
  and give secondary actions quieter icons.
- Auto-copy is on by default and lives in Capture settings. Copy screenshots
  as images and recordings as files after capture completes, and keep their
  previews available. Copy only the active display's image during a multi-display
  full-screen capture. A scrolling capture copies its final stitched image.
- Each preview auto-dismisses after 30 seconds by default once its result has
  been copied or stored in history. Capture settings offer 10 seconds,
  30 seconds, 1 minute, and Never for subsequent previews. Start the timer
  after final stitching and pause it during hover, pointer interaction, OCR,
  or temporary hiding.
- Keep captured image and video pixels visually true. Apply stable deep glass
  only to hover action overlays, close/status/duration accessories, fallback
  placeholders, and the larger hover preview shell so arbitrary media or
  wallpaper cannot lower control contrast.
- It anchors to the active screen's bottom-left corner with equal left and
  bottom padding.
- While previews are visible, they follow active-screen changes.
- Multiple previews stack upward from the bottom-left corner.
- Dragging the preview image outputs image content to targets that accept PNG
  pasteboard drags.
- Workspace opens a movable preview/edit window that stays open across focus
  changes. If there are unsaved edits, Escape or the native close control asks
  Save, Don't Save, or Cancel. Save follows the configured Save Current default;
  only an explicit Ask Every Time preference exposes Replace Current / Save As
  New in this close flow. Pin behavior is handled separately as an image-only
  pinned window.
- Opening workspace again for the same captured screenshot activates the existing
  preview/edit window instead of creating duplicates.
- Undo and Redo sit beside the traffic lights. Center the markup group in the
  remaining space before Copy, Export, and Save Current. Use 36 pt targets
  and 18 pt glyph boxes for markup. Give Save Current the primary treatment.
- Open the right inspector by default. The titlebar toggle hides it and
  returns the width to the canvas. Selecting a tool or object changes the
  inspector's controls. Give shapes a color, width, and line or fill controls.
  Give text a font, size, bold and italic, alignment, and color. Show all four
  redaction modes and the settings for the selected mode.
- Put Crop, Resize, Transform, and zoom controls in the inspector when it is
  expanded. Crop replaces the tool controls with aspect ratio, pixel dimensions,
  Cancel, and Apply. When the inspector is collapsed, restore a compact editing
  row and footer zoom controls. Keep the window frame stable when toggling.
- Return applies the crop and Escape cancels it. The canvas status row shows
  actual pixel dimensions and feedback. The canvas has an opaque work area and a
  checkerboard where the image has transparent pixels.
- Crop, resize, rotate, flip, and raster adjustments share undo with annotation
  edits. Guides and object handles are visible on canvas only. Shapes use
  corner handles. Lines and arrows use their actual endpoints. Hold Shift
  while drawing to constrain shapes and angles, and hold Option while
  dragging with a drawing tool to draw over an existing annotation.
- Inline text starts on a blank click. Drag for a fixed-width text box.
  Double-click to re-edit text and press Escape to restore it as it was before
  entering that edit. The text editor keeps native selection and clipboard
  shortcuts. With the canvas focused, `V`, `R`, `O`, `L`, `A`, `B`, `T`, `H`,
  and `M` switch tools, and `[` / `]` step through common sizes.
- Mosaic has a compact split control for Region, Brush, Blur, and Solid
  Redaction. Preview the effect during the drag. Block size and brush width
  are independent. Draw solid redactions above the other objects and omit
  text intersecting them from OCR selection. Share a flattened image when
  redaction is used. Editable project files include the underlying image.
- Copy and Export deliver the currently rendered image, show feedback, and
  keep the editor open. The Copy and Export actions leave history as it is.
  Save Current follows the configured default. Replace Current updates the
  history entry and any active originating preview. Save As New creates a
  separate history entry and a preview. Both respect history settings, and
  the current session keeps editable objects and undo after a save.
- A local `.frameimage` project stores the current raster and objects so a user
  can continue editing later. An image exported from the same session contains
  the flattened result. Importing a local image opens a new session, so replacing
  the history version leaves the source file in place.
- It should stay lightweight and dismissible, without blocking normal system
  usage.
- Starting a recording temporarily hides existing Quick Access cards; it must
  restore them after recording completes or fails, then stack the new recording
  card with the existing previews instead of clearing the stack.
- Screenshots and recordings share one Quick Access stack and one visual
  language. Recording cards use the centered play affordance to open Preview;
  hover actions expose Download, Copy, Edit, and Close so playback entry is not
  duplicated. Edit is enabled for MP4 and disabled for GIF. Preview and Edit
  open the same playable video window; MP4 windows hide the native AVPlayer
  playback controls and titlebar filename prominence, keep Save Current, Copy,
  and Download in the same right-aligned header row pattern as screenshot
  editing, and show Frame's compact grouped bottom media control strip by
  default. The strip uses a mini timeline for progress/seek, start/end trim
  handles, and read-only start/end time labels, with time labels placed inside
  wide selections, outside narrow selections when room allows, and clamped at
  crowded edges. The timeline strip and trim handles use a pointing-hand cursor.
  The bottom row stays minimal and aligned to the mini timeline's visible track:
  a neutral circular play/pause icon button with no native focus ring or blue
  accent fill, a current/selected duration summary that adds output duration
  when speed is not `1x`, and a speed dropdown sized so Chinese labels and the
  longest preset do not clip. Do not add a bottom Trim chip or make the controls
  read as a large form. Use the first decodable recording frame as the thumbnail,
  with a lightweight video placeholder as the fallback.
  Screenshots and recordings should render in the same fixed card size,
  preserving media aspect ratio inside that footprint. Keep the rendered content
  size asserted so the preview cannot collapse into a thin strip.
- Hovering a Quick Access card for two seconds opens a transient rounded
  right-side popover without an arrow. Image and recording previews render larger
  using the original media aspect ratio and aspect-fit scaling so the full image
  or video is visible; recording previews play muted and close with the hover
  state.

## Capture History

- Capture History is a recovery browser, not a file manager. Prefer preview
  tiles over table rows so screenshot content remains the primary surface.
- Use a native macOS window with system traffic-light controls, a transparent
  titlebar, and `fullSizeContentView`. Avoid a fully custom borderless window
  unless the product intentionally gives up standard window behavior.
- The titlebar chrome should blend with the content background. Keep the
  traffic-light safe area clear, and place compact filters in the titlebar
  rather than adding a separate toolbar band.
- History tiles follow the Quick Access visual language: rounded image preview,
  fine translucent border, compact metadata, and icon-only hover HUD actions.
- Single-click selects a history tile. Double-click or Return opens the selected
  screenshot in the image workspace or recording in Frame's video preview.
  Restore brings the capture back to the bottom-left Quick Access stack.
  Restored recordings must keep enough media metadata, including duration, for
  the same Preview and Edit actions available after a fresh recording.
- Recording history tiles should use the first decodable recording frame as the
  preview image and fall back to a lightweight video placeholder only when
  decoding fails.
- Keep history actions hidden until the tile is hovered. Place capture time on
  the first line below the preview and keep dimensions and size secondary.
  Empty history offers a capture action, a filter reset, or a route to Settings
  depending on why the grid is empty.
