import Foundation
import LocalAuthentication
import Security
import Testing
@testable import CodexLimits

private final class UsageRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    func record(_ token: String) { lock.withLock { counts[token, default: 0] += 1 } }
    func count(_ token: String) -> Int { lock.withLock { counts[token, default: 0] } }
}

private final class UsageStub: URLProtocol, @unchecked Sendable {
    static let requests = UsageRequests()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let token = request.value(forHTTPHeaderField: "Authorization") ?? ""
        Self.requests.record(token)
        let status = token.contains("limited") ? 429 : token.contains("unauthorized") ? 401 : 200
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Retry-After": "300"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"five_hour":{"utilization":25,"resets_at":null},"seven_day":{"utilization":40,"resets_at":null}}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class UsageClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date.now
    var date: Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value += seconds } }
}

struct ClaudeClientTests {
    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UsageStub.self]
        return URLSession(configuration: configuration)
    }

    @Test func backgroundKeychainQueriesDisallowAuthenticationUI() {
        let silent = ClaudeCredentials.keychainQuery(service: "test-only", allowPrompt: false) as NSDictionary
        let interactive = ClaudeCredentials.keychainQuery(service: "test-only", allowPrompt: true) as NSDictionary
        #expect((silent[kSecUseAuthenticationContext] as? LAContext)?.interactionNotAllowed == true)
        #expect((interactive[kSecUseAuthenticationContext] as? LAContext)?.interactionNotAllowed == false)
    }

    @Test func backgroundReadsNeverRequestApprovalWhenAccessIsDenied() async {
        let clock = UsageClock()
        let attempts = UsageRequests()
        let client = ClaudeUsageClient(hasCode: true, hasDesktop: false, session: session(),
            loadCode: { allow in
                attempts.record(allow ? "interactive" : "silent")
                throw ClaudeUsageError.keychainDenied
            }, now: { clock.date })
        for _ in 0..<3 {
            do {
                _ = try await client.read()
                Issue.record("Expected denied access")
            } catch {
                #expect(error as? ClaudeUsageError == .keychainDenied)
            }
            clock.advance(61)
        }
        #expect(attempts.count("silent") == 3)
        #expect(attempts.count("interactive") == 0)
    }

    @Test func oneTimeApprovalIsReusedAcrossBackgroundRefreshes() async throws {
        let clock = UsageClock()
        let attempts = UsageRequests()
        let token = UUID().uuidString
        let client = ClaudeUsageClient(hasCode: true, hasDesktop: true, session: session(),
            loadCode: { allow in
                attempts.record(allow ? "interactive" : "silent")
                guard allow else { throw ClaudeUsageError.keychainDenied }
                return .init(token: token, expiresAt: clock.date.addingTimeInterval(3600), source: "Claude Code")
            }, loadDesktop: { _ in throw ClaudeUsageError.notSignedIn }, now: { clock.date })
        do {
            _ = try await client.read()
            Issue.record("Expected denied access")
        } catch {
            #expect(error as? ClaudeUsageError == .keychainDenied)
        }
        // Explicit Refresh can approve immediately after the silent denial.
        let approved = try await client.read(allowKeychainPrompt: true)
        clock.advance(61)
        let firstRefresh = try await client.read()
        clock.advance(61)
        let secondRefresh = try await client.read()
        #expect(approved.sourceName == "Claude Code")
        #expect(firstRefresh.fetchedAt > approved.fetchedAt)
        #expect(secondRefresh.fetchedAt > firstRefresh.fetchedAt)
        #expect(attempts.count("interactive") == 1)
        #expect(UsageStub.requests.count("Bearer " + token) == 3)
    }

    @Test func expiredCachedCredentialsRequireApprovalInsteadOfPromptingInBackground() async throws {
        let clock = UsageClock()
        let token = UUID().uuidString
        let attempts = UsageRequests()
        let client = ClaudeUsageClient(hasCode: true, hasDesktop: false, session: session(),
            loadCode: { allow in
                attempts.record(allow ? "interactive" : "silent")
                guard allow else { throw ClaudeUsageError.keychainDenied }
                return .init(token: token, expiresAt: clock.date.addingTimeInterval(120), source: "Claude Code")
            }, now: { clock.date })
        _ = try await client.read(allowKeychainPrompt: true)
        clock.advance(121)
        do {
            _ = try await client.read()
            Issue.record("Expected denied access after expiry")
        } catch {
            #expect(error as? ClaudeUsageError == .keychainDenied)
        }
        #expect(attempts.count("interactive") == 1)
        #expect(UsageStub.requests.count("Bearer " + token) == 1)
    }

    @Test func cachedReadsKeepOriginalTimestampAndDoNotHitNetworkAgain() async throws {
        let token = UUID().uuidString
        let client = ClaudeUsageClient(hasCode: true, hasDesktop: false, session: session(),
            loadCode: { _ in .init(token: token, expiresAt: nil, source: "Claude Code") })
        let first = try await client.read()
        let second = try await client.read()
        #expect(first == second)
        #expect(first.windows.map(\.remainingPercent) == [75, 60])
        #expect(UsageStub.requests.count("Bearer " + token) == 1)
    }

    @Test func expiredCodeFallsBackToDesktopWithoutSendingExpiredToken() async throws {
        let expiredToken = UUID().uuidString
        let desktopToken = UUID().uuidString
        let client = ClaudeUsageClient(hasCode: true, hasDesktop: true, session: session(),
            loadCode: { _ in .init(token: expiredToken, expiresAt: .distantPast, source: "Claude Code") },
            loadDesktop: { _ in [.init(token: desktopToken, expiresAt: .distantFuture, source: "Claude Desktop")] })
        let snapshot = try await client.read()
        #expect(snapshot.sourceName == "Claude Desktop")
        #expect(UsageStub.requests.count("Bearer " + expiredToken) == 0)
        #expect(UsageStub.requests.count("Bearer " + desktopToken) == 1)
    }

    @Test func rejectedCodeLoginFallsBackToDesktop() async throws {
        let token = "unauthorized-" + UUID().uuidString
        let client = ClaudeUsageClient(hasCode: true, hasDesktop: true, session: session(),
            loadCode: { _ in .init(token: token, expiresAt: nil, source: "Claude Code") },
            loadDesktop: { _ in [.init(token: UUID().uuidString, expiresAt: nil, source: "Claude Desktop")] })
        #expect(try await client.read().sourceName == "Claude Desktop")
        #expect(UsageStub.requests.count("Bearer " + token) == 1)
    }

    @Test func rateLimitCooldownAlsoAppliesToRepeatedManualReads() async {
        let token = "limited-" + UUID().uuidString
        let client = ClaudeUsageClient(hasCode: true, hasDesktop: true, session: session(),
            loadCode: { _ in .init(token: token, expiresAt: nil, source: "Claude Code") },
            loadDesktop: { _ in throw ClaudeUsageError.notSignedIn })
        for _ in 0..<2 {
            do {
                _ = try await client.read(allowKeychainPrompt: true)
                Issue.record("Expected a rate-limit error")
            } catch {
                #expect(error as? ClaudeUsageError == .rateLimited)
            }
        }
        #expect(UsageStub.requests.count("Bearer " + token) == 1)
    }
}
