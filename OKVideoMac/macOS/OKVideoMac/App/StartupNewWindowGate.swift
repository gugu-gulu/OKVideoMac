import AppKit
import Combine

/// Preserve WindowGroup's native factory, including reopening after every
/// window closes. Recovery only gates execution; it must not substitute the
/// current window's tab action for the scene factory.
@MainActor
final class StartupNewWindowGate: NSObject, NSMenuItemValidation {
    private final class Binding {
        weak var item: NSMenuItem?
        let action: Selector
        let target: AnyObject?
        init(item: NSMenuItem, action: Selector) {
            self.item = item; self.action = action; target = item.target
        }
    }
    private var bindings: [ObjectIdentifier: Binding] = [:]
    private var observers: [NSObjectProtocol] = []
    private var phaseSubscription: AnyCancellable?
    private let isReady: @MainActor () -> Bool
    private let dispatch: @MainActor (Selector, AnyObject?, Any?) -> Bool

    init(isReady: @escaping @MainActor () -> Bool = {
        AppLaunchSession.current?.controller?.canRunBusinessEvents == true
    }, dispatch: @escaping @MainActor (Selector, AnyObject?, Any?) -> Bool = {
        NSApp.sendAction($0, to: $1, from: $2)
    }) {
        self.isReady = isReady; self.dispatch = dispatch
        super.init()
    }

    func start() {
        guard observers.isEmpty else { return }
        for name in [NSMenu.didAddItemNotification, NSMenu.didChangeItemNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name,
                object: nil, queue: .main) { [weak self] notification in
                    guard let menu = notification.object as? NSMenu else { return }
                    MainActor.assumeIsolated {
                        var root = menu
                        while let parent = root.supermenu { root = parent }
                        guard root === NSApp.mainMenu else { return }
                        self?.bind(in: menu)
                    }
                })
        }
        phaseSubscription = AppLaunchSession.current?.controller?.$phase.sink { [weak self] _ in
            // @Published emits before storage changes; refresh on the next turn.
            DispatchQueue.main.async { self?.refresh() }
        }
        if let menu = NSApp.mainMenu { bind(in: menu) }
    }

    func bind(in menu: NSMenu) {
        for item in menu.items {
            if let submenu = item.submenu { bind(in: submenu) }
            guard item.keyEquivalent == "n", item.keyEquivalentModifierMask == .command,
                  let action = item.action else { continue }
            let identifier = ObjectIdentifier(item)
            if item.target === self { continue }
            bindings[identifier] = Binding(item: item, action: action)
            item.target = self
            item.action = #selector(performNewWindow(_:))
            item.isEnabled = isReady()
        }
    }

    func refresh() {
        bindings = bindings.filter { $0.value.item != nil }
        for binding in bindings.values { binding.item?.isEnabled = isReady() }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { isReady() }

    @objc func performNewWindow(_ sender: NSMenuItem) {
        guard isReady(), let binding = bindings[ObjectIdentifier(sender)] else { return }
        _ = dispatch(binding.action, binding.target, sender)
    }

    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
}
