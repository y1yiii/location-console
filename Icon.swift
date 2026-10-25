import AppKit

let output = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let rect = NSRect(x: 64, y: 64, width: 896, height: 896)
let background = NSBezierPath(roundedRect: rect, xRadius: 205, yRadius: 205)
NSGradient(starting: NSColor(srgbRed: 0.10, green: 0.43, blue: 0.95, alpha: 1), ending: NSColor(srgbRed: 0.02, green: 0.68, blue: 0.63, alpha: 1))!.draw(in: background, angle: 45)
NSColor.white.withAlphaComponent(0.13).setStroke()
for diameter in [470.0, 690.0] {
    let ring = NSBezierPath(ovalIn: NSRect(x: 512 - diameter / 2, y: 512 - diameter / 2, width: diameter, height: diameter))
    ring.lineWidth = 3; ring.stroke()
}
let pointer = NSBezierPath()
pointer.move(to: NSPoint(x: 725, y: 760))
pointer.line(to: NSPoint(x: 575, y: 295))
pointer.line(to: NSPoint(x: 485, y: 482))
pointer.line(to: NSPoint(x: 295, y: 575))
pointer.close()
NSColor.white.setFill(); pointer.fill()
image.unlockFocus()
func uint32Data(_ value: Int) -> Data {
    var value = UInt32(value).bigEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}
var chunks = Data()
for (size, type) in [(16, "icp4"), (32, "icp5"), (64, "icp6"), (128, "ic07"), (256, "ic08"), (512, "ic09"), (1024, "ic10")] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    let png = rep.representation(using: .png, properties: [:])!
    chunks.append(type.data(using: .ascii)!)
    chunks.append(uint32Data(png.count + 8))
    chunks.append(png)
}
var file = "icns".data(using: .ascii)!
file.append(uint32Data(chunks.count + 8))
file.append(chunks)
try file.write(to: URL(fileURLWithPath: output))
