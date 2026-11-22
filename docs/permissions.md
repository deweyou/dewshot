# macOS Permissions

Frame needs macOS Screen Recording permission because it captures pixels directly from the display instead of using the system screenshot picker.

On recent macOS versions, the permission prompt may mention bypassing the system private window picker or directly accessing screen and audio. That wording is expected for apps that request Screen Recording or Screen & System Audio Recording access.

Frame's Settings permission section also reports two feature-specific permissions:

- Accessibility allows Frame to post automatic scroll events for scrolling screenshots.
- Input Monitoring allows live keyboard hints during recordings.

Screenshot and recording capture only require Screen Recording. The other two permissions are optional until their related feature is used. Each row provides a request action and a direct System Settings action, and the displayed state refreshes when Frame becomes active again.

## Development Signing

TCC authorization is tied to app identity, path, and code signature. Ad-hoc signing is useful for CI and first-time setup, but it can make macOS treat rebuilt bundles as new apps.

For repeat local testing, sign the `development` variant with Apple
Development and keep one installed path, `~/Applications/Frame Dev.app`.
Follow the [local installation flow](development.md#manual-smoke-test).
Authorize that installed copy, then quit and reopen it before testing capture.

## Reset Permission

If macOS keeps a stale entry for a previous local build:

```sh
tccutil reset ScreenCapture dev.deweyou.frame.dev
```

Then reopen the current app bundle and request permission again.

## Distribution Note

For public ZIP or DMG distribution, sign the production variant with
Developer ID Application and submit it for Apple notarization.

The production and development bundle identifiers have separate TCC records:

- `dev.deweyou.frame` for Frame
- `dev.deweyou.frame.dev` for Frame Dev

See [Signing and development-device migration](signing-and-device-migration.md) before setting up or replacing a development Mac.
