import Foundation
import Testing
@testable import CodexLimits

struct CodexInstallationTests {
    @Test func resolvesCurrentNestedCLI() throws {
        let app = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".app")
        defer { try? FileManager.default.removeItem(at: app) }
        let executable = app.appending(path: "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        #expect(try UsageController.bundledCodexExecutableURL(in: app) == executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: executable.path)
        #expect(throws: UsageError.codexExecutableMissing) {
            try UsageController.bundledCodexExecutableURL(in: app)
        }
    }

    @Test func oldBundleLayoutIsNotUsed() throws {
        let app = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".app")
        defer { try? FileManager.default.removeItem(at: app) }
        let executable = app.appending(path: "Contents/Resources/codex")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        #expect(throws: UsageError.codexExecutableMissing) {
            try UsageController.bundledCodexExecutableURL(in: app)
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CODEX_LIMITS_LIVE_TEST"] == "1"))
    @MainActor func readsLimitsFromInstalledSignedApp() async throws {
        let executable = try UsageController.codexExecutableURL()
        let client = CodexAppServerClient(executableURL: executable)
        do {
            let snapshot = try await client.read()
            #expect(!snapshot.windows.isEmpty)
            #expect(snapshot.windows.allSatisfy { (0...100).contains($0.remainingPercent) })
            let refreshed = try await client.read()
            #expect(!refreshed.windows.isEmpty)
            await client.stop()
        } catch {
            await client.stop()
            throw error
        }
    }
}
