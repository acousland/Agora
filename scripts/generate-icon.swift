import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[1])
func drawIcon(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let s = CGFloat(size)
    let rect = NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.21, yRadius: s * 0.21)
    NSGradient(starting: NSColor(red: 0.31, green: 0.31, blue: 0.58, alpha: 1), ending: NSColor(red: 0.13, green: 0.16, blue: 0.24, alpha: 1))!.draw(in: path, angle: -70)
    let ring = NSBezierPath(ovalIn: NSRect(x: s * 0.2, y: s * 0.2, width: s * 0.6, height: s * 0.6))
    ring.lineWidth = s * 0.012
    NSColor(red: 0.76, green: 0.75, blue: 1, alpha: 0.32).setStroke(); ring.stroke()
    let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
    let font = NSFont.systemFont(ofSize: s * 0.63, weight: .medium)
    let text = NSAttributedString(string: "a", attributes: [.font: font, .foregroundColor: NSColor(red: 0.84, green: 0.83, blue: 1, alpha: 1), .paragraphStyle: paragraph])
    text.draw(in: NSRect(x: 0, y: s * 0.19, width: s, height: s * 0.75))
    NSColor(red: 0.83, green: 0.83, blue: 1, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: s * 0.723, y: s * 0.235, width: s * 0.08, height: s * 0.08)).fill()
    image.unlockFocus()
    return image
}
func save(_ image: NSImage, _ url: URL) throws {
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}
let iconset = root.appendingPathComponent("Assets/Agora.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try save(drawIcon(size: size), iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try save(drawIcon(size: size * 2), iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
for size in [16, 32, 64, 80] { try save(drawIcon(size: size), root.appendingPathComponent("Sources/AgoraMac/Resources/Outlook/icon-\(size).png")) }
