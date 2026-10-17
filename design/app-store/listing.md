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

Until screendoor.net points at the site, use https://screendoor-one.vercel.app/privacy and /support.

## App privacy

Data collection: **No, we do not collect data from this app.**

## Version 1.0

**Promotional text** (170):

Free, private and open source. Reach your Mac from your iPhone, iPad or Apple Vision Pro with the Screen Sharing that's built into macOS.

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

## App Review

**Sign-in required:** No. Screen Door has no account. It signs in to the reviewer's own Mac.

**Notes:**

Screen Door is a VNC client for the Screen Sharing built into macOS. It has no account and no server of its own. It connects only to a Mac the user chooses.

To test it, you need a Mac with Screen Sharing turned on (System Settings > General > Sharing > Screen Sharing) on the same network as the test device:
1. Open Screen Door. The Mac appears under "On This Network". Tap it, then tap Save.
2. Tap the Mac and sign in with that Mac's username and password.
3. Tap the pointer button to control the Mac. Tap the keyboard button to type.

The attached video shows the app controlling a Mac from an iPhone, from launch to typing, in case a Mac isn't available.

The app asks for Local Network access to find Macs with Bonjour (_rfb._tcp). Encryption is used only to authenticate to the Mac, as defined by the VNC and Apple Remote Desktop protocols.

**Attachment:** a screen recording from a real iPhone controlling a Mac. Still to film.

## Export compliance

The app only uses encryption to authenticate (VNC's DES challenge and Apple Remote Desktop's Diffie-Hellman and AES sign-in), and doesn't encrypt the session itself. That's exempt, so the answer is "None of the algorithms mentioned above". You're the one attesting to this, so check it before submitting.
