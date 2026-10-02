import AppKit
import SwiftUI

struct NativeGlassIconButton: NSViewRepresentable {
    let symbol: String
    let title: String
    var isEnabled = true
    let action: @MainActor () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.setButtonType(.momentaryPushIn)
        button.bezelStyle = .glass
        button.borderShape = .circle
        button.controlSize = .large
        button.imagePosition = .imageOnly
        button.target = context.coordinator
        button.action = #selector(Coordinator.performAction)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .medium))
        button.isEnabled = isEnabled
        button.toolTip = title
        button.setAccessibilityLabel(title)
    }

    @MainActor final class Coordinator: NSObject {
        var action: @MainActor () -> Void
        init(action: @escaping @MainActor () -> Void) { self.action = action }
        @objc func performAction() { action() }
    }
}

// Keep each card as a separate native surface in the panel's AppKit glass
// container, with the system's regular material keeping usage text legible.
struct NativeGlassCard<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    func makeCoordinator() -> Coordinator { Coordinator(content: content) }

    func makeNSView(context: Context) -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = 20
        glass.contentView = context.coordinator.hosting.view
        return glass
    }

    func updateNSView(_ glass: NSGlassEffectView, context: Context) {
        context.coordinator.hosting.rootView = content
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSGlassEffectView, context: Context) -> CGSize? {
        context.coordinator.hosting.sizeThatFits(in: CGSize(
            width: proposal.width ?? 328,
            height: proposal.height ?? .greatestFiniteMagnitude
        ))
    }

    @MainActor final class Coordinator {
        let hosting: NSHostingController<Content>
        init(content: Content) { hosting = NSHostingController(rootView: content) }
    }
}
