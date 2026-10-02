import AppKit
import Foundation
import Security
import ServiceManagement

@MainActor
final class UsageController: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var loginItemError: String?
    @Published private(set) var loginItemStatus = SMAppService.mainApp.status

    @Published private(set) var claudeSnapshot: UsageSnapshot?
    @Published private(set) var claudeErrorMessage: String?
    @Published private(set) var claudeAvailable = false
    @Published private(set) var codexAvailable = true
    private var claudeClient: ClaudeUsageClient?

    var visibleProviders: [UsageProvider] {
        let providers = UsageProvider.allCases.filter { $0 == .codex ? codexAvailable : claudeAvailable }
        return providers.isEmpty ? [.codex] : providers
    }

    func snapshot(for provider: UsageProvider) -> UsageSnapshot? {
        provider == .codex ? snapshot : claudeSnapshot
    }

    func error(for provider: UsageProvider) -> String? {
        provider == .codex ? errorMessage : claudeErrorMessage
    }

    func menuBarText(for provider: UsageProvider) -> String {
        guard let snapshot = snapshot(for: provider) else {
            return error(for: provider) == nil ? "…" : "—"
        }
        let text = snapshot.windows.map { "\($0.durationLabel) \($0.remainingPercent)%" }.joined(separator: " · ")
        return text + (error(for: provider) == nil ? "" : " !")
    }

    private var client: (any RateLimitProviding)?
    private var pollTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?

    var menuBarText: String {
        visibleProviders.map { "\($0.title) \(menuBarText(for: $0))" }.joined(separator: "  |  ")
    }

    var launchAtLogin: Bool {
        loginItemStatus == .enabled || loginItemStatus == .requiresApproval
    }

    func start() async {
        configureLoginItemOnFirstLaunch()
        let hasDesktop = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") != nil
        let hasCode = Self.claudeCodeInstalled()
        claudeAvailable = hasDesktop || hasCode
        codexAvailable = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") != nil
        if claudeAvailable {
            claudeClient = ClaudeUsageClient(hasCode: hasCode, hasDesktop: hasDesktop)
        }
        if codexAvailable || !claudeAvailable {
            do {
                let executable = try Self.codexExecutableURL()
                let client = CodexAppServerClient(executableURL: executable)
                self.client = client
                updateTask = Task { [weak self] in
                    for await snapshot in client.updates {
                        guard !Task.isCancelled else { break }
                        self?.apply(snapshot)
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        await refresh()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { break }
                await self?.refresh()
            }
        }
    }

    func refresh(allowClaudeKeychainPrompt: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        // Each provider publishes as soon as its own read finishes.
        async let codex: Void = refreshCodex()
        async let claude: Void = refreshClaude(allowKeychainPrompt: allowClaudeKeychainPrompt)
        _ = await (codex, claude)
    }

    private func refreshCodex() async {
        guard let client else { return }
        do {
            apply(try await client.read())
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshClaude(allowKeychainPrompt: Bool) async {
        guard let claudeClient else { return }
        do {
            claudeSnapshot = try await claudeClient.read(allowKeychainPrompt: allowKeychainPrompt)
            claudeErrorMessage = nil
        } catch {
            claudeErrorMessage = error.localizedDescription
        }
    }

    nonisolated static func claudeCodeInstalled(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        searchPath: String = ProcessInfo.processInfo.environment["PATH"] ?? ""
    ) -> Bool {
        let paths = [home.appending(path: ".local/bin/claude").path,
                     home.appending(path: ".claude/local/claude").path,
                     "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            + searchPath.split(separator: ":").map { String($0) + "/claude" }
        return paths.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = "Could not update Launch at Login: \(error.localizedDescription)"
        }
        loginItemStatus = SMAppService.mainApp.status
    }

    func openLoginItemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func stop() {
        pollTask?.cancel()
        updateTask?.cancel()
        if let client {
            Task { await client.stop() }
        }
    }

    private func apply(_ snapshot: UsageSnapshot) {
        self.snapshot = snapshot
        errorMessage = nil
    }

    private func configureLoginItemOnFirstLaunch() {
        let key = "didConfigureLaunchAtLogin"
        guard !UserDefaults.standard.bool(forKey: key), Bundle.main.bundleURL.pathExtension == "app" else {
            loginItemStatus = SMAppService.mainApp.status
            return
        }
        UserDefaults.standard.set(true, forKey: key)
        setLaunchAtLogin(true)
    }

    static func codexExecutableURL() throws -> URL {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") else {
            throw UsageError.chatGPTNotInstalled
        }
        guard isOfficialChatGPTApp(appURL) else {
            throw UsageError.untrustedChatGPTApp
        }
        return try bundledCodexExecutableURL(in: appURL)
    }

    nonisolated static func bundledCodexExecutableURL(in appURL: URL) throws -> URL {
        let executable = appURL.appending(path: "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw UsageError.codexExecutableMissing
        }
        return executable
    }

    private static func isOfficialChatGPTApp(_ appURL: URL) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return false }

        let requirementText = #"anchor apple generic and identifier "com.openai.codex" and certificate leaf[subject.OU] = "2DC432GLL2""#
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }

        return SecStaticCodeCheckValidity(staticCode, [], requirement) == errSecSuccess
    }
}
