# Developing DewShot

[中文](DEVELOPMENT_ZH.md)

Use macOS 26 or later, Swift 6.2, and Xcode command line tools with the macOS 26 SDK or later. From the repository root, run `swift build` to compile the Swift package. Local compilation and ad-hoc packaging work without a developer account.

## Before committing

Review the staged diff with `git diff --cached` and check whitespace with `git diff --cached --check`. Choose additional checks by what changed.

| Change | Local check |
| --- | --- |
| Documentation | Resolve changed links and headings. Check command examples against their scripts. |
| Swift logic | Run the affected suite, for example `swift test --filter RecordingNamingTests` for recording names. |
| Packaging | Exercise the affected variant. For bundle mapping, use `scripts/package-app.sh --print-configuration`. For changes to the packaged contents, build and inspect the artifact. |
| AppKit or desktop behavior | Run the affected [component tests](docs/testing.md#ci-expectations). Use the signed app for the specific shortcut, permission or capture flow that changed. |

## Before merging and releasing

Review the CI result for the current PR revision before merging. GitHub Actions runs the stable suite, build, package and bundle checks on pull requests and pushes to `main`. Three real-window AppKit suites run locally when relevant. For release acceptance, test the designated build installed through TestFlight.

See the [build and release procedures](docs/development.md) for signed Dev installation, sandbox verification and distribution. The [knowledge base](docs/README.md) indexes product, design, architecture and testing decisions.

For Store candidates and post-publication merge-back, use the [release SOP](docs/release.md).
