# iPhone Duo art

Device renders for screendoor.net and the App Store, made from real captures of the app in the iPhone Duo
simulator (Xcode 27.1, iOS 27.1 runtime).

- `captures/` holds the raw, full-resolution captures: the inner display at 2853 × 2007 and the outer at
  1398 × 2034. The demo Macs come from `../app-store/source/hosts.json`, with the mock desktop served by
  `../app-store/source/imgserver.py` and the status bar set to 9:41.
- `renders/` holds the framed devices, transparent PNGs.
- `open-macbook-deck.png` comes from a simulator with a faked side-to-side fold, because the simulator can't
  rotate the inner display into the laptop pose. Its crease doesn't match a real Duo, so the site uses only a
  crop of its keyboard and trackpad, and it isn't framed for the App Store. Replace it with a capture from a
  device.

## Rebuild

```sh
cd design/iphone-duo
swift frame-duo.swift folded captures/folded-mac.png renders/folded-mac.png 900
swift frame-duo.swift open captures/open-list-and-mac.png renders/open-list-and-mac.png 1900
```

`frame-duo.swift` uses Apple's device artwork from Xcode. The folded chrome is Apple's own. Xcode has no chrome
for an open Duo, so the open frame is drawn in the same style around Apple's screen mask. It's an
approximation.

For the site, flatten each render onto the page background as a JPEG, light (`#f5f5f7`) and dark (`#000000`):

```sh
flat() { W=$(sips -g pixelWidth "$1" | awk '/pixelWidth/{print $2}'); H=$(sips -g pixelHeight "$1" | awk '/pixelHeight/{print $2}')
  ffmpeg -y -i "$1" -filter_complex "color=c=${4}:s=${W}x${H}[bg];[bg][0]overlay=shortest=1,scale=${3}:-1:flags=lanczos" -frames:v 1 -q:v 3 "$2"; }
flat renders/open-list-and-mac.png ../../site/img/duo-open-light.jpg 1500 0xf5f5f7
flat renders/open-list-and-mac.png ../../site/img/duo-open-dark.jpg 1500 0x000000
flat renders/folded-mac.png ../../site/img/duo-folded-light.jpg 760 0xf5f5f7
flat renders/folded-mac.png ../../site/img/duo-folded-dark.jpg 760 0x000000
ffmpeg -y -i captures/open-macbook-deck.png -vf "crop=2600:850:0:1062,scale=1400:-1:flags=lanczos" -q:v 3 ../../site/img/duo-deck.jpg
```

For the App Store, `opaque.swift` writes the captures as opaque PNGs, which App Store Connect requires:
`swift opaque.swift captures/folded-mac.png ../app-store/screenshots/iphone-duo/3-folded.png`.
