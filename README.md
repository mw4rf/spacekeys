<p align="center"><img src="Resources/AppIcon.png" width="128" alt="SpaceKeys icon"></p>

# SpaceKeys

A small menu bar utility for controlling **native macOS Spaces** with the keyboard,
while keeping **SIP enabled**. It complements a window manager such as Amethyst.

## Keyboard shortcuts

| Keys | Action |
| --- | --- |
| **⌘1…9, ⌘0** | Switch to desktop 1…10 on the display under the pointer |
| **⌘⇧1…9, ⌘⇧0** | Send the focused window to desktop 1…10 on its display, without following it |

On AZERTY keyboards, use the **physical positions of the number row**: `⌘&`, `⌘é`, etc.
Shift sends the window; it is not needed to type a number.
These combinations take precedence over application shortcuts using the same keys.

## Building

Requirements: **macOS 27** and Apple's Command Line Tools with Swift and Clang
(`xcode-select --install` if needed). The current version has been checked on Apple Silicon.

```sh
./build.sh
```

The script generates the macOS icon from the included PNG, compiles the application,
runs the tests, then signs and verifies `build/SpaceKeys.app`.
The entire build runs offline, with no package manager or dependencies to download.

To install in your personal Applications folder, quit SpaceKeys first, then run:

```sh
./build.sh --install
open ~/Applications/SpaceKeys.app
```

The app uses local ad hoc signing by default. Rebuilding may require renewing its
macOS authorization. If you already have an Apple signing identity,
you can supply it through the `CODESIGN_IDENTITY` environment variable.
The script does not create certificates or change system security protections.

## Getting started

1. Authorize SpaceKeys in System Settings → Privacy & Security →
   **Device Control & Data Access** (formerly Accessibility).
2. In the SpaceKeys window, choose **Enable shortcuts** (`Activer les raccourcis` in the current French interface).
3. Keep Trackpad → More Gestures →
   **Swipe between full-screen applications** enabled: the native switching mechanism depends on it.
4. In Mission Control, turn off automatic Space rearrangement to keep desktop numbers stable.

The window shows the current status, authorization, active desktop and shortcuts.
Internal identifiers and the log location are available under **Technical details…** (`Détails techniques…`).
The menu bar menu lets you pause, quit and enable launch at login
(disabled by default). No additional service is installed.

## Behavior and limitations

- Numbers follow the order of **ordinary desktops** in Mission Control, independently of their internal identifiers.
- Full-screen Spaces count toward the switching path but do not receive an ordinary desktop number.
- SpaceKeys does not create, delete or reorder Spaces, or resize windows.
- Switch requests are serialized; only the latest destination is queued when shortcuts are pressed rapidly.
- A brief Dock settling period prevents successive gestures from overlapping.
- Failures are reported: simulated shortcuts with animated transitions are never used as a fallback.
- Full-screen windows, active dialogs and windows belonging to multiple Spaces cannot be sent.
- Every window move is confirmed by reading its membership in the destination Space again.
- No injection, SIP changes, network access or screen recording permission.

**Compatibility:** the app uses private macOS 27 interfaces.
Their behavior may change with system updates. Visually animation-free switching,
rapid sequences, multiple displays and Amethyst integration require native observation:
build checks alone do not validate them. See the actual results in [VALIDATION.md](VALIDATION.md).

## Diagnostics

```sh
# Read-only: no desktop changes or shortcut registration
build/SpaceKeys.app/Contents/MacOS/SpaceKeys --diagnose

# Check the controller and timer lifecycle
build/SpaceKeys.app/Contents/MacOS/SpaceKeys --lifecycle-test

# Move only a temporary window created by the app, then restore it
build/SpaceKeys.app/Contents/MacOS/SpaceKeys --native-move-test
```

The last test is also available from the menu.
Local log: `~/Library/Logs/SpaceKeys.log` (status and identifiers, not window titles).

## Project structure

| Path | Contents |
| --- | --- |
| `Sources/main.swift` | Application, shortcuts and Space operations |
| `Sources/StatusWindow.swift` | Native AppKit window |
| `Sources/Core.swift` | Desktop model and gesture events |
| `Sources/Bridge.c`, `Bridge.h` | Native bridge for reading Spaces and moving windows |
| `Tests/` | Checks for the model and serialized events |
| `Resources/AppIcon.png` | Original icon with transparency |
| `docs/icon-generation.md` | Icon generation tool and prompt |
| `build.sh`, `Info.plist` | Build script and macOS metadata |
| `Licenses/`, `SOURCES.txt` | Third-party notices and source references |

`build/` is ignored by Git. The source folder can be added to a repository without including build outputs.

## Provenance

The window-move bridge adapts part of [gechr/WhichSpace](https://github.com/gechr/WhichSpace),
under the MIT license; its notice is preserved in `Licenses/WhichSpace-MIT.txt`.
The event format is also documented by [joshuarli/iss](https://github.com/joshuarli/iss),
under 0BSD; its notice is included. The revisions studied are listed in `SOURCES.txt`.
Analysis of [Spacetile](https://github.com/Spacetile/Spacetile.app) informed the mechanisms used;
no code covered by its proprietary license is incorporated.
The icon was created with OpenAI's built-in image generation tool; the prompt is included.

To uninstall: disable launch at login if necessary, quit SpaceKeys,
then delete the application. The log can be deleted separately.
