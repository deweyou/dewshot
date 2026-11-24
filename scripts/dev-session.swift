#!/usr/bin/env swift
import AppKit
import Darwin
import Foundation

struct Session: Codable {
    var id = UUID()
    let dev: URL
    let production: URL
    let restoreOnQuit: Bool
}

struct SessionError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

let devID = "dev.deweyou.dewshot.dev"
let productionID = "dev.deweyou.dewshot"
let files = FileManager.default
let folder = URL.applicationSupportDirectory.appending(path: "DewShot Development")
let state = folder.appending(path: "session.json")
let installedProduction = URL(fileURLWithPath: "/Applications/dewShot.app")

func locked<T>(_ work: () throws -> T) throws -> T {
    try files.createDirectory(at: folder, withIntermediateDirectories: true)
    let fd = open(folder.appending(path: "lock").path, O_CREAT | O_RDWR, 0o600)
    guard fd >= 0 else { throw SessionError("Cannot open the session lock.") }
    defer { close(fd) }
    guard flock(fd, LOCK_EX) == 0 else { throw SessionError("Cannot lock the development session.") }
    return try work()
}

func savedSession() throws -> Session? {
    guard files.fileExists(atPath: state.path) else { return nil }
    return try JSONDecoder().decode(Session.self, from: Data(contentsOf: state))
}

func instances(_ id: String) -> [NSRunningApplication] {
    NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { !$0.isTerminated }
}

func quit(_ apps: [NSRunningApplication]) throws {
    for app in apps where !app.isTerminated {
        guard app.terminate() || app.isTerminated else {
            throw SessionError("Quit \(app.localizedName ?? "DewShot") normally and retry.")
        }
    }
    let deadline = Date().addingTimeInterval(10)
    while apps.contains(where: { !$0.isTerminated }) {
        guard Date() < deadline else { throw SessionError("The app is still running. Finish any recording, quit it and retry.") }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
}

func verify(_ url: URL, id: String) throws {
    guard Bundle(url: url)?.bundleIdentifier == id else {
        throw SessionError("Expected \(id) at \(url.path).")
    }
}

func launch(_ url: URL, id: String) throws -> NSRunningApplication {
    try verify(url, id: id)
    let path = url.resolvingSymlinksInPath().standardizedFileURL.path
    if let existing = instances(id).first(where: { $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path == path }) {
        return existing
    }
    var result: Result<NSRunningApplication, Error>?
    let config = NSWorkspace.OpenConfiguration()
    NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
        if let app { result = .success(app) }
        else { result = .failure(error ?? SessionError("Could not launch \(path).")) }
    }
    while result == nil { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
    let app = try result!.get()
    guard app.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path == path else {
        throw SessionError("macOS opened another copy of \(id). Quit that copy and retry.")
    }
    return app
}

func start(_ override: String?) throws -> (Session, NSRunningApplication) {
    let prior = try savedSession()
    let runningDev = instances(devID)
    let runningProduction = instances(productionID)
    guard runningProduction.count <= 1, runningDev.count <= 1 else {
        throw SessionError("Multiple copies are running. Quit the extra copies before starting a session.")
    }
    let installedDev = files.homeDirectoryForCurrentUser.appending(path: "Applications/dewShot Dev.app")
    let sandboxDev = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: ".build/app-sandbox/dewShot Dev.app")
    let dev = override.map { URL(fileURLWithPath: $0).standardizedFileURL }
        ?? prior?.dev ?? runningDev.first?.bundleURL ?? (files.fileExists(atPath: installedDev.path) ? installedDev : sandboxDev)
    let production = runningProduction.first?.bundleURL ?? prior?.production ?? installedProduction
    try verify(dev, id: devID)
    try verify(production, id: productionID)
    if let running = runningDev.first?.bundleURL, running.standardizedFileURL.path != dev.standardizedFileURL.path {
        throw SessionError("A different Dev build is running at \(running.path). Quit it and retry.")
    }
    let session = Session(dev: dev, production: production, restoreOnQuit: !runningProduction.isEmpty || prior?.restoreOnQuit == true)
    try JSONEncoder().encode(session).write(to: state, options: .atomic)
    try quit(runningProduction)
    do {
        return (session, try launch(dev, id: devID))
    } catch {
        if instances(devID).isEmpty {
            if session.restoreOnQuit { _ = try launch(production, id: productionID) }
            try files.removeItem(at: state)
        }
        throw error
    }
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    switch args.first {
    case "start" where args.count <= 2:
        let (session, app) = try locked { try start(args.dropFirst().first) }
        print("Dev is running at \(session.dev.path). Use dev-session.swift stop to return to production.")
        while !app.isTerminated { RunLoop.current.run(until: Date().addingTimeInterval(0.5)) }
        try locked {
            guard try savedSession()?.id == session.id, instances(devID).isEmpty else { return }
            if session.restoreOnQuit { _ = try launch(session.production, id: productionID) }
            try files.removeItem(at: state)
        }
    case "stop" where args.count == 1:
        try locked {
            let session = try savedSession()
            let destination = session?.production ?? instances(productionID).first?.bundleURL ?? installedProduction
            try verify(destination, id: productionID)
            try quit(instances(devID))
            _ = try launch(destination, id: productionID)
            if session != nil { try files.removeItem(at: state) }
            print("Production is running at \(destination.path).")
        }
    default:
        throw SessionError("Usage: scripts/dev-session.swift start [path-to-dev.app] | stop")
    }
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
