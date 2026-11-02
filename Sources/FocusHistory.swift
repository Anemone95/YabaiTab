import AppKit
import notify

/// Most-recently-focused order of window ids, fed by yabai's `window_focused` signal.
final class FocusHistory {
    static let notification = "org.wenyuan.yabaitab.focus"
    private(set) var order = [CGWindowID]()
    private var token: Int32 = 0

    func start() {
        notify_register_dispatch(Self.notification, &token, .main) { [weak self] token in
            var state: UInt64 = 0
            notify_get_state(token, &state)
            self?.touch(CGWindowID(truncatingIfNeeded: state))
        }
        DispatchQueue.global().async { Yabai.installFocusSignal(notification: Self.notification) }
    }

    func touch(_ wid: CGWindowID) {
        guard wid != 0 else { return }
        order.removeAll { $0 == wid }
        order.insert(wid, at: 0)
        if order.count > 500 { order.removeLast() }
    }

    /// Windows in most-recent-first order; windows never seen focused keep yabai's order after them.
    /// The focused window must already head the history while the signal is alive. When it does not
    /// (yabai restarted and its config cleared all signals), the signal is installed again.
    func sorted(_ windows: [YabaiWindow]) -> [YabaiWindow] {
        if let focused = windows.first(where: { $0.hasFocus }) {
            if order.first != focused.id {
                DispatchQueue.global().async { Yabai.installFocusSignal(notification: Self.notification) }
            }
            touch(focused.id)
        }
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return windows.enumerated().sorted { a, b in
            let ra = rank[a.element.id] ?? Int.max, rb = rank[b.element.id] ?? Int.max
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map { $0.element }
    }
}
