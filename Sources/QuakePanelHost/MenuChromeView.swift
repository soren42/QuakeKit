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
            guard point.y > bounds.height - 72 else { return nil }
            let width = max(1, (bounds.width - 260) / CGFloat(max(1, pages.count)))
            let index = Int((point.x - 240) / width)
            return pages.indices.contains(index) ? index : nil
        case .ambientMarquee:
            guard point.y < 62 else { return nil }
            let width = bounds.width / CGFloat(max(1, pages.count))
            let index = Int(point.x / width)
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
            return NSRect(x: 16, y: 20, width: bounds.width - 32, height: max(1, bounds.height - 100))
        case .ambientMarquee:
            return NSRect(x: 18, y: 74, width: bounds.width - 36, height: max(1, bounds.height - 142))
        }
    }

    private func drawStatusRail() {
        fill(bounds, color: theme.background)
        fill(NSRect(x: 0, y: 0, width: 224, height: bounds.height), color: theme.surface.withAlphaComponent(0.94))
        stroke(NSRect(x: 0, y: 0, width: 224, height: bounds.height), color: theme.border)
        drawText("QuakeKit", in: NSRect(x: 18, y: bounds.height - 35, width: 128, height: 22), size: 18, weight: .black, color: theme.textPrimary)
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
        let hub = NSRect(x: 28, y: 28, width: 150, height: 150)
        let ring = NSBezierPath(ovalIn: hub)
        theme.surfaceRaised.setFill(); ring.fill()
        theme.accent.setStroke(); ring.lineWidth = 2; ring.stroke()
        let projected = menuSettings["radialOrbit.headlineProjection"]?.boolValue ?? true
        let hubTitle = projected && pages.indices.contains(selectedPageIndex) ? pages[selectedPageIndex].title.uppercased() : "ORBIT"
        drawText(hubTitle, in: NSRect(x: hub.minX + 12, y: hub.midY - 10, width: hub.width - 24, height: 20), size: 14, weight: .black, color: theme.textPrimary, alignment: .center)
        drawText("ORBIT", in: NSRect(x: hub.minX + 12, y: hub.midY - 31, width: hub.width - 24, height: 14), size: 10, weight: .bold, color: theme.accent, alignment: .center)
        for index in 0..<4 {
            let angle = CGFloat(index) * .pi / 2 + .pi / 4
            let center = NSPoint(x: hub.midX + cos(angle) * 108, y: hub.midY + sin(angle) * 108)
            fillRounded(NSRect(x: center.x - 12, y: center.y - 12, width: 24, height: 24), color: index == 0 ? theme.accent : theme.surfaceRaised, radius: 12)
        }
        strokeLine(from: NSPoint(x: 0, y: bounds.height - 72), to: NSPoint(x: bounds.width, y: bounds.height - 72), color: theme.border)
        let width = max(1, (bounds.width - 260) / CGFloat(max(1, pages.count)))
        for (index, page) in pages.enumerated() {
            let rect = NSRect(x: 240 + CGFloat(index) * width, y: bounds.height - 58, width: width - 8, height: 28)
            if index == selectedPageIndex { fillRounded(rect, color: theme.accent.withAlphaComponent(0.18), radius: 6) }
            drawText(page.title, in: rect, size: 12, weight: .bold, color: index == selectedPageIndex ? theme.textPrimary : theme.textSecondary, alignment: .center)
        }
        drawText("QuakeKit / (clockString())", in: NSRect(x: 18, y: bounds.height - 28, width: 200, height: 16), size: 11, weight: .medium, color: theme.textSecondary)
    }

    private func drawAmbientMarquee() {
        fill(bounds, color: theme.background)
        let hero = NSRect(x: 0, y: bounds.height - 130, width: bounds.width, height: 130)
        fill(hero, color: theme.surface.withAlphaComponent(0.72))
        drawText(clockString(), in: NSRect(x: 30, y: bounds.height - 100, width: 270, height: 58), size: 48, weight: .thin, color: theme.textPrimary)
        drawText("QUAKEKIT  •  (status.uppercased())", in: NSRect(x: 34, y: bounds.height - 122, width: 420, height: 16), size: 11, weight: .bold, color: theme.accent)
        drawText("Ambient Marquee", in: NSRect(x: bounds.width - 270, y: bounds.height - 94, width: 240, height: 22), size: 16, weight: .bold, color: theme.textPrimary, alignment: .right)
        drawText("Live display companion", in: NSRect(x: bounds.width - 270, y: bounds.height - 117, width: 240, height: 16), size: 11, weight: .medium, color: theme.textSecondary, alignment: .right)
        let dockY: CGFloat = 14
        let width = bounds.width / CGFloat(max(1, pages.count))
        let dockAutohides = menuSettings["ambientMarquee.dockPolicy"]?.stringValue == "autohide"
        for (index, page) in pages.enumerated() {
            let rect = NSRect(x: CGFloat(index) * width + 5, y: dockY, width: width - 10, height: 38)
            if index == selectedPageIndex { fillRounded(rect, color: theme.accent.withAlphaComponent(dockAutohides ? 0.10 : 0.18), radius: 8); strokeRounded(rect, color: theme.accent, radius: 8) }
            drawText(page.title.uppercased(), in: rect.insetBy(dx: 4, dy: 12), size: 10, weight: .bold, color: index == selectedPageIndex ? theme.textPrimary : theme.textSecondary, alignment: .center)
        }
    }

    private func clockString() -> String { DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short) }
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
