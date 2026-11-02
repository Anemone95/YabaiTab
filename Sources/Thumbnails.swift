import ScreenCaptureKit

/// Window thumbnails captured by window id through ScreenCaptureKit. On macOS 26 `captureScreenshot` also
/// captures minimized and other-Space windows; its one known failure is a native-fullscreen window whose
/// Space is not visible, so those are skipped and keep their last image. The OS serves captures one at a
/// time, so two in flight is as fast as more.
final class Thumbnails {
    static let maxPixels = CGSize(width: 480, height: 300)
    var onUpdate: ((CGWindowID, CGImage) -> Void)?
    private var images = [CGWindowID: CGImage]()
    private var refreshing = false
    private let queue = DispatchQueue(label: "yabaitab.capture")

    func image(_ wid: CGWindowID) -> CGImage? { images[wid] }

    /// Main thread. Captures `windows` in order, so the caller passes the most relevant first.
    func refresh(_ windows: [YabaiWindow], completion: (() -> Void)? = nil) {
        guard !refreshing else { completion?(); return }
        refreshing = true
        let alive = Set(windows.map { $0.id })
        images = images.filter { alive.contains($0.key) }
        let wanted = windows.filter { !($0.isNativeFullscreen && !$0.isVisible) }.map { $0.id }
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { content, _ in
            let byId = Dictionary((content?.windows ?? []).map { ($0.windowID, $0) }, uniquingKeysWith: { a, _ in a })
            let targets = wanted.compactMap { byId[$0] }
            self.queue.async {
                let gate = DispatchSemaphore(value: 2)
                let group = DispatchGroup()
                for window in targets {
                    gate.wait()
                    group.enter()
                    Self.capture(window) { image in
                        gate.signal()
                        if let image {
                            DispatchQueue.main.async {
                                self.images[window.windowID] = image
                                self.onUpdate?(window.windowID, image)
                            }
                        }
                        group.leave()
                    }
                }
                group.notify(queue: .main) {
                    self.refreshing = false
                    completion?()
                }
            }
        }
    }

    private static func capture(_ window: SCWindow, _ done: @escaping (CGImage?) -> Void) {
        let size = window.frame.size
        let scale = min(maxPixels.width / max(size.width, 1), maxPixels.height / max(size.height, 1), 2)
        let config = SCScreenshotConfiguration()
        config.width = Int(size.width * scale)
        config.height = Int(size.height * scale)
        config.showsCursor = false
        config.dynamicRange = .sdr
        SCScreenshotManager.captureScreenshot(contentFilter: SCContentFilter(desktopIndependentWindow: window),
                                              configuration: config) { output, _ in done(output?.sdrImage) }
    }
}
