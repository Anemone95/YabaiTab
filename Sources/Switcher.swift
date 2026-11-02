import AppKit

enum Item {
    case window(YabaiWindow)
    /// A running app with no window: selecting it reopens the app, like clicking its Dock icon.
    case app(NSRunningApplication)

    var pid: pid_t {
        switch self {
        case .window(let w): return w.pid
        case .app(let a): return a.processIdentifier
        }
    }
    var wid: CGWindowID? {
        if case .window(let w) = self { return w.id }
        return nil
    }
    var title: String {
        switch self {
        case .window(let w): return w.title.isEmpty ? w.app : w.title
        case .app(let a): return a.localizedName ?? ""
        }
    }
}

/// The switcher session: hold ⌃, Tab / ⇧Tab to move, release ⌃ to focus the selection.
final class Switcher {
    static let showDelay = 0.1  // a quick ⌃Tab switches without flashing the panel
    private let history: FocusHistory
    private let thumbnails: Thumbnails
    private let panel: NSPanel
    private var cells = [Cell]()
    private var items = [Item]()
    private var selected = 0
    private var columns = 1
    private(set) var isActive = false
    private var session = 0
    private var loaded = false
    private var pendingSteps = 0
    private var commitWhenLoaded = false
    private var prefetched: (time: TimeInterval, windows: [YabaiWindow])?
    private var lastPrefetch: TimeInterval = 0

    init(history: FocusHistory, thumbnails: Thumbnails) {
        self.history = history
        self.thumbnails = thumbnails
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        thumbnails.onUpdate = { [weak self] wid, image in self?.cells.first { $0.wid == wid }?.setThumbnail(image) }
    }

    /// ⌃ went down: query yabai now, so the list is usually ready when Tab arrives.
    func prefetch() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPrefetch > 0.5 else { return }
        lastPrefetch = now
        DispatchQueue.global(qos: .userInteractive).async {
            let windows = Yabai.windows()
            DispatchQueue.main.async { self.prefetched = (now, windows) }
        }
    }

    func begin(backward: Bool) {
        isActive = true
        loaded = false
        commitWhenLoaded = false
        pendingSteps = backward ? -1 : 1
        session += 1
        let session = self.session
        let started = ProcessInfo.processInfo.systemUptime
        if let p = prefetched, started - p.time < 1 {
            prefetched = nil
            load(p.windows, session, started)
            return
        }
        DispatchQueue.global(qos: .userInteractive).async {
            let windows = Yabai.windows()
            DispatchQueue.main.async { self.load(windows, session, started) }
        }
    }

    func step(_ delta: Int) {
        guard isActive else { return }
        guard loaded else { pendingSteps += delta; return }
        select(wrap(selected + delta))
    }

    func stepRow(_ direction: Int) { step(direction * columns) }

    func commit() {
        guard isActive else { return }
        guard loaded else { commitWhenLoaded = true; return }
        let item = items[selected]
        hide()
        switch item {
        case .window(let w):
            history.touch(w.id)
            DispatchQueue.global(qos: .userInteractive).async { Yabai.focus(w) }
        case .app(let app):
            guard let url = app.bundleURL else { app.activate(); return }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func cancel() {
        guard isActive else { return }
        hide()
    }

    private func load(_ windows: [YabaiWindow], _ session: Int, _ started: TimeInterval) {
        guard isActive, session == self.session else { return }
        let sorted = history.sorted(windows)
        let pidsWithWindows = Set(sorted.map { $0.pid })
        let windowless = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !pidsWithWindows.contains($0.processIdentifier)
                && $0.bundleIdentifier != "com.apple.finder" && $0 != NSRunningApplication.current
        }
        items = sorted.map { Item.window($0) } + windowless.map { Item.app($0) }
        loaded = true
        guard !items.isEmpty else { cancel(); return }
        // The first item is the focused window, so the first Tab lands on the one before it. With no
        // focused window (desktop, windowless app) the first Tab lands on the most recent window.
        let base = sorted.first?.hasFocus == true || pendingSteps < 0 ? 0 : -1
        selected = wrap(base + pendingSteps)
        if commitWhenLoaded { commit(); return }
        let wait = max(0, Self.showDelay - (ProcessInfo.processInfo.systemUptime - started))
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self, self.isActive, session == self.session else { return }
            self.show()
            self.thumbnails.refresh(sorted)
        }
    }

    private func wrap(_ index: Int) -> Int {
        let n = items.count
        return n == 0 ? 0 : ((index % n) + n) % n
    }

    private func select(_ index: Int) {
        if cells.indices.contains(selected) { cells[selected].isSelected = false }
        selected = index
        if cells.indices.contains(selected) { cells[selected].isSelected = true }
    }

    private func hide() {
        isActive = false
        session += 1
        panel.orderOut(nil)
        cells = []
        items = []
    }

    private func show() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }
        let area = screen.visibleFrame
        let pad: CGFloat = 16, gap: CGFloat = 8
        // Largest thumbnails whose grid fits in 90% of the screen.
        var thumb = CGSize.zero, cell = CGSize.zero, rows = 1
        for scale in stride(from: 1.0, through: 0.3, by: -0.1) {
            thumb = CGSize(width: 220 * scale, height: 138 * scale)
            cell = Cell.size(thumb: thumb)
            columns = max(1, min(items.count, Int((area.width * 0.9 - 2 * pad + gap) / (cell.width + gap))))
            rows = (items.count + columns - 1) / columns
            if 2 * pad + CGFloat(rows) * (cell.height + gap) - gap <= area.height * 0.9 { break }
        }
        let size = CGSize(width: 2 * pad + CGFloat(columns) * (cell.width + gap) - gap,
                          height: 2 * pad + CGFloat(rows) * (cell.height + gap) - gap)
        let background = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true
        cells = items.enumerated().map { index, item in
            let c = Cell(item: item, thumb: thumb, image: item.wid.flatMap { thumbnails.image($0) })
            let row = index / columns, column = index % columns
            c.frame.origin = CGPoint(x: pad + CGFloat(column) * (cell.width + gap),
                                     y: size.height - pad - CGFloat(row + 1) * cell.height - CGFloat(row) * gap)
            c.onClick = { [weak self] in
                guard let self else { return }
                self.select(index)
                self.commit()
            }
            background.addSubview(c)
            return c
        }
        select(selected)
        panel.contentView = background
        panel.setFrame(CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                              width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
    }
}

final class Cell: NSView {
    static func size(thumb: CGSize) -> CGSize { CGSize(width: thumb.width + 16, height: thumb.height + 40) }

    let wid: CGWindowID?
    var onClick: (() -> Void)?
    var isSelected = false {
        didSet { layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.45).cgColor : nil }
    }
    private let thumbLayer = CALayer()

    init(item: Item, thumb: CGSize, image: CGImage?) {
        wid = item.wid
        super.init(frame: CGRect(origin: .zero, size: Cell.size(thumb: thumb)))
        wantsLayer = true
        layer?.cornerRadius = 10
        let icon = NSRunningApplication(processIdentifier: item.pid)?.icon
        thumbLayer.frame = CGRect(x: 8, y: 32, width: thumb.width, height: thumb.height)
        thumbLayer.contentsGravity = .resizeAspect
        thumbLayer.contents = image ?? icon  // the app icon stands in until a capture arrives
        layer?.addSublayer(thumbLayer)
        let iconView = NSImageView(frame: CGRect(x: 8, y: 8, width: 18, height: 18))
        iconView.image = icon
        addSubview(iconView)
        let label = NSTextField(labelWithString: item.title)
        label.frame = CGRect(x: 30, y: 8, width: thumb.width - 22, height: 18)
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
    }

    required init?(coder: NSCoder) { nil }

    func setThumbnail(_ image: CGImage) { thumbLayer.contents = image }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func rightMouseDown(with event: NSEvent) { onClick?() }  // ⌃-click arrives as a right click
}
