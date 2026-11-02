# YabaiTab

A ⌃Tab window switcher for macOS, built on [yabai](https://github.com/asmvik/yabai).
Hold ⌃ and press Tab to step through the windows of every Space and display, shown as
thumbnails in most-recently-used order. Release ⌃ to focus the selected window.

## Features

- Windows from all Spaces and displays, most recently used first. A quick ⌃Tab goes back to
  the previous window without showing the panel.
- Thumbnails from ScreenCaptureKit, including windows on other Spaces.
- Minimized windows and windows of hidden apps are restored when you select them.
- Running apps without a window are listed last. Selecting one reopens the app, as a click
  on its Dock icon does.
- The panel opens on the display that has the mouse pointer.
- The window list comes from yabai's own state. The only request an app gets is the focus
  request for the window you select.

## Keys

| Key                      | Action                          |
| ------------------------ | ------------------------------- |
| ⌃Tab                     | Open the switcher, next window  |
| ⌃⇧Tab                    | Previous window                 |
| ← → ↑ ↓ (while open)     | Move through the grid           |
| Release ⌃, or Return     | Focus the selected window       |
| Esc                      | Close without switching         |

## Requirements

- macOS 26 on Apple silicon
- yabai running, installed at `/opt/homebrew/bin/yabai`
- Xcode Command Line Tools (`swiftc`, `codesign`)
- A code-signing certificate in your login keychain. `build.sh` signs with `yabai-cert`,
  the certificate that yabai's install guide creates. Set `SIGN_IDENTITY` to use another
  one. A stable identity keeps the macOS permission grants valid across rebuilds.

## Install

```sh
git clone git@github.com:Anemone95/YabaiTab.git
cd YabaiTab
./install.sh
```

`install.sh` builds the app, copies it to `/Applications/YabaiTab.app`, and loads the
LaunchAgent `~/Library/LaunchAgents/org.wenyuan.yabaitab.plist`. The agent starts YabaiTab
at login and restarts it after a crash. "Quit YabaiTab" in the menu bar icon stops it until
the next login.

On first start, give YabaiTab these permissions in System Settings › Privacy & Security:

- **Accessibility**, for the ⌃Tab keyboard shortcut
- **Screen & System Audio Recording**, for the thumbnails

Run `./install.sh` again after a change to update the installed app.

## How it works

| Part        | Source                                                                                         |
| ----------- | ---------------------------------------------------------------------------------------------- |
| Window list | `yabai -m query --windows id,pid,app,title,role,subrole,space,has-focus,is-visible,is-minimized,is-hidden,is-native-fullscreen`. yabai answers these fields from its own state. Standard windows (`AXWindow` / `AXStandardWindow`) that are on screen, minimized, or in a hidden app are listed. |
| Focus order | A yabai signal on `window_focused` posts the window id as the Darwin notification `org.wenyuan.yabaitab.focus`. YabaiTab adds the signal (label `yabaitab-focus`) at start, and again when yabai restarts. |
| Thumbnails  | `SCScreenshotManager.captureScreenshot` for each window id, at most 480×300 px, two captures at a time, most recently used window first. Each time the switcher opens, it shows the cached images at once and replaces them as new captures arrive. |
| Timing      | YabaiTab queries yabai when ⌃ goes down, so the list is usually ready when Tab arrives.       |
| Focus       | `yabai -m window --focus <id>`, after `--deminimize` or an app unhide when needed.             |
| Shortcut    | A `CGEvent` session tap that handles ⌃Tab and the keys used while the panel is open.           |

To check the thumbnails, write one PNG per window and a `report.txt` to a folder:

```sh
mkdir -p /tmp/yabaitab-capture
open -n /Applications/YabaiTab.app --args --capture-test /tmp/yabaitab-capture
```

## Uninstall

```sh
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/org.wenyuan.yabaitab.plist
rm ~/Library/LaunchAgents/org.wenyuan.yabaitab.plist
rm -rf /Applications/YabaiTab.app
yabai -m signal --remove yabaitab-focus
```

## Acknowledgements

The thumbnail-grid design follows [AltTab](https://github.com/lwouis/alt-tab-macos).
