# App Store screenshots

`screenshots/` holds the finished images: iPhone 6.9" (1320×2868), iPad 13" (2752×2064) and Apple Vision Pro (3840×2160).

To make them again:

1. Render the mock Mac desktop and convert it to raw pixels:
   `swift source/snap.swift source/desktop.html desktop4x.png 1280 800`, then
   `sips -z 1600 2560 desktop4x.png --out desktop.png` and `swift source/raw.swift desktop.png source/desktop.rgbx`.
2. Serve it: `python3 source/imgserver.py 5998`. Give it a tidy name with
   `dns-sd -P "MacBook Pro" _rfb._tcp local 5998 macbook-pro.local 127.0.0.1`.
3. Load `source/hosts.json` into the simulator's saved Macs:
   `xcrun simctl spawn <device> defaults write com.joncallahan.ScreenDoor hosts -data <hex of the JSON>`.
   Hide the Macs Bonjour finds on your own network so they don't appear in the shots.
4. Capture with `xcrun simctl io <device> screenshot`, after
   `xcrun simctl status_bar <device> override --time 9:41`.
5. Add the captions: `swiftc -O source/compose.swift -o compose`, then
   `./compose <width> <height> raw.png out.png "Title" "Subtitle" <screenshot width fraction> <corner radius>`.

## The mock Mac desktop

`source/desktop.html` uses real images from `source/assets/`: a wallpaper and an album of
photos from Unsplash (fetched through picsum.photos, Unsplash License), and the Dock icons
exported from the macOS apps with `sips -s format png -Z 128 <App>.app/Contents/Resources/<icon>.icns`.

## Updating the website screenshots without re-capturing

`source/swap.swift` replaces the desktop inside an existing screenshot with a re-rendered one.
It finds where the desktop sits (scale and offset), then changes only the pixels that still show
the old desktop, so the app's own controls on top are kept.

1. Render the old and new desktops with `snap.swift` at 1280×800 (it writes 2× pixels).
2. `swiftc -O source/swap.swift -o swap`
3. `./swap shot.jpg old.png new.png out.jpg [jpeg quality] [scale x y] [stop row]`
   The optional `scale x y` gives a starting position when the screen is mostly covered
   (the keyboard shot used `0.4728 -131.1 218.7 800`).
