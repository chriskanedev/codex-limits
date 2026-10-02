import AppKit
import CommonCrypto
import CryptoKit
import Foundation
import LocalAuthentication
import Security

struct ClaudeUsagePayload: Decodable, Sendable {
    struct Window: Decodable, Sendable {
        let utilization: Double?
        let resets_at: String?
    }
    let five_hour: Window?
    let seven_day: Window?

    func snapshot(source: String, at date: Date = .now) throws -> UsageSnapshot {
        let windows = try [("five_hour", 300, five_hour), ("seven_day", 10_080, seven_day)]
            .compactMap { id, duration, payload -> UsageWindow? in
                guard let payload, let used = payload.utilization else { return nil }
                guard used.isFinite else { throw ClaudeUsageError.invalidResponse }
                let reset: Date?
                if let value = payload.resets_at {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    reset = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
                    guard reset != nil else { throw ClaudeUsageError.invalidResponse }
                } else {
                    reset = nil
                }
                return UsageWindow(id: id, usedPercent: Int(min(100, max(0, used)).rounded()),
                                   durationMinutes: duration, resetsAt: reset)
            }
        guard !windows.isEmpty else { throw ClaudeUsageError.noSubscriptionLimits }
        return UsageSnapshot(planType: nil, windows: windows, fetchedAt: date, sourceName: source)
    }
}

enum ClaudeUsageError: LocalizedError, Equatable {
    case notSignedIn, expired, keychainDenied, invalidResponse, noSubscriptionLimits
    case rateLimited, http(Int)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "Open Claude Desktop or run claude, sign in with your Claude subscription, then refresh."
        case .expired: "Claude’s login has expired. Open Claude Desktop or Claude Code to renew it, then refresh."
        case .keychainDenied: "Claude needs Keychain access. Click Refresh to approve it once; background checks stay silent."
        case .invalidResponse: "Claude returned an unsupported usage response."
        case .noSubscriptionLimits: "This Claude account does not expose subscription limits. API billing has no 5h or 7d limit."
        case .rateLimited: "Claude is limiting usage checks. Retrying automatically after a short pause."
        case .http(let status): "Claude usage could not be read (HTTP \(status))."
        }
    }
}

struct ClaudeCredential: Sendable {
    let token: String
    let expiresAt: Date?
    let source: String
}

// Read only the two apps' OAuth stores. Claude owns login and token renewal;
// never rotate refresh tokens, overwrite its stores, or inspect cookie databases.
enum ClaudeCredentials {
    static var configDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude")
    }

    static func codeCredential(allowKeychainPrompt: Bool = false) throws -> ClaudeCredential {
        var service = "Claude Code-credentials"
        if ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] != nil {
            let digest = SHA256.hash(data: Data(configDirectory.path.utf8))
                .map { String(format: "%02x", $0) }.joined()
            service += "-" + digest.prefix(8)
        }
        let data: Data
        do {
            data = try keychainData(service: service, allowPrompt: allowKeychainPrompt)
        } catch {
            let file = configDirectory.appending(path: ".credentials.json")
            guard let fallback = try? Data(contentsOf: file) else { throw error }
            data = fallback
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let oauth = json?["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else {
            throw ClaudeUsageError.notSignedIn
        }
        return ClaudeCredential(token: token, expiresAt: expiry(oauth["expiresAt"]), source: "Claude Code")
    }

    static func desktopCredentials(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                   allowKeychainPrompt: Bool = false) throws -> [ClaudeCredential] {
        let file = home.appending(path: "Library/Application Support/Claude/config.json")
        guard let data = try? Data(contentsOf: file),
              let config = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeUsageError.notSignedIn
        }
        let password = try keychainData(service: "Claude Safe Storage", allowPrompt: allowKeychainPrompt)
        var credentials: [ClaudeCredential] = []
        for name in ["oauth:tokenCacheV2", "oauth:tokenCache"] {
            guard let encoded = config[name] as? String, let encrypted = Data(base64Encoded: encoded) else { continue }
            let decrypted = try decryptDesktopCache(encrypted, password: password)
            let cache = try JSONSerialization.jsonObject(with: decrypted) as? [String: Any] ?? [:]
            credentials += desktopCredentials(in: cache, account: config["lastKnownAccountUuid"] as? String)
        }
        guard !credentials.isEmpty else { throw ClaudeUsageError.notSignedIn }
        return credentials.sorted { ($0.expiresAt ?? .distantPast) > ($1.expiresAt ?? .distantPast) }
    }

    static func desktopCredentials(in cache: [String: Any], account: String?) -> [ClaudeCredential] {
        // Account-tagged entries must belong to the desktop's current account.
        // Ignore third-party/custom endpoints and config-only OAuth scopes.
        cache.compactMap { key, value in
            if key.hasPrefix("acct:") {
                guard let account, key.hasPrefix("acct:\(account)|") else { return nil }
            } else if cache.keys.contains(where: { $0.hasPrefix("acct:") }) {
                return nil
            }
            guard key.contains(":https://api.anthropic.com:"), key.contains("user:inference"),
                  let entry = value as? [String: Any], let token = entry["token"] as? String,
                  !token.isEmpty else { return nil }
            return ClaudeCredential(token: token, expiresAt: expiry(entry["expiresAt"]), source: "Claude Desktop")
        }
    }

    static func decryptDesktopCache(_ encrypted: Data, password: Data) throws -> Data {
        guard encrypted.starts(with: Data("v10".utf8)), encrypted.count > 3 else {
            throw ClaudeUsageError.invalidResponse
        }
        var key = [UInt8](repeating: 0, count: kCCKeySizeAES128)
        let salt = Array("saltysalt".utf8)
        let deriveStatus = password.withUnsafeBytes { bytes in
            salt.withUnsafeBufferPointer { saltBuffer in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                    bytes.baseAddress?.assumingMemoryBound(to: Int8.self), password.count,
                    saltBuffer.baseAddress, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                    1003, &key, key.count)
            }
        }
        guard deriveStatus == kCCSuccess else { throw ClaudeUsageError.invalidResponse }
        let ciphertext = Data(encrypted.dropFirst(3))
        var plaintext = [UInt8](repeating: 0, count: ciphertext.count + kCCBlockSizeAES128)
        var written = 0
        let iv = [UInt8](repeating: 32, count: kCCBlockSizeAES128)
        let status = ciphertext.withUnsafeBytes { bytes in
            CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                    key, key.count, iv, bytes.baseAddress, ciphertext.count,
                    &plaintext, plaintext.count, &written)
        }
        guard status == kCCSuccess else { throw ClaudeUsageError.invalidResponse }
        return Data(plaintext.prefix(written))
    }

    private static func expiry(_ value: Any?) -> Date? {
        (value as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
    }

    private static func keychainData(service: String, allowPrompt: Bool) throws -> Data {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(keychainQuery(service: service, allowPrompt: allowPrompt), &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw status == errSecItemNotFound ? ClaudeUsageError.notSignedIn : ClaudeUsageError.keychainDenied
        }
        return data
    }

    static func keychainQuery(service: String, allowPrompt: Bool) -> CFDictionary {
        let context = LAContext()
        context.interactionNotAllowed = !allowPrompt
        return [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecUseAuthenticationContext: context,
        ] as CFDictionary
    }
}

actor ClaudeUsageClient {
    private let hasCode: Bool
    private let hasDesktop: Bool
    private let session: URLSession
    private let loadCode: @Sendable (Bool) throws -> ClaudeCredential
    private let loadDesktop: @Sendable (Bool) throws -> [ClaudeCredential]
    private let now: @Sendable () -> Date
    private var cachedCredentials: [String: [ClaudeCredential]] = [:]
    private var nextReadAt = Date.distantPast
    private var lastResult: Result<UsageSnapshot, Error>?

    init(hasCode: Bool, hasDesktop: Bool, session: URLSession? = nil,
         loadCode: @escaping @Sendable (Bool) throws -> ClaudeCredential = { try ClaudeCredentials.codeCredential(allowKeychainPrompt: $0) },
         loadDesktop: @escaping @Sendable (Bool) throws -> [ClaudeCredential] = { try ClaudeCredentials.desktopCredentials(allowKeychainPrompt: $0) },
         now: @escaping @Sendable () -> Date = { .now }) {
        self.hasCode = hasCode
        self.hasDesktop = hasDesktop
        self.loadCode = loadCode
        self.loadDesktop = loadDesktop
        self.now = now
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        self.session = session ?? URLSession(configuration: configuration, delegate: NoUsageRedirects(), delegateQueue: nil)
    }

    func read(allowKeychainPrompt: Bool = false) async throws -> UsageSnapshot {
        // An explicit approval retry can bypass a cached Keychain denial, but
        // never bypass the usage endpoint's network/rate-limit cooldown.
        let needsApproval: Bool
        if case .failure(let error) = lastResult {
            needsApproval = (error as? ClaudeUsageError) == .keychainDenied
        } else {
            needsApproval = false
        }
        if now() < nextReadAt, let lastResult, !(allowKeychainPrompt && needsApproval) {
            return try lastResult.get()
        }
        nextReadAt = now().addingTimeInterval(60)
        do {
            let snapshot = try await readAvailableCredential(allowKeychainPrompt: allowKeychainPrompt)
            lastResult = .success(snapshot)
            return snapshot
        } catch {
            lastResult = .failure(error)
            throw error
        }
    }

    private func readAvailableCredential(allowKeychainPrompt: Bool) async throws -> UsageSnapshot {
        var failure: Error = ClaudeUsageError.notSignedIn
        var seenTokens = Set<String>()
        func remember(_ error: Error) {
            let incoming = error as? ClaudeUsageError
            let previous = failure as? ClaudeUsageError
            if incoming == .keychainDenied || (previous != .keychainDenied &&
                !(previous == .expired && incoming == .notSignedIn)) {
                failure = error
            }
        }
        // Load lazily: a working CLI credential does not require Desktop Keychain access.
        for source in [hasCode ? "code" : nil, hasDesktop ? "desktop" : nil].compactMap({ $0 }) {
            let credentials: [ClaudeCredential]
            do {
                credentials = try self.credentials(for: source, allowKeychainPrompt: allowKeychainPrompt)
            } catch {
                remember(error)
                continue
            }
            for credential in credentials where seenTokens.insert(credential.token).inserted {
                if let expiry = credential.expiresAt, expiry <= now() {
                    remember(ClaudeUsageError.expired)
                    continue
                }
                do {
                    return try await fetch(credential)
                } catch {
                    remember(error)
                    if (error as? ClaudeUsageError) == .expired { cachedCredentials[source] = nil }
                    if (error as? ClaudeUsageError) == .rateLimited { throw error }
                }
            }
        }
        throw failure
    }

    private func credentials(for source: String, allowKeychainPrompt: Bool) throws -> [ClaudeCredential] {
        let load: (Bool) throws -> [ClaudeCredential] = { allow in
            try source == "code" ? [self.loadCode(allow)] : self.loadDesktop(allow)
        }
        do {
            // Silent rereads pick up Claude's renewals and account changes when
            // persistent access exists. A one-time Allow is sufficient to reuse
            // the credential in memory until it expires.
            let credentials = try load(false)
            cachedCredentials[source] = credentials
            return credentials
        } catch {
            guard (error as? ClaudeUsageError) == .keychainDenied else {
                cachedCredentials[source] = nil
                throw error
            }
            let usable = cachedCredentials[source, default: []].filter {
                $0.expiresAt.map { $0 > now() } ?? true
            }
            cachedCredentials[source] = usable
            if !usable.isEmpty { return usable }
            guard allowKeychainPrompt else { throw error }
            let credentials = try load(true)
            cachedCredentials[source] = credentials
            return credentials
        }
    }

    private func fetch(_ credential: ClaudeCredential) async throws -> UsageSnapshot {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.4"
        request.setValue("codex-claude-limits/\(version)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ClaudeUsageError.invalidResponse }
        switch response.statusCode {
        case 200: break
        case 401, 403: throw ClaudeUsageError.expired
        case 429:
            let retry = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) ?? 300
            nextReadAt = now().addingTimeInterval(max(60, retry))
            throw ClaudeUsageError.rateLimited
        default: throw ClaudeUsageError.http(response.statusCode)
        }
        guard let payload = try? JSONDecoder().decode(ClaudeUsagePayload.self, from: data) else {
            throw ClaudeUsageError.invalidResponse
        }
        return try payload.snapshot(source: credential.source, at: now())
    }
}

private final class NoUsageRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
