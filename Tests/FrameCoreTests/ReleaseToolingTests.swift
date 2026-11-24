import Foundation
import XCTest

final class ReleaseToolingTests: XCTestCase {
    func testReleaseScriptHasValidShellSyntax() throws {
        let result = try run([
            "bash",
            "-c",
            """
            for script in scripts/package-app.sh scripts/package-app-store.sh scripts/package-release.sh; do
                bash -n "$script" || exit 1
            done
            """,
        ])

        XCTAssertEqual(result.exitCode, 0, result.diagnosticOutput)
    }

    func testPackageAppUsesRegisteredProductionIdentityByDefault() throws {
        let result = try run([
            "bash",
            repositoryRoot.appendingPathComponent("scripts/package-app.sh").path,
            "--print-configuration",
        ])

        XCTAssertEqual(result.exitCode, 0, result.diagnosticOutput)
        XCTAssertTrue(result.stdout.contains("FRAME_APP_VARIANT=production"), result.diagnosticOutput)
        XCTAssertTrue(result.stdout.contains("FRAME_APP_NAME=dewShot"), result.diagnosticOutput)
        XCTAssertTrue(result.stdout.contains("FRAME_BUNDLE_ID=dev.deweyou.dewshot"), result.diagnosticOutput)
        XCTAssertTrue(
            result.stdout.contains("FRAME_APP_PATH=\(repositoryRoot.path)/.build/app/dewShot.app"),
            result.diagnosticOutput
        )
    }

    func testPackageAppUsesRegisteredDevelopmentIdentityWhenRequested() throws {
        let result = try run(
            [
                "bash",
                repositoryRoot.appendingPathComponent("scripts/package-app.sh").path,
                "--print-configuration",
            ],
            environment: ["FRAME_APP_VARIANT": "development"]
        )

        XCTAssertEqual(result.exitCode, 0, result.diagnosticOutput)
        XCTAssertTrue(result.stdout.contains("FRAME_APP_VARIANT=development"), result.diagnosticOutput)
        XCTAssertTrue(result.stdout.contains("FRAME_APP_NAME=dewShot Dev"), result.diagnosticOutput)
        XCTAssertTrue(result.stdout.contains("FRAME_BUNDLE_ID=dev.deweyou.dewshot.dev"), result.diagnosticOutput)
        XCTAssertTrue(
            result.stdout.contains("FRAME_APP_PATH=\(repositoryRoot.path)/.build/app/dewShot Dev.app"),
            result.diagnosticOutput
        )
    }

    func testSandboxedDevelopmentPackageHasSeparateOutput() throws {
        let result = try run(
            [
                "bash",
                repositoryRoot.appendingPathComponent("scripts/package-app.sh").path,
                "--print-configuration",
            ],
            environment: ["FRAME_APP_VARIANT": "development", "FRAME_APP_SANDBOX": "1"]
        )

        XCTAssertEqual(result.exitCode, 0, result.diagnosticOutput)
        XCTAssertTrue(
            result.stdout.contains("FRAME_APP_PATH=\(repositoryRoot.path)/.build/app-sandbox/dewShot Dev.app"),
            result.diagnosticOutput
        )
    }

    func testAppStorePackageRequiresDistributionSigning() throws {
        let result = try run(
            ["bash", repositoryRoot.appendingPathComponent("scripts/package-app-store.sh").path],
            environment: ["FRAME_APP_STORE_APP_IDENTITY": ""]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("FRAME_APP_STORE_APP_IDENTITY"), result.diagnosticOutput)
    }

    func testPackageAppRejectsUnknownVariant() throws {
        let result = try run(
            [
                "bash",
                repositoryRoot.appendingPathComponent("scripts/package-app.sh").path,
                "--print-configuration",
            ],
            environment: ["FRAME_APP_VARIANT": "staging"]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.diagnosticOutput.contains("Unsupported FRAME_APP_VARIANT: staging"), result.diagnosticOutput)
    }

    func testPackageReleaseAlwaysUsesProductionVariant() throws {
        let script = try String(contentsOf: repositoryRoot.appendingPathComponent("scripts/package-release.sh"))

        XCTAssertTrue(script.contains("FRAME_APP_VARIANT=production"), script)
        XCTAssertFalse(script.contains("FRAME_APP_VARIANT=development"), script)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func run(_ arguments: [String], environment: [String: String] = [:]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = repositoryRoot
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return CommandResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}

private struct CommandResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var diagnosticOutput: String {
        [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
