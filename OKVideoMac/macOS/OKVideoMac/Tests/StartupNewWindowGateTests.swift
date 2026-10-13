import AppKit
import XCTest
@testable import OKVideoMac

@MainActor final class StartupNewWindowGateTests: XCTestCase {
    func testRecoveryRejectsEvenForcedActionThenReadyUsesOriginalSceneFactory() {
        var ready = false
        let nativeTarget = NSObject()
        let originalAction = NSSelectorFromString("createScene:")
        var calls = 0
        let gate = StartupNewWindowGate(isReady: { ready }) { action, target, sender in
            XCTAssertEqual(action, originalAction)
            XCTAssertTrue(target === nativeTarget)
            XCTAssertTrue(sender is NSMenuItem)
            calls += 1
            return true
        }
        let menu = NSMenu()
        let item = NSMenuItem(title: "New Window", action: originalAction, keyEquivalent: "n")
        item.target = nativeTarget
        menu.addItem(item)
        gate.bind(in: menu)
        XCTAssertFalse(gate.validateMenuItem(item))
        item.isEnabled = true // An invocation cannot bypass recovery validation.
        gate.performNewWindow(item)
        XCTAssertEqual(calls, 0)
        ready = true
        gate.refresh()
        XCTAssertTrue(item.isEnabled)
        gate.bind(in: menu) // A menu refresh must not capture its own proxy.
        gate.performNewWindow(item)
        XCTAssertEqual(calls, 1)
        ready = false
        gate.performNewWindow(item)
        XCTAssertEqual(calls, 1)
    }
}
