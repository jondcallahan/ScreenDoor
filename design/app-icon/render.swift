// Screen Door app icon: a solid laptop with an outlined iPhone in front, in white on a blue gradient.
// swift design/app-icon/render.swift ScreenDoor/Assets.xcassets/AppIcon.appiconset/icon.png
// Add `preview.png old-icon.png` to also write an old-vs-new comparison sheet.
// Add `--vision DIR` instead to also write the Vision Pro icon's layers, back.png and front.png, to DIR.
import AppKit

let size: CGFloat = 1024
let stroke: CGFloat = 50          // the laptop's base
let gap: CGFloat = 32             // clear space between the laptop and the phone
let bezel: CGFloat = 34           // the laptop screen's white border
let phoneBezel: CGFloat = 40      // a touch heavier than the laptop's, as the phone is drawn smaller

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
}

// Shapes in a y-down 1024 grid, before centring.
let screen = CGRect(x: 0, y: 0, width: 520, height: 352)       // laptop lid, outer edge
let base = CGRect(x: -58, y: screen.maxY, width: screen.width + 116, height: stroke)
let phone = CGRect(x: 386, y: 102, width: 218, height: 362)     // overlaps the lid's right side
let screenRadius: CGFloat = 46
let phoneRadius: CGFloat = 58

let art = screen.union(base).union(phone)
// Centre the artwork, nudged a little above the middle so it looks centred.
let offset = CGPoint(x: (size - art.width) / 2 - art.minX, y: (size - art.height) / 2 - art.minY - 8)
func place(_ r: CGRect) -> CGRect { r.offsetBy(dx: offset.x, dy: offset.y) }

/// The icon is a background and the artwork on top. Vision Pro shows them as separate layers.
func icon(background: Bool = true, art: Bool = true) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: (art && !background ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)!
    ctx.translateBy(x: 0, y: size); ctx.scaleBy(x: 1, y: -1)   // y-down
    if background { drawBackground(ctx) }
    if art { drawArt(ctx) }
    return ctx.makeImage()!
}

func drawBackground(_ ctx: CGContext) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [rgb(75, 177, 255), rgb(11, 93, 243)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size), options: [])
    drawMesh(ctx)
}

/// A faint woven wire mesh, like a screen door. Each wire is shaded so it looks round, and the
/// wires take turns crossing over each other, with a small shadow where one passes over the other.
let meshPitch: CGFloat = 30      // wire spacing. Much finer and it's lost at home screen size.
let meshStrength: CGFloat = 0.12 // how strongly the wires show

func drawMesh(_ ctx: CGContext) {
    let wire = meshPitch * 0.22
    let count = Int(size / meshPitch) + 1
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let shade = CGColor(srgbRed: 0, green: 0.06, blue: 0.28, alpha: meshStrength * 1.4)
    let shine = CGColor(gray: 1, alpha: meshStrength * 1.6)
    let round = CGGradient(colorsSpace: space, colors: [shade, shine, shade] as CFArray, locations: [0, 0.4, 1])!
    let shadow = CGColor(srgbRed: 0, green: 0.04, blue: 0.2, alpha: meshStrength * 1.2)

    func wireRect(_ rect: CGRect, horizontal: Bool) {
        ctx.saveGState()
        ctx.clip(to: rect)
        let start = horizontal ? CGPoint(x: 0, y: rect.minY) : CGPoint(x: rect.minX, y: 0)
        let end = horizontal ? CGPoint(x: 0, y: rect.maxY) : CGPoint(x: rect.maxX, y: 0)
        ctx.drawLinearGradient(round, start: start, end: end, options: [])
        ctx.restoreGState()
    }
    func row(_ i: Int) -> CGRect { CGRect(x: 0, y: CGFloat(i) * meshPitch - wire / 2, width: size, height: wire) }
    func column(_ i: Int) -> CGRect { CGRect(x: CGFloat(i) * meshPitch - wire / 2, y: 0, width: wire, height: size) }

    // Each crossing shows only the wire on top. The wire underneath gets a short shadow either side.
    func verticalOnTop(_ r: Int, _ c: Int) -> Bool { (r + c) % 2 == 0 }
    let shadowLength = wire * 0.45
    for r in 0...count {
        let band = row(r)
        var x: CGFloat = 0
        for c in 0...count + 1 where c > count || verticalOnTop(r, c) {
            let gapStart = c > count ? size : CGFloat(c) * meshPitch - wire / 2
            if gapStart > x { wireRect(CGRect(x: x, y: band.minY, width: gapStart - x, height: wire), horizontal: true) }
            if c <= count {
                ctx.setFillColor(shadow)
                ctx.fill(CGRect(x: gapStart - shadowLength, y: band.minY, width: shadowLength, height: wire))
                ctx.fill(CGRect(x: gapStart + wire, y: band.minY, width: shadowLength, height: wire))
            }
            x = gapStart + wire
        }
    }
    for c in 0...count {
        let band = column(c)
        var y: CGFloat = 0
        for r in 0...count + 1 where r > count || !verticalOnTop(r, c) {
            let gapStart = r > count ? size : CGFloat(r) * meshPitch - wire / 2
            if gapStart > y { wireRect(CGRect(x: band.minX, y: y, width: wire, height: gapStart - y), horizontal: false) }
            if r <= count {
                ctx.setFillColor(shadow)
                ctx.fill(CGRect(x: band.minX, y: gapStart - shadowLength, width: wire, height: shadowLength))
                ctx.fill(CGRect(x: band.minX, y: gapStart + wire, width: wire, height: shadowLength))
            }
            y = gapStart + wire
        }
    }
}

func drawArt(_ ctx: CGContext) {
    // Draw the laptop on its own layer so the phone's gap can be cut out of it.
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setFillColor(.white)
    let lid = place(screen)
    // The lid is solid, so the outlined phone reads as standing in front of it.
    // Only the top corners are rounded. The bottom edge sits flush on the base.
    let lidPath = CGMutablePath()
    lidPath.move(to: CGPoint(x: lid.minX, y: lid.maxY))
    lidPath.addArc(tangent1End: CGPoint(x: lid.minX, y: lid.minY), tangent2End: CGPoint(x: lid.maxX, y: lid.minY), radius: screenRadius)
    lidPath.addArc(tangent1End: CGPoint(x: lid.maxX, y: lid.minY), tangent2End: CGPoint(x: lid.maxX, y: lid.maxY), radius: screenRadius)
    lidPath.addLine(to: CGPoint(x: lid.maxX, y: lid.maxY + 1))
    lidPath.addLine(to: CGPoint(x: lid.minX, y: lid.maxY + 1))
    lidPath.closeSubpath()
    ctx.addPath(lidPath)
    ctx.fillPath()
    // The Mac's screen: a pale panel inside the white bezel, so the lid reads as a display.
    let display = CGRect(x: lid.minX + bezel, y: lid.minY + bezel,
                         width: lid.width - bezel * 2, height: lid.height - bezel * 1.6)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: display, cornerWidth: screenRadius - bezel * 0.6,
                       cornerHeight: screenRadius - bezel * 0.6, transform: nil))
    ctx.clip()
    let screenGradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                    colors: [rgb(170, 220, 255), rgb(120, 190, 255)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(screenGradient, start: CGPoint(x: 0, y: display.minY), end: CGPoint(x: 0, y: display.maxY), options: [])
    ctx.restoreGState()
    let foot = place(base)
    ctx.addPath(CGPath(roundedRect: foot, cornerWidth: stroke / 2, cornerHeight: stroke / 2, transform: nil))
    ctx.fillPath()
    // Cut the gap around the phone.
    let handset = place(phone)
    ctx.setBlendMode(.clear)
    let cut = handset.insetBy(dx: -gap, dy: -gap)
    ctx.addPath(CGPath(roundedRect: cut, cornerWidth: phoneRadius + gap, cornerHeight: phoneRadius + gap, transform: nil))
    ctx.fillPath()
    ctx.setBlendMode(.normal)
    ctx.endTransparencyLayer()

    // The phone, as an outline. Its screen shows the background.
    ctx.setFillColor(.white)
    let phonePath = CGMutablePath()
    phonePath.addRoundedRect(in: handset, cornerWidth: phoneRadius, cornerHeight: phoneRadius)
    let phoneInner = handset.insetBy(dx: phoneBezel, dy: phoneBezel)
    phonePath.addRoundedRect(in: phoneInner, cornerWidth: phoneRadius - phoneBezel * 0.6, cornerHeight: phoneRadius - phoneBezel * 0.6)
    ctx.addPath(phonePath); ctx.fillPath(using: .evenOdd)
}

func write(_ image: CGImage, to path: String) {
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil); CGImageDestinationFinalize(dest)
}

let out = CommandLine.arguments[1]
let image = icon()
write(image, to: out)

if CommandLine.arguments.count > 3, CommandLine.arguments[2] == "--vision" {
    let dir = CommandLine.arguments[3]
    write(icon(art: false), to: dir + "/back.png")
    write(icon(background: false), to: dir + "/front.png")
}

// Optional comparison sheet: old and new, masked, at 300 and 60 px, on light and dark.
if CommandLine.arguments.count > 3, CommandLine.arguments[2] != "--vision", let old = NSImage(contentsOfFile: CommandLine.arguments[3])?
    .cgImage(forProposedRect: nil, context: nil, hints: nil) {
    let w = 900, h = 820
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    for (row, bg) in [(0, rgb(242, 242, 247)), (1, rgb(28, 28, 30))] {
        let y = CGFloat(h - (row + 1) * 410)
        ctx.setFillColor(bg); ctx.fill(CGRect(x: 0, y: y, width: CGFloat(w), height: 410))
        for (col, img) in [(0, old), (1, image)] {
            let x = CGFloat(40 + col * 440)
            for (s, dx, dy) in [(CGFloat(300), CGFloat(0), CGFloat(70)), (CGFloat(60), CGFloat(320), CGFloat(70))] {
                let r = CGRect(x: x + dx, y: y + dy, width: s, height: s)
                ctx.saveGState()
                ctx.addPath(CGPath(roundedRect: r, cornerWidth: s * 0.225, cornerHeight: s * 0.225, transform: nil)); ctx.clip()
                ctx.interpolationQuality = .high; ctx.draw(img, in: r)
                ctx.restoreGState()
            }
        }
    }
    write(ctx.makeImage()!, to: CommandLine.arguments[2])
}
