import AppKit

/// Global ⌃Tab through a session event tap. The tap needs Accessibility permission; the app uses it only
/// to read and swallow its own keys, never to query other apps.
final class HotkeyTap {
    private enum Key {
        static let tab: Int64 = 48, escape: Int64 = 53, enter: Int64 = 36
        static let left: Int64 = 123, right: Int64 = 124, down: Int64 = 125, up: Int64 = 126
    }

    private let switcher: Switcher
    private var tap: CFMachPort?

    init?(switcher: Switcher) {
        self.switcher = switcher
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue | 1 << CGEventType.keyUp.rawValue
            | 1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: { _, type, event, refcon in
            Unmanaged<HotkeyTap>.fromOpaque(refcon!).takeUnretainedValue().handle(type, event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return nil }
        self.tap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        let flags = event.flags
        let control = flags.contains(.maskControl)
        let otherModifiers = !flags.intersection([.maskCommand, .maskAlternate]).isEmpty
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        switch type {
        case .flagsChanged:
            if switcher.isActive, !control { switcher.commit() }
            else if control, !otherModifiers, !switcher.isActive { switcher.prefetch() }
            return pass
        case .keyDown:
            if key == Key.tab, control, !otherModifiers {
                let backward = flags.contains(.maskShift)
                if switcher.isActive { switcher.step(backward ? -1 : 1) } else { switcher.begin(backward: backward) }
                return nil
            }
            guard switcher.isActive else { return pass }
            switch key {
            case Key.escape: switcher.cancel()
            case Key.left: switcher.step(-1)
            case Key.right: switcher.step(1)
            case Key.up: switcher.stepRow(-1)
            case Key.down: switcher.stepRow(1)
            case Key.enter: switcher.commit()
            default: break
            }
            return nil  // while the switcher is open, keys belong to it
        case .keyUp:
            return switcher.isActive || (key == Key.tab && control) ? nil : pass
        default:
            return pass
        }
    }
}
