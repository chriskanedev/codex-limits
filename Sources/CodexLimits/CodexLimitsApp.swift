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
        GlassEffectContainer(spacing: 8) {
            VStack(alignment: .leading, spacing: 12) {
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

                controls
            }
            .padding(16)
            .frame(width: 360)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .containerBackground(.clear, for: .window)
        .task { await controller.refresh() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title3.weight(.semibold))
                .frame(width: 38, height: 38)
                .background(.quaternary, in: .circle)

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
            Button {
                Task { await controller.refresh() }
            } label: {
                ZStack {
                    Image(systemName: "arrow.clockwise")
                        .opacity(controller.isRefreshing ? 0 : 1)
                    if controller.isRefreshing {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(width: 18, height: 18)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .disabled(controller.isRefreshing)
            .help("Refresh limits")
            .accessibilityLabel("Refresh limits")

            Button {
                controller.stop()
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .help("Quit Codex Limits")
            .accessibilityLabel("Quit Codex Limits")
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    controller.setLaunchAtLogin(!controller.launchAtLogin)
                } label: {
                    controlTile(
                        "Launch at Login",
                        subtitle: controller.launchAtLogin ? "On" : "Off",
                        symbol: controller.launchAtLogin ? "checkmark.circle.fill" : "circle"
                    )
                    .glassEffect(
                        controller.launchAtLogin ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
                        in: .rect(cornerRadius: 20)
                    )
                }
                .accessibilityValue(controller.launchAtLogin ? "On" : "Off")

                Button {
                    controller.openChatGPT()
                } label: {
                    controlTile("ChatGPT", subtitle: "Open app", symbol: "arrow.up.forward.app")
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
                }
            }
            .buttonStyle(.plain)

            if controller.loginItemStatus == .requiresApproval {
                Button("Approve in Login Items") {
                    controller.openLoginItemSettings()
                }
                .buttonStyle(.glass)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func controlTile(_ title: String, subtitle: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.title3.weight(.medium))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .foregroundStyle(.primary)
        .accessibilityElement(children: .combine)
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
                Label("\(window.durationLabel) allowance", systemImage: window.durationMinutes == 10_080 ? "calendar" : "clock")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(window.remainingPercent)%")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                    Text("remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            ProgressView(value: Double(window.remainingPercent), total: 100)
                .tint(window.remainingPercent <= 15 ? .red : .accentColor)
                .accessibilityLabel("Remaining allowance")
                .accessibilityValue("\(window.remainingPercent)%")

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
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 20))
    }
}
