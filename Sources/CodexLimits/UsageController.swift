import AppKit
import Foundation
import Security
import ServiceManagement

@MainActor
final class UsageController: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var loginItemStatus = SMAppService.mainApp.status

    private var client: (any RateLimitProviding)?
    private var pollTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?

    var menuBarText: String {
        guard let snapshot else { return errorMessage == nil ? "Codex …" : "Codex —" }
        return snapshot.windows
            .map { "\($0.durationLabel) \($0.remainingPercent)%" }
            .joined(separator: " · ")
    }

    var isStale: Bool {
        guard errorMessage != nil, snapshot != nil else { return false }
        return true
    }

    var launchAtLogin: Bool {
        loginItemStatus == .enabled || loginItemStatus == .requiresApproval
    }

    func start() async {
        configureLoginItemOnFirstLaunch()

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
            await refresh()
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(15))
                    guard !Task.isCancelled else { break }
                    await self?.refresh()
                }
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func refresh() async {
        guard !isRefreshing, let client else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            apply(try await client.read())
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
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
            errorMessage = nil
        } catch {
            errorMessage = "Could not update Launch at Login: \(error.localizedDescription)"
        }
        loginItemStatus = SMAppService.mainApp.status
    }

    func openChatGPT() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") else {
            errorMessage = UsageError.chatGPTNotInstalled.errorDescription
            return
        }
        NSWorkspace.shared.open(url)
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

    private static func codexExecutableURL() throws -> URL {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") else {
            throw UsageError.chatGPTNotInstalled
        }
        guard isOfficialChatGPTApp(appURL) else {
            throw UsageError.untrustedChatGPTApp
        }
        let executable = appURL.appending(path: "Contents/Resources/codex")
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
