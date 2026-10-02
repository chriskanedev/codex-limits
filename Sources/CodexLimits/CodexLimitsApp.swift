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

                ForEach(controller.visibleProviders) { provider in
                    providerSection(provider)
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
                Text("Codex & Claude Limits")
                    .font(.headline)
                Text("Subscription limits")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ZStack {
                NativeGlassIconButton(
                    symbol: "arrow.clockwise",
                    title: "Refresh limits",
                    isEnabled: !controller.isRefreshing
                ) {
                    Task { await controller.refresh(allowClaudeKeychainPrompt: true) }
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

            if let error = controller.loginItemError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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

    private func providerSection(_ provider: UsageProvider) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(nsImage: ProviderLogo.image(for: provider))
                Text(provider.title).font(.subheadline.weight(.semibold))
                Spacer()
                if let snapshot = controller.snapshot(for: provider) {
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        Text(FreshnessText.format(snapshot.fetchedAt, now: context.date,
                                                 stale: controller.error(for: provider) != nil))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let snapshot = controller.snapshot(for: provider) {
                ForEach(snapshot.windows) { window in
                    UsageCard(window: window, provider: provider)
                }
                if let source = snapshot.sourceName {
                    Text("Connected via \(source)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if controller.error(for: provider) == nil {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading \(provider.title) limits…").font(.caption)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            if let error = controller.error(for: provider) {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct UsageCard: View {
    let window: UsageWindow
    let provider: UsageProvider

    var body: some View {
        NativeGlassCard(tint: provider.nsColor.withAlphaComponent(0.12)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Label("\(window.durationLabel) limit", systemImage: window.durationMinutes == 10_080 ? "calendar" : "clock")
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
                    .accessibilityLabel("Remaining limit")
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
