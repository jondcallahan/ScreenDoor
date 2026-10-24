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

## Clips

The site's two clips are screen recordings from the simulator: `clips/open-raw.mov` (tap a Mac, it appears beside the
list, then full screen) and `clips/deck-raw.mov` (Shift and Command latching on the MacBook deck, with the faked
fold). Record with `xcrun simctl io <udid> recordVideo --display=<inner display uuid> --codec=h264`.

The simulator only writes a frame when the screen changes, so convert to a steady frame rate before trimming:

```sh
ffmpeg -i clips/open-raw.mov -filter_complex "[0:v]fps=30,split[s1][s2];[s1]trim=1.0:5.0,setpts=PTS-STARTPTS[a];[s2]trim=7.4:9.3,setpts=PTS-STARTPTS[b];[a][b]concat=n=2:v=1[c];[c]scale=1280:900:flags=lanczos,tpad=stop_mode=clone:stop_duration=1.2,format=yuv420p[v]" -map "[v]" -c:v libx264 -preset slow -crf 23 -movflags +faststart -an ../../site/img/duo-open-clip.mp4
ffmpeg -i clips/deck-raw.mov -filter_complex "[0:v]fps=30,trim=1.4:8.8,setpts=PTS-STARTPTS,crop=2600:850:0:1062,scale=1400:458:flags=lanczos,tpad=stop_mode=clone:stop_duration=0.5,format=yuv420p[v]" -map "[v]" -c:v libx264 -preset slow -crf 22 -movflags +faststart -an ../../site/img/duo-deck-clip.mp4
```

Each clip's poster is its last frame (`ffmpeg -sseof -0.1 -i clip.mp4 -frames:v 1 poster.jpg`). The open clip plays
under `duo-clip-frame.png`, a render with a see-through screen, and is cut to the screen's shape by
`duo-clip-mask.png`. `clip-frame.py` makes both, and prints the screen's position for the CSS.
