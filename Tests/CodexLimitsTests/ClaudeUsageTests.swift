import Foundation
import Testing
@testable import CodexLimits

struct ClaudeUsageTests {
    @Test func mapsFiveHourAndWeeklyUsageAndResetTimes() throws {
        let json = """
        {"five_hour":{"utilization":21.4,"resets_at":"2026-10-02T23:00:00.123+00:00"},
         "seven_day":{"utilization":0,"resets_at":"2026-10-09T12:00:00Z"},
         "seven_day_sonnet":{"utilization":95,"resets_at":null},"extra_usage":null}
        """
        let payload = try JSONDecoder().decode(ClaudeUsagePayload.self, from: Data(json.utf8))
        let date = Date(timeIntervalSince1970: 123)
        let snapshot = try payload.snapshot(source: "Claude Desktop", at: date)
        #expect(snapshot.windows.map(\.durationLabel) == ["5h", "7d"])
        #expect(snapshot.windows.map(\.remainingPercent) == [79, 100])
        #expect(snapshot.windows.allSatisfy { $0.resetsAt != nil })
        #expect(snapshot.fetchedAt == date)
        #expect(snapshot.sourceName == "Claude Desktop")
    }

    @Test func absentAndNullLimitsAreNotPresentedAsUnusedAllowance() throws {
        let payload = try JSONDecoder().decode(ClaudeUsagePayload.self,
            from: Data(#"{"five_hour":null,"seven_day":{"utilization":null,"resets_at":null}}"#.utf8))
        #expect(throws: ClaudeUsageError.noSubscriptionLimits) { try payload.snapshot(source: "Claude Code") }
    }

    @Test func clampsUsageAndAllowsWeeklyOnlyResponse() throws {
        let payload = ClaudeUsagePayload(five_hour: nil, seven_day: .init(utilization: 140, resets_at: nil))
        #expect(try payload.snapshot(source: "Claude Code").windows[0].remainingPercent == 0)
        let negative = ClaudeUsagePayload(five_hour: .init(utilization: -5, resets_at: nil), seven_day: nil)
        #expect(try negative.snapshot(source: "Claude Code").windows[0].remainingPercent == 100)
    }

    @Test func malformedResetAndNonFiniteUsageAreRejected() {
        let payload = ClaudeUsagePayload(five_hour: .init(utilization: 20, resets_at: "bad date"), seven_day: nil)
        #expect(throws: ClaudeUsageError.invalidResponse) { try payload.snapshot(source: "Claude Code") }
        let invalid = ClaudeUsagePayload(five_hour: .init(utilization: .infinity, resets_at: nil), seven_day: nil)
        #expect(throws: ClaudeUsageError.invalidResponse) { try invalid.snapshot(source: "Claude Code") }
    }

    @Test func desktopCacheSelectsCurrentAccountAndAnthropicInferenceOnly() {
        let entry: [String: Any] = ["token": "test-token", "expiresAt": 1_800_000_000_000]
        let cache: [String: Any] = [
            "acct:current|client:org:https://api.anthropic.com:user:inference user:profile": entry,
            "acct:other|client:org:https://api.anthropic.com:user:inference": entry,
            "acct:current|client:org:https://example.com:user:inference": entry,
            "acct:current|client:org:https://api.anthropic.com:user:profile org:desktop_config": entry,
            "client:org:https://api.anthropic.com:user:inference": entry,
        ]
        let credentials = ClaudeCredentials.desktopCredentials(in: cache, account: "current")
        #expect(credentials.count == 1)
        #expect(credentials.first?.source == "Claude Desktop")
        #expect(credentials.first?.expiresAt == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(ClaudeCredentials.desktopCredentials(in: cache, account: nil).isEmpty)
    }

    @Test func rejectsUnsupportedDesktopEncryption() {
        #expect(throws: ClaudeUsageError.invalidResponse) {
            try ClaudeCredentials.decryptDesktopCache(Data("v20unsupported".utf8), password: Data("test".utf8))
        }
    }

    @Test func discoversClaudeNativeInstallWithoutGUIPath() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(!UsageController.claudeCodeInstalled(home: home, searchPath: "/no-such-path"))
        let executable = home.appending(path: ".local/bin/claude")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        #expect(UsageController.claudeCodeInstalled(home: home, searchPath: "/no-such-path"))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CLAUDE_KEYCHAIN_SILENT_TEST"] == "1"))
    func readsInstalledCodeCredentialWithoutShowingAuthenticationUI() throws {
        let start = Date.now
        do {
            _ = try ClaudeCredentials.codeCredential()
        } catch {
            #expect(error as? ClaudeUsageError == .keychainDenied || error as? ClaudeUsageError == .notSignedIn)
        }
        #expect(Date.now.timeIntervalSince(start) < 3)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CLAUDE_LIMITS_LIVE_TEST"] == "1"))
    func readsDesktopLimitsWithoutCLI() async throws {
        let snapshot = try await ClaudeUsageClient(hasCode: false, hasDesktop: true).read()
        #expect(!snapshot.windows.isEmpty)
        #expect(snapshot.sourceName == "Claude Desktop")
        #expect(snapshot.windows.allSatisfy { (0...100).contains($0.remainingPercent) })
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CLAUDE_CODE_LIMITS_LIVE_TEST"] == "1"))
    func readsCodeLimitsWithoutDesktop() async throws {
        let snapshot = try await ClaudeUsageClient(hasCode: true, hasDesktop: false).read()
        #expect(!snapshot.windows.isEmpty)
        #expect(snapshot.sourceName == "Claude Code")
    }
}
