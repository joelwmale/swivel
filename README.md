# Swivel

A window switcher for macOS that replaces the system `⌘Tab`. It lists windows instead of apps, in most-recently-used order, and lets you jump to an app by typing its letter.

Written in Swift with AppKit and SwiftUI. No dependencies.

## Features

- **Per-window switching.** `⌘Tab` lists every window, including minimized ones and windows on other Spaces.
- **Same-app cycling.** `` ⌘` `` cycles the windows of the frontmost app.
- **Key hints.** Each app gets a letter that never changes. Hold `⌘`, type the letter to select that app, type it again for its next window.
- **Tabs.** `→` expands a window's native tabs (Ghostty, Terminal, Finder, Safari) so you can switch straight to one.
- **Search.** `⌥Tab` opens a fuzzy search over app names, window titles and tab titles.
- **Preview on demand.** Hold `Space` on a row to see the window.
- **Multiple displays.** Show the switcher on the screen with the pointer, the screen with the focused window, the primary screen, or all of them. Optionally list only the windows on that display.
- **Readable titles.** The trailing app name is removed, and editor windows lead with the project name.
- **Exclusions.** Hide apps with no windows, and exclude individual apps.
- **Two themes.** A translucent system look and Aura Dark.

## Requirements

- macOS 14 or later
- Xcode 16 or later, or the matching Command Line Tools (`xcode-select --install`)

## Build

```sh
git clone https://github.com/joelwmale/swivel.git
cd swivel
Scripts/build-app.sh --install --run
```

This builds a release binary, wraps it in `Swivel.app`, signs it, copies it to `/Applications` and launches it. Without `--install` the app stays in `build/`.

### Signing

The script signs with the first `Apple Development` identity in your keychain and falls back to an ad-hoc signature. With an ad-hoc signature macOS forgets the permissions below every time you rebuild, so a real identity is worth having. A free Apple ID in Xcode (Settings > Accounts > Manage Certificates) is enough.

To choose an identity or bundle identifier:

```sh
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" BUNDLE_ID="com.example.swivel" Scripts/build-app.sh
```

### Tests

```sh
swift test
```

## Permissions

Swivel walks you through these on first launch.

| Permission | Needed for | Required |
| --- | --- | --- |
| Accessibility | Reading window titles, focusing windows, receiving `⌘Tab` | Yes |
| Screen Recording | Window previews | No |

The system `⌘Tab` is only turned off once Accessibility is granted. Relaunch Swivel after granting Screen Recording.

## Keys

| Keys | Action |
| --- | --- |
| `⌘Tab` | List all windows. Release `⌘` to switch |
| `` ⌘` `` | List windows of the current app |
| `⇧` | Reverse direction |
| `↑` `↓` | Move the selection |
| `⌘` + hint | Select an app. Repeat for its next window |
| `→` `←` | Show or hide the selected window's tabs |
| `Space` (hold) | Preview the selected window |
| `⌘⇧W` | Close window |
| `⌘⇧M` | Minimize window |
| `⌘⇧H` | Hide app |
| `⌘⇧Q` | Quit app |
| `⌥Tab` | Search. `Return` switches, `Esc` cancels |

Settings are in the menu bar icon.

## How it works

`SwivelCore` holds the logic that needs no system access: fuzzy matching, most-recently-used ordering, hint assignment and title cleaning. It is covered by unit tests.

`Swivel` is the app:

- `System/` wraps the event tap, Accessibility and the private WindowServer calls.
- `Windows/` keeps the list of windows and performs actions on them.
- `Switcher/` runs a switching session and draws the panel.
- `Settings/` stores preferences and draws the settings window.

### Private APIs

Public macOS APIs cannot turn off the system switcher, list windows on other Spaces, or focus one window of an app without raising the rest. Swivel uses undocumented SkyLight and Accessibility calls for these, all declared in `Sources/Swivel/System/PrivateAPIs.swift`. They can break in any macOS release, and they rule out the Mac App Store.

## Limitations

- While a password field has secure input on, macOS delivers no keys to Swivel. The system switcher takes over until you leave the field.
- If Swivel is force-killed, the system `⌘Tab` stays off until you relaunch Swivel or log out. A normal quit or a crash restores it.
- `` ⌘` `` is bound to the key above Tab on an ANSI keyboard.
- Tabs are listed for apps that use native macOS tabs. Chromium browsers, Firefox and VS Code draw their own and are not.

## Uninstall

Quit Swivel from its menu bar icon, then:

```sh
rm -rf /Applications/Swivel.app
defaults delete com.joelmale.swivel
```

## Acknowledgements

The techniques for reaching windows on other Spaces and focusing a single window were worked out by the [AltTab](https://github.com/lwouis/alt-tab-macos) and [yabai](https://github.com/koekeishiya/yabai) projects. The layout follows [Contexts](https://contexts.co), and typed hints were inspired by [Sxitch](https://github.com/MystikoLab/sxitch) and [rcmd](https://lowtechguys.com/rcmd/).

## License

[MIT](LICENSE)
