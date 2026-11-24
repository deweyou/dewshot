## Project Context

dewShot is a native macOS screenshot and screen recording tool. Editing, saving, and sharing captures are part of its core workflow. See [Product Positioning](docs/product-positioning.md) when deciding what to develop or prioritize.

## Feature telemetry

For each new requirement, identify the product, latency or failure question worth
measuring. Check the [telemetry PRD](docs/dewshot-telemetry-prd.md) for an existing
event or parameter that answers it. Record the decision in the requirement or PR,
including when existing coverage is sufficient or measurement adds no value.
Add an event only for a distinct observation that needs its own count. Update
the PRD when event definitions or counting rules change.

## Verification

Before committing, review the staged diff and run the checks affected by the change.
For documentation, check links, anchors, and command examples. For Swift logic,
run the matching XCTest filter. For packaging, exercise the affected script or
artifact. Use the [development guide](DEVELOPMENT.md) to choose a check.

Review the [CI result](.github/workflows/ci.yml) for the PR revision before merging.
CI owns the stable suite, build, packaging, and bundle checks. Real-window tests
and desktop interactions use the [local test boundaries](docs/testing.md#ci-expectations).

For local GUI iteration, use the signed development variant and the
[local installation flow](docs/development.md#manual-smoke-test). For sandbox
behavior, use the [sandbox smoke test](docs/development.md#sandbox-smoke-test).
For release acceptance, use the [designated TestFlight build](docs/development.md#mac-app-store-and-testflight).
Report the build tested and the interaction observed. Replace a local Dev app
when the requested verification calls for it and installation is authorized.

When testing Dev alongside an installed production copy, use
`scripts/dev-session.swift start` for the shortcut handoff. At the end of
testing, run `scripts/dev-session.swift stop` to close Dev and reopen the
user's production app, unless the user wants Dev left open for review.
See [Switching between production and Dev](docs/development.md#switching-between-production-and-dev).

## Knowledge Base

Start with the [knowledge base](docs/README.md). Update the document that owns a
decision when it changes. Keep release commands and manual test procedures there.

## Product README

`README.md` is the English product overview and `README_ZH.md` is the Chinese product overview. Keep them aligned. Whenever adding, removing, or materially changing a user-facing feature, check whether both README files need updates.

## Changelog

For user-facing features, behavior changes, bug fixes, and release workflow changes, update `CHANGELOG.md` in the same task unless the user explicitly asks not to. Put changes that are already in the current code but not yet released under `Unreleased`; keep already released behavior under its versioned section. Skip changelog entries for purely internal refactors, tests, or cleanup that do not affect user-visible behavior or release mechanics.

## macOS Permission Notes

Screen Recording permission is tied to the app identity and code signature.
For repeat GUI testing, keep the same Apple Development identity, development
bundle identifier, and installed path. See [macOS Permissions](docs/permissions.md).

## Git Hygiene

- Do not commit `.build/`, `.superpowers/`, Xcode user state, or local app bundles.
- Do not stage unrelated user files.
- Keep feature work on `codex/*` branches unless the user asks otherwise.
