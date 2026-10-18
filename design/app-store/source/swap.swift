import AppKit
// Replaces the mock Mac desktop inside an app screenshot with a re-rendered version.
// Usage: swap shot.png old-desktop.png new-desktop.png out.png [quality]
// Finds where the desktop sits in the shot (scale + offset) from the yellow "Weekend plan"
// selection, refines it by minimising pixel differences, then swaps only pixels where the
// shot still shows the old desktop and the new desktop is different. App UI on top is kept.

struct Img { var w: Int; var h: Int; var p: [UInt8] }
func load(_ path: String) -> Img {
    let src = NSImage(contentsOfFile: path)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    let w = src.width, h = src.height
    var p = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &p, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))
    return Img(w: w, h: h, p: p)
}
func save(_ img: Img, _ path: String, jpeg: Double?) {
    var p = img.p
    let ctx = CGContext(data: &p, width: img.w, height: img.h, bitsPerComponent: 8, bytesPerRow: img.w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    let data = jpeg != nil ? rep.representation(using: .jpeg, properties: [.compressionFactor: jpeg!])!
                           : rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}
// Box-filtered downscale so the desktop matches the shot's own resampling.
func downscale(_ a: Img, by f: Int) -> Img {
    let w = a.w / f, h = a.h / f
    var p = [UInt8](repeating: 0, count: w * h * 4)
    for y in 0..<h { for x in 0..<w { for c in 0..<4 {
        var s = 0
        for dy in 0..<f { for dx in 0..<f { s += Int(a.p[((y * f + dy) * a.w + x * f + dx) * 4 + c]) } }
        p[(y * w + x) * 4 + c] = UInt8(s / (f * f))
    } } }
    return Img(w: w, h: h, p: p)
}
// Bilinear sample of the desktop at desktop-space coordinates.
func sample(_ a: Img, _ x: Double, _ y: Double) -> (Double, Double, Double)? {
    if x < 0 || y < 0 || x > Double(a.w - 1) || y > Double(a.h - 1) { return nil }
    let x0 = Int(x), y0 = Int(y), x1 = min(x0 + 1, a.w - 1), y1 = min(y0 + 1, a.h - 1)
    let fx = x - Double(x0), fy = y - Double(y0)
    func px(_ xx: Int, _ yy: Int, _ c: Int) -> Double { Double(a.p[(yy * a.w + xx) * 4 + c]) }
    var out = [0.0, 0.0, 0.0]
    for c in 0..<3 {
        out[c] = px(x0, y0, c) * (1 - fx) * (1 - fy) + px(x1, y0, c) * fx * (1 - fy) + px(x0, y1, c) * (1 - fx) * fy + px(x1, y1, c) * fx * fy
    }
    return (out[0], out[1], out[2])
}
// Bounding box of the yellow selection (#ffd54a).
func yellowBox(_ a: Img) -> (Int, Int, Int, Int)? {
    var x0 = Int.max, y0 = Int.max, x1 = -1, y1 = -1
    for y in 0..<a.h { for x in 0..<a.w {
        let i = (y * a.w + x) * 4
        let r = Int(a.p[i]), g = Int(a.p[i + 1]), b = Int(a.p[i + 2])
        if abs(r - 255) < 22 && abs(g - 213) < 26 && abs(b - 74) < 40 { x0 = min(x0, x); y0 = min(y0, y); x1 = max(x1, x); y1 = max(y1, y) }
    } }
    return x1 < 0 ? nil : (x0, y0, x1, y1)
}

let a = CommandLine.arguments
let shot = load(a[1])
let oldFull = load(a[2]), newFull = load(a[3])
let quality = a.count > 5 && a[5] != "-" ? Double(a[5]) : nil
let seed: (Double, Double, Double)? = a.count > 8 ? (Double(a[6])!, Double(a[7])!, Double(a[8])!) : nil
let maxY = a.count > 9 ? Int(a[9])! : Int.max   // rows at or below this are left alone (e.g. a keyboard)

// Work against a 2560x1600 desktop (the size the VNC server sent).
let factor = oldFull.w / 2560
let old = factor > 1 ? downscale(oldFull, by: factor) : oldFull
let new = factor > 1 ? downscale(newFull, by: factor) : newFull

// 1. Initial estimate from the yellow box. Its height is never clipped; use it for scale,
//    and its right/bottom edge for offset (the left edge can be cut off in zoomed shots).
guard let ob = yellowBox(old) else { print("no yellow box in desktop"); exit(1) }
var s = 0.0, tx = 0.0, ty = 0.0
if let seed { (s, tx, ty) = seed } else {
    guard let yb = yellowBox(shot) else { print("no yellow box"); exit(1) }
    s = Double(yb.3 - yb.1 + 1) / Double(ob.3 - ob.1 + 1)      // shot px per desktop px
    tx = Double(yb.2) - Double(ob.2) * s
    ty = Double(yb.3) - Double(ob.3) * s
}
print("initial s=\(s) tx=\(tx) ty=\(ty)")

// 2. Refine by minimising mean abs difference over a grid of shot pixels.
func cost(_ s: Double, _ tx: Double, _ ty: Double) -> Double {
    var sum = 0.0, n = 0
    let step = max(2, shot.w / 180)
    for y in stride(from: 0, to: shot.h, by: step) { for x in stride(from: 0, to: shot.w, by: step) {
        guard let o = sample(old, (Double(x) - tx) / s, (Double(y) - ty) / s) else { continue }
        let i = (y * shot.w + x) * 4
        let d = abs(Double(shot.p[i]) - o.0) + abs(Double(shot.p[i + 1]) - o.1) + abs(Double(shot.p[i + 2]) - o.2)
        sum += min(d, 120); n += 1   // cap so app UI on top doesn't dominate
    } }
    return n < 200 ? 1e9 : sum / Double(n)
}
var best = cost(s, tx, ty)
for (ds, dt) in [(0.02, 8.0), (0.005, 2.0), (0.001, 0.5), (0.0002, 0.15)] {
    var improved = true
    while improved {
        improved = false
        for (a1, b1, c1) in [(ds, 0.0, 0.0), (-ds, 0.0, 0.0), (0.0, dt, 0.0), (0.0, -dt, 0.0), (0.0, 0.0, dt), (0.0, 0.0, -dt)] {
            // scale steps keep the yellow box's bottom-right anchored
            let ns = s * (1 + a1)
            let ntx = tx + b1 - Double(ob.2) * (ns - s), nty = ty + c1 - Double(ob.3) * (ns - s)
            let c = cost(ns, ntx, nty)
            if c < best - 1e-6 { best = c; s = ns; tx = ntx; ty = nty; improved = true }
        }
    }
}
print("refined s=\(s) tx=\(tx) ty=\(ty) cost=\(best)")

// 3. Swap pixels: where the shot matches the old desktop and the new one differs.
//    A soft weight avoids hard edges around app UI drawn on top.
var out = shot
var swapped = 0, desktop = 0
for y in 0..<min(shot.h, maxY) { for x in 0..<shot.w {
    let dx = (Double(x) - tx) / s, dy = (Double(y) - ty) / s
    guard sample(old, dx, dy) != nil else { continue }
    desktop += 1
    let i = (y * shot.w + x) * 4
    let sr = Double(shot.p[i]), sg = Double(shot.p[i + 1]), sb = Double(shot.p[i + 2])
    // Compare against the old desktop here and up to one shot pixel away, to absorb
    // sub-pixel differences at hard edges. Use whichever position matches best.
    var match = Double.infinity
    var o = (0.0, 0.0, 0.0), n = (0.0, 0.0, 0.0)
    for oy in [0.0, -1.0, 1.0] { for ox in [0.0, -1.0, 1.0] {
        let ddx = dx + ox / s, ddy = dy + oy / s
        guard let oo = sample(old, ddx, ddy), let nn = sample(new, ddx, ddy) else { continue }
        let m = abs(sr - oo.0) + abs(sg - oo.1) + abs(sb - oo.2) + (ox == 0 && oy == 0 ? 0 : 12)
        if m < match { match = m; o = oo; n = nn }
    } }
    let change = abs(n.0 - o.0) + abs(n.1 - o.1) + abs(n.2 - o.2)
    if change < 6 { continue }
    let w = max(0, min(1, (170 - match) / 70))   // 1 when shot ≈ old, 0 when app UI clearly sits on top
    if w <= 0 { continue }
    // Transfer the change (new − old) rather than replacing the pixel. Anti-aliased edges,
    // shadows and tints that mix desktop with something else then carry over correctly.
    out.p[i] = UInt8(max(0, min(255, sr + w * (n.0 - o.0))))
    out.p[i + 1] = UInt8(max(0, min(255, sg + w * (n.1 - o.1))))
    out.p[i + 2] = UInt8(max(0, min(255, sb + w * (n.2 - o.2))))
    swapped += 1
} }
print("desktop px \(desktop), swapped \(swapped)")
save(out, a[4], jpeg: quality)
