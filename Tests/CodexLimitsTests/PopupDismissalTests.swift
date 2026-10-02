import Foundation
import Testing
@testable import CodexLimits

struct PopupDismissalTests {
    private let popup = CGRect(x: -500, y: 300, width: 360, height: 505)
    private let statusItem = CGRect(x: -400, y: 813, width: 160, height: 25)

    @Test(arguments: [
        CGPoint(x: -220, y: 770), // Refresh button
        CGPoint(x: -320, y: 680), // Allowance card
        CGPoint(x: -320, y: 370), // Action pill
        CGPoint(x: -499, y: 301), // Background padding
    ])
    func internalClicksKeepPopupOpen(point: CGPoint) {
        #expect(!PopupDismissal.shouldDismissClick(at: point, popupFrame: popup, statusItemFrame: statusItem))
    }

    @Test(arguments: [CGPoint(x: -501, y: 600), CGPoint(x: -139, y: 600), CGPoint(x: -320, y: 299), CGPoint(x: 200, y: 600)])
    func outsideClicksDismissPopup(point: CGPoint) {
        #expect(PopupDismissal.shouldDismissClick(at: point, popupFrame: popup, statusItemFrame: statusItem))
    }

    @Test func statusItemClickIsLeftToItsToggleAction() {
        #expect(!PopupDismissal.shouldDismissClick(at: .init(x: -320, y: 825), popupFrame: popup, statusItemFrame: statusItem))
    }

    @Test func outsideClickStillDismissesWithoutStatusItem() {
        #expect(PopupDismissal.shouldDismissClick(at: .init(x: 200, y: 600), popupFrame: popup, statusItemFrame: nil))
    }
}
