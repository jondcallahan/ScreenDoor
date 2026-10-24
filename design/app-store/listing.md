# App Store listing

Copy for App Store Connect, version 1.0. Limits are Apple's character limits.

## App information

- **Name** (30): Screen Door – Remote Desktop (the name under the icon stays "Screen Door")
- **Subtitle** (30): See and control your Mac
- **Primary category:** Utilities
- **Secondary category:** Productivity
- **Content rights:** doesn't contain, show or access third-party content
- **Age rating:** answer "None" to every question, which gives 4+
- **Price:** Free, all countries
- **Privacy policy URL:** https://screendoor.net/privacy
- **Support URL:** https://screendoor.net/support
- **Marketing URL:** https://screendoor.net
- **Copyright:** 2026 Jon Callahan

## App privacy

Data collection: **No, we do not collect data from this app.**

## Version 1.0

**Promotional text** (170):

Free, private and open source. Reach your Mac from iPhone, iPad or Apple Vision Pro. On iPhone Duo, stand it up like a laptop for a Mac keyboard and trackpad.

**Description** (4000):

Screen Door shows your Mac's screen on your iPhone, iPad or Apple Vision Pro, and lets you control it. It uses the Screen Sharing built into macOS, so there's nothing to install on your Mac.

FINDS YOUR MACS
Macs on your network show up by themselves, each with the right icon. Tap one, then sign in with the username and password you use on the Mac.

AT HOME OR AWAY
Give a Mac its Tailscale address too. Screen Door uses your local network when the Mac answers there, and Tailscale or another VPN when you're out.

MADE FOR TOUCH
• Look around: drag and pinch to explore the screen without touching the Mac.
• Mouse mode: drag to move the pointer, tap to click, tap with two fingers to right-click, and drag with two fingers to scroll.
• Every key a Mac needs: Command, Option, Control, Shift, esc, tab and the arrow keys sit right above the keyboard.
• The screen slides up so the keyboard doesn't cover the spot you're typing into.

ON IPAD
Use a trackpad, mouse or hardware keyboard as if you were at your desk. Each Mac opens in its own window, so you can keep two side by side.

ON IPHONE DUO
• Open it, and your Macs sit beside the one you're using. One button takes the Mac full screen, and the same button brings the list back.
• Fold it partway and stand it up like a laptop. The Mac's screen moves to the top half, with a full Mac keyboard and a trackpad below the fold.
• Mission Control, Spotlight, Switch Apps, screenshots and Lock Screen sit in the toolbar beside the screen.
• Close it and you stay on your Mac, still connected.

ON APPLE VISION PRO
Look at something and tap to click it. Pinch and drag to scroll. The window takes the shape of your Mac's screen, and you can put it anywhere.

PRIVATE
No account, no analytics and no tracking. Your passwords stay in the Keychain on your device, and Screen Door connects straight to your Mac with no servers in between. The code is open source.

SET UP
On your Mac, open System Settings > General > Sharing and turn on Screen Sharing. Then open Screen Door and tap your Mac.

Screen Door works with Macs running macOS Screen Sharing. Connecting from outside your home network needs Tailscale or another VPN.

**Keywords** (100):

vnc,remote desktop,screen sharing,remote control,tailscale,viewer,mouse,keyboard,trackpad,access

**What's new:** leave empty for 1.0.

## Screenshots

`screenshots/iphone-duo/` has uncaptioned iPhone Duo screenshots at Apple's sizes (inner 2853 × 2007, outer 1398 × 2034). In October 2026 App Store Connect lists the sizes but has no upload slot for iPhone Duo yet, so keep using the iPhone 6.9" set. Duo screenshots become required in April 2027 for apps built with the iOS 27.1 SDK. See `../iphone-duo/README.md` to rebuild them.

## App Review

**Sign-in required:** No. Screen Door has no account. It signs in to the reviewer's own Mac.

**Notes:**

Screen Door is a VNC client for the Screen Sharing built into macOS. It has no account and no server of its own. It connects only to a Mac the user chooses.

To test it, you need a Mac with Screen Sharing turned on (System Settings > General > Sharing > Screen Sharing) on the same network as the test device:
1. Open Screen Door. The Mac appears under "On This Network". Tap it, then tap Save.
2. Tap the Mac and sign in with that Mac's username and password.
3. Tap the pointer button to control the Mac. Tap the keyboard button to type.

On iPhone Duo, the app has a few extra layouts:
- Open the device. The list of Macs sits on the left and the Mac on the right. The full-screen button in the toolbar switches between the two.
- Rotate the open device so the fold runs side to side, then fold it partway and stand it up like a laptop. The Mac's screen moves to the top half, and the bottom half shows a Mac keyboard and a trackpad.
- Close the device. The session stays connected on the outer display.

The attached video shows the app controlling a Mac from an iPhone, from launch to typing, in case a Mac isn't available.

The app asks for Local Network access to find Macs with Bonjour (_rfb._tcp). Encryption is used only to authenticate to the Mac, as defined by the VNC and Apple Remote Desktop protocols.

**Attachment:** a screen recording from a real iPhone controlling a Mac. Still to film.

## Export compliance

The app only uses encryption to authenticate (VNC's DES challenge and Apple Remote Desktop's Diffie-Hellman and AES sign-in), and doesn't encrypt the session itself. That's exempt, so the answer is "None of the algorithms mentioned above". You're the one attesting to this, so check it before submitting.
