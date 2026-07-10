import AppKit
import QuakePluginAPI

enum PanelMenuTemplate: String, CaseIterable {
    case classic
    case statusRail = "status-rail"
    case radialOrbit = "radial-orbit"
    case ambientMarquee = "ambient-marquee"

    init(menuID: String) {
        switch menuID {
        case "builtin:status-rail": self = .statusRail
        case "builtin:radial-orbit": self = .radialOrbit
        case "builtin:ambient-marquee": self = .ambientMarquee
        default: self = .classic
        }
    }

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .statusRail: return "Status Rail"
        case .radialOrbit: return "Radial Orbit"
        case .ambientMarquee: return "Ambient Marquee"
        }
    }
}

/// Native implementation of the RC2 menu-template shell. It intentionally owns
/// only panel chrome; the host continues to provide page bodies and plugin data.
final class MenuChromeView: NSView {
    var template: PanelMenuTemplate = .classic { didSet { needsDisplay = true } }
    var theme: PanelTheme = .fallback { didSet { needsDisplay = true } }
    var pages: [ShellPage] = [] { didSet { needsDisplay = true } }
    var selectedPageIndex = 0 { didSet { needsDisplay = true } }
    var status = "Ready" { didSet { needsDisplay = true } }
    var menuSettings: [String: JSONValue] = [:] { didSet { needsDisplay = true } }
    private lazy var darkWordmark = wordmark(named: "quakekit-wordmark-ondark")
    private lazy var lightWordmark = wordmark(named: "quakekit-wordmark-onlight")

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard template != .classic else { return }
        switch template {
        case .statusRail: drawStatusRail()
        case .radialOrbit: drawRadialOrbit()
        case .ambientMarquee: drawAmbientMarquee()
        case .classic: break
        }
    }

    func navigationIndex(at point: NSPoint) -> Int? {
        guard pages.indices.contains(selectedPageIndex) else { return nil }
        switch template {
        case .statusRail:
            guard point.x < 224, point.y < bounds.height - 38 else { return nil }
            let rowHeight: CGFloat = 42
            let top = bounds.height - 78
            let index = Int((top - point.y) / rowHeight)
            return pages.indices.contains(index) ? index : nil
        case .radialOrbit:
            let stageWidth = radialStageWidth
            guard point.y > bounds.height - 72, point.x >= stageWidth else { return nil }
            let width = max(1, (bounds.width - stageWidth - 18) / CGFloat(max(1, pages.count)))
            let index = Int((point.x - stageWidth) / width)
            return pages.indices.contains(index) ? index : nil
        case .ambientMarquee:
            let dockWidth = min(bounds.width - 80, CGFloat(max(1, pages.count)) * 116)
            let dockX = bounds.midX - dockWidth / 2
            guard point.y >= 18, point.y <= 62, point.x >= dockX, point.x <= dockX + dockWidth else { return nil }
            let width = dockWidth / CGFloat(max(1, pages.count))
            let index = Int((point.x - dockX) / width)
            return pages.indices.contains(index) ? index : nil
        case .classic:
            return nil
        }
    }

    func contentRect(in bounds: NSRect) -> NSRect {
        switch template {
        case .classic:
            return NSRect(x: 16, y: 38, width: bounds.width - 32, height: bounds.height - 100)
        case .statusRail:
            return NSRect(x: 238, y: 34, width: max(1, bounds.width - 254), height: max(1, bounds.height - 48))
        case .radialOrbit:
            let stageWidth = radialStageWidth
            return NSRect(x: stageWidth, y: 20, width: max(1, bounds.width - stageWidth - 18), height: max(1, bounds.height - 100))
        case .ambientMarquee:
            // The marquee is a composed stage: left hero, right chip field,
            // and a bottom dock. Plugin tiles are confined to the field.
            let fieldLeft = max(400, bounds.width * 0.36)
            return NSRect(x: fieldLeft, y: 84, width: max(1, bounds.width - fieldLeft - 34), height: max(1, bounds.height - 110))
        }
    }

    private func drawStatusRail() {
        fill(bounds, color: theme.background)
        fill(NSRect(x: 0, y: 0, width: 224, height: bounds.height), color: theme.surface.withAlphaComponent(0.94))
        stroke(NSRect(x: 0, y: 0, width: 224, height: bounds.height), color: theme.border)
        drawWordmark(in: NSRect(x: 16, y: bounds.height - 43, width: 142, height: 37))
        drawText("STATUS RAIL", in: NSRect(x: 18, y: bounds.height - 55, width: 160, height: 14), size: 10, weight: .bold, color: theme.accent)
        drawText(clockString(), in: NSRect(x: bounds.width - 86, y: bounds.height - 30, width: 68, height: 18), size: 14, weight: .bold, color: theme.textPrimary, alignment: .right)
        strokeLine(from: NSPoint(x: 224, y: bounds.height - 38), to: NSPoint(x: bounds.width, y: bounds.height - 38), color: theme.border)
        for (index, page) in pages.enumerated() {
            let rect = NSRect(x: 12, y: bounds.height - 110 - CGFloat(index) * 42, width: 200, height: 34)
            if index == selectedPageIndex { fillRounded(rect, color: theme.accent.withAlphaComponent(0.15), radius: 6); strokeRounded(rect, color: theme.accent, radius: 6) }
            let collapsed = menuSettings["statusRail.railMode"]?.stringValue == "collapsed"
            let label = collapsed ? "\(index + 1)" : page.title.uppercased()
            drawText(label, in: rect.insetBy(dx: 12, dy: 8), size: 12, weight: .bold, color: index == selectedPageIndex ? theme.textPrimary : theme.textSecondary, alignment: collapsed ? .center : .left)
        }
        drawText(status, in: NSRect(x: 18, y: 14, width: 188, height: 16), size: 10, weight: .medium, color: theme.textSecondary)
    }

    private func drawRadialOrbit() {
        fill(bounds, color: theme.background)
        let hubDiameter = min(230, max(170, bounds.height - 150))
        let hub = NSRect(x: 28, y: max(46, (bounds.height - 72 - hubDiameter) / 2), width: hubDiameter, height: hubDiameter)
        let ring = NSBezierPath(ovalIn: hub)
        theme.surfaceRaised.setFill(); ring.fill()
        theme.accent.setStroke(); ring.lineWidth = 2; ring.stroke()
        let projected = menuSettings["radialOrbit.headlineProjection"]?.boolValue ?? true
        let hubTitle = projected && pages.indices.contains(selectedPageIndex) ? pages[selectedPageIndex].title.uppercased() : "ORBIT"
        drawText(hubTitle, in: NSRect(x: hub.minX + 12, y: hub.midY - 10, width: hub.width - 24, height: 20), size: 14, weight: .black, color: theme.textPrimary, alignment: .center)
        drawText("ORBIT", in: NSRect(x: hub.minX + 12, y: hub.midY - 31, width: hub.width - 24, height: 14), size: 10, weight: .bold, color: theme.accent, alignment: .center)
        for index in 0..<4 {
            let angle = CGFloat(index) * .pi / 2 + .pi / 4
            let center = NSPoint(x: hub.midX + cos(angle) * hubDiameter * 0.64, y: hub.midY + sin(angle) * hubDiameter * 0.64)
            fillRounded(NSRect(x: center.x - 15, y: center.y - 15, width: 30, height: 30), color: index == 0 ? theme.accent : theme.surfaceRaised, radius: 15)
        }
        strokeLine(from: NSPoint(x: 0, y: bounds.height - 72), to: NSPoint(x: bounds.width, y: bounds.height - 72), color: theme.border)
        let stageWidth = radialStageWidth
        let width = max(1, (bounds.width - stageWidth - 18) / CGFloat(max(1, pages.count)))
        for (index, page) in pages.enumerated() {
            let rect = NSRect(x: stageWidth + CGFloat(index) * width, y: bounds.height - 58, width: width - 8, height: 28)
            if index == selectedPageIndex { fillRounded(rect, color: theme.accent.withAlphaComponent(0.18), radius: 6) }
            drawText(page.title, in: rect, size: 12, weight: .bold, color: index == selectedPageIndex ? theme.textPrimary : theme.textSecondary, alignment: .center)
        }
        drawText("QuakeKit / \(clockString())", in: NSRect(x: 18, y: bounds.height - 28, width: radialStageWidth - 28, height: 16), size: 11, weight: .medium, color: theme.textSecondary)
    }

    private func drawAmbientMarquee() {
        fill(bounds, color: theme.background)
        drawAmbientWash()
        let fieldLeft = max(400, bounds.width * 0.36)
        let hero = NSRect(x: 42, y: 78, width: fieldLeft - 86, height: bounds.height - 120)
        drawText(DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .none).uppercased(), in: NSRect(x: hero.minX, y: hero.maxY - 26, width: hero.width, height: 16), size: 11, weight: .bold, color: theme.accent)
        drawText(clockString(), in: NSRect(x: hero.minX - 6, y: hero.maxY - min(168, hero.height * 0.48), width: hero.width + 12, height: min(132, hero.height * 0.42)), size: min(112, hero.width * 0.22), weight: .black, color: theme.textPrimary)
        drawText("72°", in: NSRect(x: hero.minX, y: hero.minY + 72, width: 132, height: 58), size: 52, weight: .black, color: theme.textPrimary)
        drawText("PARTLY CLOUDY", in: NSRect(x: hero.minX + 140, y: hero.minY + 103, width: hero.width - 140, height: 18), size: 14, weight: .bold, color: theme.accent)
        drawText("Charlotte, NC  ·  H 82°  L 69°", in: NSRect(x: hero.minX + 140, y: hero.minY + 78, width: hero.width - 140, height: 18), size: 12, weight: .medium, color: theme.textSecondary)

        let tray = NSRect(x: bounds.width - 304, y: bounds.height - 40, width: 278, height: 24)
        fillRounded(tray, color: theme.surface.withAlphaComponent(0.78), radius: 12)
        strokeRounded(tray, color: theme.border, radius: 12)
        drawText("CPU 38%   ·   WEATHER 72°   ·   MARQUEE", in: tray.insetBy(dx: 10, dy: 5), size: 10, weight: .bold, color: theme.textSecondary, alignment: .center)
        strokeLine(from: NSPoint(x: fieldLeft - 18, y: 76), to: NSPoint(x: fieldLeft - 18, y: bounds.height - 54), color: theme.border.withAlphaComponent(0.6))

        let dockY: CGFloat = 18
        let dockWidth = min(bounds.width - 80, CGFloat(max(1, pages.count)) * 116)
        let dockX = bounds.midX - dockWidth / 2
        let dock = NSRect(x: dockX, y: dockY, width: dockWidth, height: 44)
        fillRounded(dock, color: theme.surfaceRaised.withAlphaComponent(0.88), radius: 16)
        strokeRounded(dock, color: theme.border, radius: 16)
        let width = dock.width / CGFloat(max(1, pages.count))
        let dockAutohides = menuSettings["ambientMarquee.dockPolicy"]?.stringValue == "autohide"
        for (index, page) in pages.enumerated() {
            let rect = NSRect(x: dock.minX + CGFloat(index) * width + 4, y: dockY + 4, width: width - 8, height: 36)
            if index == selectedPageIndex { fillRounded(rect, color: theme.accent.withAlphaComponent(dockAutohides ? 0.10 : 0.18), radius: 8); strokeRounded(rect, color: theme.accent, radius: 8) }
            drawText(page.title.uppercased(), in: rect.insetBy(dx: 4, dy: 12), size: 10, weight: .bold, color: index == selectedPageIndex ? theme.textPrimary : theme.textSecondary, alignment: .center)
        }
    }

    private func clockString() -> String { DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short) }
    private func drawAmbientWash() {
        theme.accent.withAlphaComponent(0.10).setFill()
        NSBezierPath(ovalIn: NSRect(x: -bounds.width * 0.18, y: bounds.height * 0.38, width: bounds.width * 0.78, height: bounds.height * 0.9)).fill()
        theme.danger.withAlphaComponent(0.06).setFill()
        NSBezierPath(ovalIn: NSRect(x: bounds.width * 0.54, y: -bounds.height * 0.32, width: bounds.width * 0.72, height: bounds.height * 0.9)).fill()
    }
    private var radialStageWidth: CGFloat { min(max(300, bounds.width * 0.18), 350) }
    private func wordmark(named name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "svg", subdirectory: "Brand") else { return nil }
        return NSImage(contentsOf: url)
    }
    private func drawWordmark(in rect: NSRect) {
        let rgb = theme.background.usingColorSpace(.deviceRGB)
        let luminance = (rgb?.redComponent ?? 0) * 0.2126 + (rgb?.greenComponent ?? 0) * 0.7152 + (rgb?.blueComponent ?? 0) * 0.0722
        (luminance > 0.55 ? lightWordmark : darkWordmark)?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
    private func fill(_ rect: NSRect, color: NSColor) { color.setFill(); rect.fill() }
    private func stroke(_ rect: NSRect, color: NSColor) { color.setStroke(); NSBezierPath(rect: rect).stroke() }
    private func fillRounded(_ rect: NSRect, color: NSColor, radius: CGFloat) { color.setFill(); NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill() }
    private func strokeRounded(_ rect: NSRect, color: NSColor, radius: CGFloat) { color.setStroke(); let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius); path.lineWidth = 1; path.stroke() }
    private func strokeLine(from: NSPoint, to: NSPoint, color: NSColor) { color.setStroke(); let path = NSBezierPath(); path.move(to: from); path.line(to: to); path.lineWidth = 1; path.stroke() }
    private func drawText(_ value: String, in rect: NSRect, size: CGFloat, weight: NSFont.Weight, color: NSColor, alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = alignment; paragraph.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: value, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: paragraph]).draw(in: rect)
    }
}
