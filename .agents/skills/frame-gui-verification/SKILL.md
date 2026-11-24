---
name: frame-gui-verification
description: Verify dewShot GUI behavior in a signed local Dev app or a designated TestFlight build. Use for focused AppKit checks and live macOS tests of capture, permissions, and sandbox file access.
---

# dewShot GUI Verification

Produce trustworthy local evidence for a user-facing dewShot change. Do not treat a successful build, package, or launch as proof that the changed interaction works.

## Establish The Verification Scope

Use the current checkout for local verification. For release acceptance, record
the installed TestFlight version and build number and test that copy.

Before acting, read:

- `AGENTS.md` for the current packaging, replacement, and handoff contract.
- `docs/testing.md` for the automated-versus-manual test boundary.
- `docs/permissions.md` when Screen Recording, TCC, signing identity, or app-path stability matters.
- `docs/development.md` for the applicable manual smoke flow.
- `DESIGN.md` and `docs/overlay-interactions.md` when the change affects HUD, overlay, Quick Access, or workspace interaction behavior.

Identify the user-visible claims that need live proof. Reuse test and packaging
results that match the source and configuration under test.

## Select The Test App

For a local Dev session alongside production, execute the [local GUI test SOP](../../../docs/development.md#local-gui-test-sop) through its restoration check.

- For local iteration, follow the installation steps in `docs/development.md`.
  Check the installed Dev bundle's Apple Development signature, bundle ID and running path.
- For local sandbox checks, package with `FRAME_APP_SANDBOX=1` and verify the
  sandbox entitlement on the installed copy before testing saves or permissions.
- For release acceptance, run the build installed through TestFlight. Check
  first-run setup, screenshots and recording playback for the scoped change.

Use existing authorization for local installation, launch and desktop testing.
If an action needs new permission, complete independent checks and identify the
remaining live check. Keep routine rebuilds on the same app identity and path.
Check the running app and its signature before considering a permission reset.

## Verify The Changed Behavior

Choose evidence by claim:

- Use focused XCTest coverage for deterministic FrameCore behavior and AppKit component interactions supported by `docs/testing.md`.
- Use a real installed app for permissions, global shortcuts, ScreenCaptureKit flows, multi-display behavior, and full desktop interaction.
- Use the smallest relevant section of the manual smoke flow. Do not repeat the complete checklist when the change affects only one bounded surface.
- Capture screenshots, process details, signature output, or concise observations when they materially prove the claim.

When GUI control is unavailable, provide an exact bounded manual check and mark the live claim unverified. A handoff checklist is not live evidence.

## Report The Result

Report the tested build, relevant automated checks, the actions observed in
the running app, and any unverified behavior. Include signing and permission
details when they affect the result.
