import AppKit
import SwiftUI

// Puts a raw iPhone Duo simulator capture into device chrome, on a transparent background.
//
//   swift frame-duo.swift folded <capture.png> <out.png> [width px, default 900]
//   swift frame-duo.swift open   <capture.png> <out.png> [width px, default 1900]
//
// folded: Apple's own chrome from Xcode (hinge spine on the left) + the outer display's mask.
// open:   Xcode ships no open-Duo chrome, so this draws one in the same style (rim, band, black bezel,
//         hinge marks, faint crease) with Apple's inner-display mask. It's an approximation; say so.
// Captures: outer display 1398 × 2034 (folded), inner 2853 × 2007 (open, landscape). Needs Xcode 27.1+.

let chromeDir = URL(fileURLWithPath: "/Library/Developer/DeviceKit/Chrome/phone15.devicechrome/Contents/Resources")
let duoDir = URL(fileURLWithPath: "/Library/Developer/CoreSimulator/Profiles/DeviceTypes/iPhone Duo.simdevicetype/Contents/Resources")

/// The device type's profile.plist names the masks; read them rather than hardcoding the UUIDs.
func duoMasks() -> (outer: URL, inner: URL) {
    let pdfs = (try? FileManager.default.contentsOfDirectory(at: duoDir, includingPropertiesForKeys: nil))?
        .filter { $0.pathExtension == "pdf" && !$0.lastPathComponent.hasPrefix("sensor") } ?? []
    let sized = pdfs.compactMap { url -> (URL, CGFloat)? in
        guard let rep = NSPDFImageRep(data: (try? Data(contentsOf: url)) ?? Data()) else { return nil }
        return (url, rep.bounds.width)
    }.sorted { $0.1 < $1.1 }
    guard sized.count >= 2 else { fatalError("iPhone Duo device type not found; install Xcode 27.1+") }
    return (sized.first!.0, sized.last!.0) // outer is 466 pt wide, inner (portrait) 1252
}

func raster(_ url: URL, width: CGFloat, height: CGFloat, quarterTurn: Bool = false) -> NSImage {
    guard let pdf = NSPDFImageRep(data: try! Data(contentsOf: url)) else { fatalError("bad pdf \(url.lastPathComponent)") }
    let w = Int(width.rounded()), h = Int(height.rounded())
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    if quarterTurn {
        let t = NSAffineTransform(); t.translateX(by: 0, yBy: CGFloat(h)); t.rotate(byDegrees: -90); t.concat()
        pdf.draw(in: NSRect(x: 0, y: 0, width: h, height: w))
    } else {
        pdf.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
    }
    NSGraphicsContext.restoreGraphicsState()
    let image = NSImage(size: NSSize(width: w, height: h)); image.addRepresentation(rep)
    return image
}

struct FoldedDevice: View {
    var image: NSImage; var width: CGFloat; var mask: URL
    var body: some View {
        let s = width / 514 // PhoneComposite is 514 × 706 pt; screen inset 26 left, 14 top
        ZStack(alignment: .topLeading) {
            Image(nsImage: raster(chromeDir.appending(path: "PhoneComposite.pdf"), width: width, height: 706 * s)).resizable()
            Image(nsImage: image).resizable()
                .frame(width: 466 * s, height: 678 * s)
                .mask { Image(nsImage: raster(mask, width: 466 * s, height: 678 * s)).resizable() }
                .offset(x: 26 * s, y: 14 * s)
        }
        .frame(width: width, height: 706 * s)
        .shadow(color: .black.opacity(0.22), radius: 22 * s, y: 12 * s)
    }
}

struct OpenDevice: View {
    var image: NSImage; var width: CGFloat; var mask: URL
    var body: some View {
        let s = width / (951 + 28)
        let screen = CGSize(width: 951 * s, height: 669 * s)
        let r = 64 * s
        ZStack {
            RoundedRectangle(cornerRadius: r, style: .continuous).fill(.black)
            RoundedRectangle(cornerRadius: r, style: .continuous).strokeBorder(Color(white: 0.23), lineWidth: 3 * s)
            RoundedRectangle(cornerRadius: r, style: .continuous).strokeBorder(Color(white: 0.57), lineWidth: 1 * s)
            VStack {
                Rectangle().fill(Color(white: 0.12)).frame(width: 2 * s, height: 4 * s)
                Spacer()
                Rectangle().fill(Color(white: 0.12)).frame(width: 2 * s, height: 4 * s)
            }
            Image(nsImage: image).resizable()
                .frame(width: screen.width, height: screen.height)
                .overlay {
                    LinearGradient(colors: [.clear, .black.opacity(0.05), .white.opacity(0.07), .black.opacity(0.05), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: screen.width * 0.022)
                }
                .mask { Image(nsImage: raster(mask, width: screen.width, height: screen.height, quarterTurn: true)).resizable() }
        }
        .frame(width: width, height: screen.height + 28 * s)
        .shadow(color: .black.opacity(0.22), radius: 22 * s, y: 12 * s)
    }
}

let a = CommandLine.arguments
guard a.count >= 4, ["folded", "open"].contains(a[1]), let image = NSImage(contentsOf: URL(fileURLWithPath: a[2])) else {
    print("usage: swift frame-duo.swift folded|open <capture.png> <out.png> [width]"); exit(1)
}
let masks = duoMasks()
MainActor.assumeIsolated {
    let width = a.count > 4 ? CGFloat(Double(a[4])!) : (a[1] == "folded" ? 900 : 1900)
    let view = Group {
        if a[1] == "folded" { FoldedDevice(image: image, width: width, mask: masks.outer) }
        else { OpenDevice(image: image, width: width, mask: masks.inner) }
    }.padding(60) // room for the shadow
    let renderer = ImageRenderer(content: view); renderer.scale = 1
    guard let cg = renderer.cgImage else { fatalError("render failed") }
    try! NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[3]))
    print("wrote \(a[3]) \(cg.width)×\(cg.height)")
}
