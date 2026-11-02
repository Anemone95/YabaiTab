import AppKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let history = FocusHistory()
    private let thumbnails = Thumbnails()
    private lazy var switcher = Switcher(history: history, thumbnails: thumbnails)
    private var tap: HotkeyTap?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--capture-test"), i + 1 < args.count {
            captureTest(outputDirectory: args[i + 1])
            return
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "YabaiTab")
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit YabaiTab", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
        history.start()
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        installTapWhenTrusted()
        DispatchQueue.global().async {
            let windows = Yabai.windows()
            DispatchQueue.main.async { self.thumbnails.refresh(windows) }
        }
    }

    /// The event tap can only be created once Accessibility is granted; wait for the grant without a relaunch.
    private func installTapWhenTrusted() {
        if AXIsProcessTrusted(), let tap = HotkeyTap(switcher: switcher) {
            self.tap = tap
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.installTapWhenTrusted() }
    }

    /// Verification mode: capture every yabai window once, write PNGs and a report, then quit.
    private func captureTest(outputDirectory: String) {
        let windows = Yabai.windows()
        let started = Date()
        thumbnails.refresh(windows) {
            var report = "screenRecording=\(CGPreflightScreenCaptureAccess()) windows=\(windows.count) "
                + "elapsed=\(String(format: "%.2f", Date().timeIntervalSince(started)))s\n"
            for w in windows {
                let state = "visible=\(w.isVisible) minimized=\(w.isMinimized) hidden=\(w.isHidden) fullscreen=\(w.isNativeFullscreen)"
                guard let image = self.thumbnails.image(w.id) else {
                    report += "MISSING \(w.id) \(state) \(w.app)\n"
                    continue
                }
                let url = URL(fileURLWithPath: outputDirectory).appendingPathComponent("\(w.id).png")
                if let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
                    CGImageDestinationAddImage(dest, image, nil)
                    CGImageDestinationFinalize(dest)
                }
                report += "ok \(w.id) \(image.width)x\(image.height) \(state) \(w.app)\n"
            }
            try? report.write(toFile: outputDirectory + "/report.txt", atomically: true, encoding: .utf8)
            exit(0)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
