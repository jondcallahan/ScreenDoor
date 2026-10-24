# Screen Door

An iPhone, iPad and Apple Vision Pro app for seeing and controlling your Mac's screen over VNC (macOS Screen Sharing). Built with SwiftUI, Liquid Glass and [RoyalVNCKit](https://github.com/royalapplications/royalvnc).

## Features

- **Look around:** drag to pan, pinch or double-tap to zoom. Nothing is sent to the Mac.
- **Mouse:** use the screen like a trackpad. Drag to move the pointer, tap to click, tap with two fingers to right-click, drag with two fingers to scroll, and touch and hold then drag to select. On iPad, a connected trackpad or mouse controls the pointer directly.
- **Vision Pro:** look at something and tap to click it. Pinch and drag to scroll. Pinch and hold, then drag to select, or let go to right-click. Each Mac's window takes the shape of its screen.
- **iPhone Duo:** open, your Macs sit on the left and the Mac you're using on the right, one on each side of the fold. One button takes the Mac full screen and the same button brings the list back. Close the Duo and you stay on the Mac, still connected. On the Mac's screen, the controls sit at either edge, one under each thumb, so nothing lands on the fold. Fold it partway and stand it up like a laptop, and it becomes a little MacBook: the Mac's screen on top, and a full Mac keyboard and trackpad on the bottom half. Hold ⌘, ⌥, ⌃ or ⇧ while you tap a key for a shortcut, or tap one first to apply it to the next key.
- **Windows:** on iPad and Vision Pro, each Mac opens in its own window, so you can see several at once.
- **Mac shortcuts:** on iPhone, Mission Control, Spotlight, Switch Apps, screenshots and Lock Screen sit in the toolbar while the keyboard is down. On iPhone Duo the toolbar stands up beside the screen.
- **Keyboard:** the on-screen keyboard, plus a row with esc, tab, ⌃ ⌥ ⌘ ⇧ and arrow keys. Hardware keyboards type on the Mac and send shortcuts like ⌘C, without opening the on-screen keyboard.
- **Finds your Macs:** Macs with Screen Sharing on show up by themselves when you're on the same network.
- **Home and away:** give each Mac a local address and a Tailscale (or other VPN) address. Screen Door tries the local one first and falls back to Tailscale, so it's the same Mac in the list wherever you are.
- Sign in with your Mac account. Passwords are stored in the iOS Keychain on this device only.

## Set up your Mac

On the Mac, open System Settings > General > Sharing and turn on **Screen Sharing**.

## Build

Requires Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

1. Copy `Config/Local.example.xcconfig` to `Config/Local.xcconfig`, then add your Apple Developer team ID and a bundle ID prefix. This file is git-ignored.
2. Run `xcodegen generate`.
3. Open `ScreenDoor.xcodeproj` and run on your device.

In T3 Code, import the actions from `t3.json` in Settings → Project. **Generate Xcode project** runs XcodeGen, and **Preview website** serves `site/` at `http://127.0.0.1:8000` and opens the desktop preview panel. Stop its terminal command with Ctrl+C when finished. Requires Python 3 for the website preview.

## Security

When you sign in, your Mac password is encrypted on its way to the Mac. After that, standard VNC doesn't encrypt the session, so the screen and your keystrokes travel unencrypted, and VNC can't confirm that you've reached your own Mac. That's fine on your home network. From anywhere else, connect over a VPN such as Tailscale, and don't expose port 5900 to the internet. Screen Door prefers a Mac's local address when something answers there, so on a network you don't trust, leave the Local address empty to always use Tailscale.

Screen Door collects no data. See the [privacy policy](PRIVACY.md).

## Known limits

- Clipboard sync is off.
- iOS keeps some shortcuts for itself, such as ⌘Tab and ⌘Space.
