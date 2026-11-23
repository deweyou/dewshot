# macOS Permissions

dewShot needs macOS Screen Recording permission because it captures pixels directly from the display instead of using the system screenshot picker.

On recent macOS versions, the permission prompt may mention bypassing the system private window picker or directly accessing screen and audio. That wording is expected for apps that request Screen Recording or Screen & System Audio Recording access.

dewShot's Settings permission section also reports two feature-specific permissions:

- Accessibility allows dewShot to post automatic scroll events for scrolling screenshots.
- Input Monitoring allows live keyboard hints during recordings.

Screenshot and recording capture only require Screen Recording. In dewShot's
Permissions pane, granted access shows a checkmark. Missing access shows a link
to the corresponding macOS settings pane. dewShot checks again when the
Permissions pane appears or the app becomes active.

When Accessibility access is missing, the automatic scrolling control in the
capture HUD explains how to open Settings and leaves manual scrolling available.
If Input Monitoring is missing, the recording setup marks keystroke hints as
unavailable. Selecting that control offers a link to System Settings. The
recording can still start with keystroke hints off. Opening System Settings
closes the full-screen selection so that System Settings can receive input.

## Development Signing

TCC authorization is tied to app identity, path, and code signature. Ad-hoc signing is useful for CI and first-time setup, but it can make macOS treat rebuilt bundles as new apps.

For repeat local testing, sign the `development` variant with Apple
Development and keep one installed path, `~/Applications/dewShot Dev.app`.
When upgrading from a build with a Frame bundle identifier, grant Screen
Recording and any optional capture permissions again for the new app identity.
Follow the [local installation flow](development.md#manual-smoke-test).
Authorize that installed copy, then quit and reopen it before testing capture.

## Reset Permission

If macOS keeps a stale entry for a previous local build:

```sh
tccutil reset ScreenCapture dev.deweyou.dewshot.dev
```

Then reopen the current app bundle and request permission again.

## Distribution Note

For public ZIP or DMG distribution, sign the production variant with
Developer ID Application and submit it for Apple notarization.

The production and development bundle identifiers have separate TCC records:

- `dev.deweyou.dewshot` for dewShot
- `dev.deweyou.dewshot.dev` for dewShot Dev

See [Signing and development-device migration](signing-and-device-migration.md) before setting up or replacing a development Mac.
