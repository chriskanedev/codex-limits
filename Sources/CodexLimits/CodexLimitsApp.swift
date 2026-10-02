import AppKit
import ServiceManagement
import SwiftUI

@main
struct CodexLimitsApp: App {
    @NSApplicationDelegateAdaptor(MenuBarController.self) private var delegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

struct UsagePopover: View {
    @ObservedObject var controller: UsageController
    var onSizeChange: (CGSize) -> Void = { _ in }
    var onDismiss: () -> Void = {}

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
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSizeChange($0) }
        .onExitCommand(perform: onDismiss)
        .task { await controller.refresh() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title3.weight(.semibold))
                .frame(width: 38, height: 38)
                .glassEffect(.clear, in: .circle)

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
            ZStack {
                NativeGlassIconButton(
                    symbol: "arrow.clockwise",
                    title: "Refresh limits",
                    isEnabled: !controller.isRefreshing
                ) {
                    Task { await controller.refresh() }
                }
                .opacity(controller.isRefreshing ? 0 : 1)
                if controller.isRefreshing {
                    ProgressView().controlSize(.small).allowsHitTesting(false)
                }
            }
            .frame(width: 36, height: 36)
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Button {
                controller.setLaunchAtLogin(!controller.launchAtLogin)
            } label: {
                controlPill(
                    "Launch at Login",
                    subtitle: controller.launchAtLogin ? "On" : "Off",
                    symbol: "power",
                    selected: controller.launchAtLogin
                )
            }
            .accessibilityValue(controller.launchAtLogin ? "On" : "Off")

            if controller.loginItemStatus == .requiresApproval {
                Button("Approve in Login Items") {
                    controller.openLoginItemSettings()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.glass(.clear))
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }

    private func controlPill(_ title: String, subtitle: String, symbol: String, selected: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3.weight(.medium))
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                .frame(width: 44, height: 44)
                .background(selected ? Color.white : Color.white.opacity(0.12), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
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
        NativeGlassCard {
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
        }
    }
}
