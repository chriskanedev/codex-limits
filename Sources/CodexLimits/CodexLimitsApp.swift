import AppKit
import ServiceManagement
import SwiftUI

@main
struct CodexLimitsApp: App {
    @StateObject private var controller: UsageController

    init() {
        let controller = UsageController()
        _controller = StateObject(wrappedValue: controller)
        Task { await controller.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            UsagePopover(controller: controller)
        } label: {
            Text(controller.menuBarText)
                .monospacedDigit()
                .accessibilityLabel("Codex remaining limits: \(controller.menuBarText)")
        }
        .menuBarExtraStyle(.window)
    }
}

private struct UsagePopover: View {
    @ObservedObject var controller: UsageController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let snapshot = controller.snapshot {
                ForEach(snapshot.windows) { window in
                    UsageCard(window: window)
                }
            } else if let error = controller.errorMessage {
                ContentUnavailableView(
                    "Usage unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, minHeight: 130)
            } else {
                HStack {
                    Spacer()
                    ProgressView("Loading limits…")
                    Spacer()
                }
                .frame(minHeight: 130)
            }

            if let error = controller.errorMessage, controller.snapshot != nil {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            controls
        }
        .padding(16)
        .frame(width: 350)
        .task { await controller.refresh() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Codex Limits")
                    .font(.headline)
                if let snapshot = controller.snapshot {
                    Text(statusText(snapshot))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if controller.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Toggle(
                "Launch at Login",
                isOn: Binding(
                    get: { controller.launchAtLogin },
                    set: { controller.setLaunchAtLogin($0) }
                )
            )

            if controller.loginItemStatus == .requiresApproval {
                Button("Approve in Login Items") {
                    controller.openLoginItemSettings()
                }
                .buttonStyle(.link)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button {
                    Task { await controller.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(controller.isRefreshing)

                Button("Open ChatGPT") {
                    controller.openChatGPT()
                }

                Spacer()

                Button("Quit") {
                    controller.stop()
                    NSApplication.shared.terminate(nil)
                }
            }
            .buttonStyle(.glass)
        }
    }

    private func statusText(_ snapshot: UsageSnapshot) -> String {
        FreshnessText.format(snapshot.fetchedAt, stale: controller.isStale)
    }
}

private struct UsageCard: View {
    let window: UsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.durationLabel)
                    .font(.headline)
                Spacer()
                Text("\(window.remainingPercent)% remaining")
                    .font(.headline)
                    .monospacedDigit()
            }

            ProgressView(value: Double(window.remainingPercent), total: 100)
                .tint(window.remainingPercent <= 15 ? .red : .accentColor)

            if let resetsAt = window.resetsAt {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ResetText.relative(to: resetsAt, now: context.date))
                            .font(.subheadline)
                        Text(ResetText.absolute(resetsAt, now: context.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Reset time unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}
