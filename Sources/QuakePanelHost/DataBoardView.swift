import AppKit
import Foundation
import QuakePluginAPI

struct DataBoardItem: Equatable {
    var title: String
    var value: String
    var detail: String
    var positive: Bool?
}

struct DataBoardSnapshot: Equatable {
    var title: String
    var subtitle: String
    var items: [DataBoardItem]
    var timestamp: Date?

    init(pluginName: String, viewTitle: String, value: JSONValue?, timestamp: Date?) {
        self.title = viewTitle
        self.timestamp = timestamp
        guard let value else {
            self.subtitle = pluginName
            self.items = [DataBoardItem(title: "No Data", value: "-", detail: "Run refresh action", positive: nil)]
            return
        }
        let rows = Self.rows(from: value)
        self.subtitle = Self.subtitle(from: value, fallback: pluginName)
        self.items = rows.isEmpty ? [DataBoardItem(title: pluginName, value: "Ready", detail: "No fields returned", positive: nil)] : rows
    }

    private static func subtitle(from value: JSONValue, fallback: String) -> String {
        guard let object = value.objectValue else { return fallback }
        if let source = object["source"]?.stringValue {
            return "\(fallback) · \(source)"
        }
        if let status = object["status"]?.stringValue {
            return "\(fallback) · \(status)"
        }
        return fallback
    }

    private static func rows(from value: JSONValue) -> [DataBoardItem] {
        guard let object = value.objectValue else {
            return [DataBoardItem(title: "Value", value: display(value), detail: "", positive: nil)]
        }
        if let symbols = object["symbols"]?.arrayValue {
            return symbols.prefix(8).compactMap { row in
                guard let item = row.objectValue else { return nil }
                let symbol = item["symbol"]?.stringValue ?? "Ticker"
                let price = item["price"].map(display) ?? "-"
                let change = item["change"]?.doubleValue ?? 0
                return DataBoardItem(title: symbol, value: price, detail: change >= 0 ? "+\(format(change))" : format(change), positive: change >= 0)
            }
        }
        if let games = object["games"]?.arrayValue {
            return games.prefix(8).compactMap { row in
                guard let item = row.objectValue else { return nil }
                let matchup = item["matchup"]?.stringValue ?? [item["away"]?.stringValue, item["home"]?.stringValue].compactMap { $0 }.joined(separator: " @ ")
                return DataBoardItem(
                    title: item["league"]?.stringValue?.uppercased() ?? "Game",
                    value: matchup.isEmpty ? "Scheduled" : matchup,
                    detail: item["status"]?.stringValue ?? item["score"]?.stringValue ?? "-",
                    positive: nil
                )
            }
        }
        if let devices = object["devices"]?.arrayValue {
            return devices.prefix(8).compactMap { row in
                guard let item = row.objectValue else { return nil }
                let state = item["state"]?.stringValue ?? item["status"]?.stringValue ?? "-"
                return DataBoardItem(title: item["name"]?.stringValue ?? "Device", value: state, detail: item["detail"]?.stringValue ?? "", positive: state.lowercased().contains("online"))
            }
        }
        if let rows = object["rows"]?.arrayValue {
            return rows.prefix(8).compactMap { row in
                guard let item = row.objectValue else { return nil }
                return DataBoardItem(title: item["title"]?.stringValue ?? "Item", value: item["value"].map(display) ?? "-", detail: item["detail"]?.stringValue ?? "", positive: item["positive"]?.boolValue)
            }
        }
        return object.keys.sorted().prefix(8).map { key in
            DataBoardItem(title: titleize(key), value: display(object[key] ?? .null), detail: "", positive: nil)
        }
    }

    private static func display(_ value: JSONValue) -> String {
        switch value {
        case .string(let value):
            return value
        case .integer(let value):
            return "\(value)"
        case .double(let value):
            return format(value)
        case .bool(let value):
            return value ? "on" : "off"
        case .null:
            return "-"
        case .array(let values):
            return "\(values.count)"
        case .object(let object):
            return "\(object.count)"
        }
    }

    private static func format(_ value: Double) -> String {
        abs(value) >= 100 ? String(format: "%.0f", value) : String(format: "%.2f", value)
    }

    private static func titleize(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

final class DataBoardView: NSView {
    var snapshot: DataBoardSnapshot {
        didSet { needsDisplay = true }
    }
    var theme: PanelTheme {
        didSet { needsDisplay = true }
    }

    init(snapshot: DataBoardSnapshot, theme: PanelTheme) {
        self.snapshot = snapshot
        self.theme = theme
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        theme.background.setFill()
        bounds.fill()
        drawHeader()
        drawCards()
    }

    private func drawHeader() {
        drawText(snapshot.title.uppercased(), in: NSRect(x: 0, y: bounds.height - 42, width: bounds.width * 0.42, height: 34), size: 27, weight: .black, color: theme.accent)
        drawText(snapshot.subtitle, in: NSRect(x: bounds.width * 0.43, y: bounds.height - 34, width: bounds.width * 0.42, height: 22), size: 16, weight: .semibold, color: theme.textSecondary, alignment: .right)
        if let timestamp = snapshot.timestamp {
            drawText(relative(timestamp), in: NSRect(x: bounds.width - 130, y: bounds.height - 34, width: 130, height: 22), size: 13, weight: .medium, color: theme.textSecondary, alignment: .right)
        }
    }

    private func drawCards() {
        let top: CGFloat = 54
        let gap = theme.spacing
        let rect = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - top)
        let columns = snapshot.items.count <= 4 ? max(1, snapshot.items.count) : 4
        let rows = Int(ceil(Double(snapshot.items.count) / Double(columns)))
        let cardWidth = (rect.width - gap * CGFloat(max(0, columns - 1))) / CGFloat(columns)
        let cardHeight = min(150, (rect.height - gap * CGFloat(max(0, rows - 1))) / CGFloat(max(1, rows)))
        for (index, item) in snapshot.items.enumerated() {
            let column = index % columns
            let row = index / columns
            let card = NSRect(
                x: rect.minX + CGFloat(column) * (cardWidth + gap),
                y: rect.maxY - CGFloat(row + 1) * cardHeight - CGFloat(row) * gap,
                width: cardWidth,
                height: cardHeight
            )
            drawCard(item, in: card)
        }
    }

    private func drawCard(_ item: DataBoardItem, in rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: theme.cornerRadius, yRadius: theme.cornerRadius)
        theme.surface.withAlphaComponent(0.82).setFill()
        path.fill()
        (item.positive == true ? theme.success : item.positive == false ? theme.danger : theme.border).setStroke()
        path.lineWidth = max(1, theme.borderWidth)
        path.stroke()
        drawText(item.title, in: NSRect(x: rect.minX + 14, y: rect.maxY - 32, width: rect.width - 28, height: 20), size: 15, weight: .bold, color: theme.textSecondary)
        drawText(item.value, in: NSRect(x: rect.minX + 14, y: rect.midY - 4, width: rect.width - 28, height: 36), size: 28, weight: .black, color: theme.textPrimary)
        drawText(item.detail, in: NSRect(x: rect.minX + 14, y: rect.minY + 14, width: rect.width - 28, height: 20), size: 15, weight: .semibold, color: item.positive == true ? theme.success : item.positive == false ? theme.danger : theme.accent)
    }

    private func drawText(_ text: String, in rect: NSRect, size: CGFloat, weight: NSFont.Weight, color: NSColor, alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = alignment
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]).draw(in: rect)
    }

    private func relative(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        return seconds < 60 ? "\(seconds)s ago" : "\(seconds / 60)m ago"
    }
}
