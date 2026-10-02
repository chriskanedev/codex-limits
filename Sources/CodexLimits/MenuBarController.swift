import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSApplicationDelegate {
    private let controller = UsageController()
    private var statusItem: NSStatusItem?
    private var panel: GlassPanel?
    private var subscription: AnyCancellable?
    private var outsideClickMonitor: Any?
    private var localEventMonitor: Any?
    private var applicationSwitchObserver: NSObjectProtocol?
    private var contentSize = CGSize(width: 360, height: 240)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "CodexLimits"
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        item.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        statusItem = item
        updateMenuBar()

        subscription = controller.objectWillChange.sink { [weak self] _ in
            // ObservableObject announces before the new value is assigned.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateMenuBar()
            }
        }

        let panel = GlassPanel(
            contentRect: CGRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Codex & Claude Limits"
        panel.isOpaque = false
        // Glass is composited separately from the window's pixels. A tiny
        // nonzero backing alpha keeps the entire popup in the mouse hit map.
        panel.backgroundColor = .black.withAlphaComponent(0.01)
        panel.ignoresMouseEvents = false
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        let content = UsagePopover(
            controller: controller,
            onSizeChange: { [weak self] size in self?.resizePanel(to: size) },
            onDismiss: { [weak self] in self?.hidePanel() }
        )
        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = .intrinsicContentSize
        let glass = NSGlassEffectView()
        glass.style = .clear
        glass.cornerRadius = 28
        glass.contentView = hosting
        let glassContainer = NSGlassEffectContainerView()
        glassContainer.spacing = 0
        glassContainer.contentView = glass
        panel.contentView = glassContainer
        self.panel = panel

        Task { await controller.start() }
    }

    private func updateMenuBar() {
        // Leave text colour unset so the status button uses native menu bar contrast.
        let title = NSMutableAttributedString()
        for (index, provider) in controller.visibleProviders.enumerated() {
            if index > 0 {
                title.append(NSAttributedString(string: "  |  "))
            }
            let attachment = NSTextAttachment()
            attachment.image = ProviderLogo.image(for: provider, size: 16)
            attachment.bounds = CGRect(x: 0, y: -3, width: 16, height: 16)
            title.append(NSAttributedString(attachment: attachment))
            title.append(NSAttributedString(string: " " + controller.menuBarText(for: provider), attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium),
            ]))
        }
        statusItem?.button?.attributedTitle = title
        statusItem?.button?.setAccessibilityLabel("Remaining limits: \(controller.menuBarText)")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        hidePanel()
        controller.stop()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }

    @objc private func togglePanel() {
        if panel?.isVisible == true {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let panel else { return }
        positionPanel()
        statusItem?.button?.highlight(true)
        panel.makeKeyAndOrderFront(nil)
        // A nonactivating panel can change key focus during an internal click.
        // Dismiss from the actual input, not windowDidResignKey.
        if outsideClickMonitor == nil {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.dismissForOutsideClick(at: NSEvent.mouseLocation)
                }
            }
        }
        if localEventMonitor == nil {
            localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
                let consumed = MainActor.assumeIsolated {
                    guard let self else { return false }
                    if event.type == .keyDown {
                        if event.keyCode == 53 {
                            self.hidePanel()
                            return true
                        }
                    } else if event.window !== self.panel {
                        self.dismissForOutsideClick(at: NSEvent.mouseLocation)
                    }
                    return false
                }
                return consumed ? nil : event
            }
        }
        if applicationSwitchObserver == nil {
            applicationSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] notification in
                guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
                MainActor.assumeIsolated {
                    self?.hidePanel()
                }
            }
        }
        Task { await controller.refresh() }
    }

    private func hidePanel() {
        panel?.orderOut(nil)
        statusItem?.button?.highlight(false)
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let applicationSwitchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(applicationSwitchObserver)
            self.applicationSwitchObserver = nil
        }
    }

    private func dismissForOutsideClick(at point: CGPoint) {
        guard let panel, panel.isVisible,
              PopupDismissal.shouldDismissClick(at: point, popupFrame: panel.frame, statusItemFrame: statusItemFrame) else { return }
        hidePanel()
    }

    private var statusItemFrame: CGRect? {
        guard let button = statusItem?.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func resizePanel(to size: CGSize) {
        guard size.width > 0, size.height > 0, size != contentSize else { return }
        contentSize = size
        positionPanel()
    }

    private func positionPanel() {
        guard let panel, let button = statusItem?.button, let buttonWindow = button.window,
              let screen = buttonWindow.screen else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        panel.setFrame(
            PopupPlacement.frame(size: contentSize, anchor: anchor, visibleFrame: screen.visibleFrame),
            display: panel.isVisible
        )
    }
}

private final class GlassPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

enum PopupPlacement {
    static func frame(size: CGSize, anchor: CGRect, visibleFrame: CGRect) -> CGRect {
        let margin: CGFloat = 8
        let x = min(max(anchor.midX - size.width / 2, visibleFrame.minX + margin), visibleFrame.maxX - size.width - margin)
        let y = max(visibleFrame.minY + margin, min(anchor.minY - size.height - margin, visibleFrame.maxY - size.height - margin))
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}

enum PopupDismissal {
    static func shouldDismissClick(at point: CGPoint, popupFrame: CGRect, statusItemFrame: CGRect?) -> Bool {
        // The status item handles its own toggle on mouse-up. Closing on its
        // mouse-down would make that same click reopen the popup.
        !popupFrame.contains(point) && !(statusItemFrame?.contains(point) ?? false)
    }
}
