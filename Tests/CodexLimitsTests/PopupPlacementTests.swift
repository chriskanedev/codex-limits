import Foundation
import Testing
@testable import CodexLimits

struct PopupPlacementTests {
    @Test(arguments: [CGFloat(-1_400), CGFloat(-720), CGFloat(-10)])
    func popupStaysOnTheStatusItemsScreen(anchorX: CGFloat) {
        let screen = CGRect(x: -1_440, y: 25, width: 1_440, height: 875)
        let anchor = CGRect(x: anchorX, y: 900, width: 100, height: 25)
        let size = CGSize(width: 360, height: 450)
        let frame = PopupPlacement.frame(size: size, anchor: anchor, visibleFrame: screen)

        #expect(frame.size == size)
        #expect(frame.minX >= screen.minX + 8)
        #expect(frame.maxX <= screen.maxX - 8)
        #expect(frame.maxY == screen.maxY - 8)
    }

    @Test func loadingAndLoadedPanelsKeepTheirTopEdgeAnchored() {
        let screen = CGRect(x: 0, y: 25, width: 1_440, height: 875)
        let anchor = CGRect(x: 800, y: 900, width: 100, height: 25)
        let loading = PopupPlacement.frame(size: .init(width: 360, height: 240), anchor: anchor, visibleFrame: screen)
        let loaded = PopupPlacement.frame(size: .init(width: 360, height: 450), anchor: anchor, visibleFrame: screen)

        #expect(loading.maxY == loaded.maxY)
        #expect(loading.midX == anchor.midX)
        #expect(loaded.midX == anchor.midX)
    }
}
