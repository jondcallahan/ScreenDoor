#!/usr/bin/env python3
"""Makes the open-Duo frame for the site's clips: the frame with a see-through screen, and a mask in the
screen's exact shape for the video under it.

    swift frame-duo.swift open magenta.png frame-magenta.png 1900   # a solid #ff00ff 2853 × 2007 capture
    swift frame-duo.swift open clear.png frame-clear.png 1900       # a fully transparent capture
    python3 -I clip-frame.py frame-magenta.png frame-clear.png frame-hole.png screen-mask.png

It prints the screen's position in the frame, which the site's CSS uses to place the video.
"""
import subprocess, sys

magenta_path, clear_path, hole_path, mask_path = sys.argv[1:5]

def size(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=width,height", "-of", "csv=p=0", path],
                         capture_output=True, text=True).stdout.strip()
    return tuple(int(v) for v in out.split(","))

def pixels(path, fmt):
    return bytearray(subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-f", "rawvideo", "-pix_fmt", fmt, "-"],
                                    capture_output=True).stdout)

W, H = size(magenta_path)
magenta, frame = pixels(magenta_path, "rgb24"), pixels(clear_path, "rgba")

def screen(i):
    """How much of this pixel is screen, from 0 to 1."""
    r, g = magenta[i * 3], magenta[i * 3 + 1]
    return max(0.0, min(1.0, (r - g - 20) / 215.0))

xs, ys = [], []
for y in range(H):
    for x in range(W):
        if screen(y * W + x) > 0.5:
            xs.append(x); ys.append(y)
X, Y, SW, SH = min(xs), min(ys), max(xs) - min(xs) + 1, max(ys) - min(ys) + 1

hole, mask = bytearray(frame), bytearray(SW * SH * 4)
for y in range(H):
    for x in range(W):
        i = y * W + x
        k = screen(i)
        if k > 0:
            hole[i * 4 + 3] = int(frame[i * 4 + 3] * (1 - k))
        if X <= x < X + SW and Y <= y < Y + SH:
            j = ((y - Y) * SW + (x - X)) * 4
            mask[j:j + 4] = bytes((255, 255, 255, int(255 * k)))

def save(buf, w, h, out):
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgba", "-s", f"{w}x{h}",
                    "-i", "-", out], input=bytes(buf))

save(hole, W, H, hole_path)
save(mask, SW, SH, mask_path)
print(f"frame {W}x{H}, screen at x {X}, y {Y}, {SW}x{SH}")
