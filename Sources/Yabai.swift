import AppKit

/// One window as `yabai -m query --windows` reports it. Only the fields the switcher uses.
struct YabaiWindow: Decodable {
    let id: CGWindowID
    let pid: pid_t
    let app: String
    let title: String
    let role: String
    let subrole: String
    let space: Int
    let hasFocus: Bool
    let isMinimized: Bool
    let isHidden: Bool
    let isNativeFullscreen: Bool
    let isVisible: Bool

    enum CodingKeys: String, CodingKey {
        case id, pid, app, title, role, subrole, space
        case hasFocus = "has-focus", isMinimized = "is-minimized", isHidden = "is-hidden"
        case isNativeFullscreen = "is-native-fullscreen", isVisible = "is-visible"
    }
}

private struct YabaiSpace: Decodable {
    let index: Int
    let isVisible: Bool
    enum CodingKeys: String, CodingKey { case index, isVisible = "is-visible" }
}

/// yabai is the only window source: the switcher never sends accessibility requests to other apps.
enum Yabai {
    static let path = "/opt/homebrew/bin/yabai"
    /// yabai serves these from its own state and the WindowServer. Fields such as `can-move`, `can-resize`
    /// and `frame` would make yabai read every window through accessibility on each query.
    private static let windowFields = "id,pid,app,title,role,subrole,space,has-focus,is-visible,is-minimized,is-hidden,is-native-fullscreen"

    @discardableResult
    static func run(_ args: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }

    /// Standard windows on every Space and display, in yabai's order. A window that is not visible
    /// although its Space is, and that is neither minimized nor in a hidden app, is ordered out: an app
    /// keeps it for later (IguanaTex keeps its closed forms this way), so it is not listed.
    static func windows() -> [YabaiWindow] {
        guard let data = run(["-m", "query", "--windows", windowFields]),
              let all = try? JSONDecoder().decode([YabaiWindow].self, from: data) else { return [] }
        let visibleSpaces = Set((run(["-m", "query", "--spaces", "index,is-visible"])
            .flatMap { try? JSONDecoder().decode([YabaiSpace].self, from: $0) } ?? [])
            .filter { $0.isVisible }.map { $0.index })
        return all.filter { w in
            let orderedOut = !w.isVisible && !w.isMinimized && !w.isHidden && (w.space == 0 || visibleSpaces.contains(w.space))
            return w.role == "AXWindow" && w.subrole == "AXStandardWindow" && !orderedOut
        }
    }

    static func focus(_ window: YabaiWindow) {
        if window.isHidden { NSRunningApplication(processIdentifier: window.pid)?.unhide() }
        if window.isMinimized { run(["-m", "window", "\(window.id)", "--deminimize"]) }
        run(["-m", "window", "--focus", "\(window.id)"])
    }

    /// yabai posts every focus change as a Darwin notification whose state is the focused window id.
    /// Adding by label replaces an existing signal with that label, so calling this again is safe.
    static func installFocusSignal(notification: String) {
        run(["-m", "signal", "--add", "event=window_focused", "label=yabaitab-focus",
             "action=/usr/bin/notifyutil -s \(notification) $YABAI_WINDOW_ID -p \(notification)"])
    }
}
