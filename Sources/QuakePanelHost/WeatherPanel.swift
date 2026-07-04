import AppKit
import Foundation
import QuakePluginAPI

struct WeatherForecastDay: Equatable {
    var day: String
    var icon: String
    var condition: String
    var low: Double
    var high: Double
}

struct WeatherHour: Equatable {
    var time: String
    var icon: String
    var temperature: Double
}

struct WeatherLocation: Equatable {
    var name: String
    var latitude: Double
    var longitude: Double
    var temperature: Double
    var high: Double
    var low: Double
    var condition: String
    var icon: String
    var alert: String
    var humidity: Double
    var windMph: Double
    var radarURL: String
    var hourly: [WeatherHour]
    var daily: [WeatherForecastDay]
}

struct WeatherSnapshot: Equatable {
    enum Layout: String {
        case singleFullscreen = "single_fullscreen"
        case twoLocationHalves = "two_location_halves"
        case multiLocationWidgets = "multi_location_widgets"
    }

    var layout: Layout
    var units: String
    var unitSymbol: String
    var forecastDays: Int
    var showRadar: Bool
    var updatedAt: String
    var locations: [WeatherLocation]
    var timestamp: Date?

    init(
        layout: Layout,
        units: String,
        unitSymbol: String,
        forecastDays: Int,
        showRadar: Bool,
        updatedAt: String,
        locations: [WeatherLocation],
        timestamp: Date?
    ) {
        self.layout = layout
        self.units = units
        self.unitSymbol = unitSymbol
        self.forecastDays = forecastDays
        self.showRadar = showRadar
        self.updatedAt = updatedAt
        self.locations = locations
        self.timestamp = timestamp
    }

    static let placeholder = WeatherSnapshot(
        layout: .singleFullscreen,
        units: "fahrenheit",
        unitSymbol: "F",
        forecastDays: 5,
        showRadar: true,
        updatedAt: "-",
        locations: [
            WeatherLocation(
                name: "Charlotte",
                latitude: 35.2271,
                longitude: -80.8431,
                temperature: 81,
                high: 98,
                low: 76,
                condition: "Mostly Cloudy",
                icon: "cloud.fill",
                alert: "Heat Advisory",
                humidity: 64,
                windMph: 7,
                radarURL: "https://open-meteo.com/",
                hourly: [
                    WeatherHour(time: "03", icon: "cloud.moon.fill", temperature: 78),
                    WeatherHour(time: "04", icon: "cloud.fill", temperature: 77),
                    WeatherHour(time: "05", icon: "cloud.fill", temperature: 76),
                    WeatherHour(time: "06", icon: "cloud.fill", temperature: 76),
                    WeatherHour(time: "06:13", icon: "sunrise.fill", temperature: 77),
                    WeatherHour(time: "07", icon: "cloud.fill", temperature: 77)
                ],
                daily: [
                    WeatherForecastDay(day: "Sun", icon: "cloud.bolt.rain.fill", condition: "Storms", low: 76, high: 95),
                    WeatherForecastDay(day: "Mon", icon: "cloud.bolt.rain.fill", condition: "Storms", low: 75, high: 93),
                    WeatherForecastDay(day: "Tue", icon: "cloud.rain.fill", condition: "Rain", low: 74, high: 91),
                    WeatherForecastDay(day: "Wed", icon: "cloud.sun.fill", condition: "Partly Cloudy", low: 74, high: 87),
                    WeatherForecastDay(day: "Thu", icon: "sun.max.fill", condition: "Clear", low: 72, high: 88)
                ]
            )
        ],
        timestamp: nil
    )

    init(value: JSONValue, timestamp: Date) {
        let object = value.objectValue ?? [:]
        self.layout = Layout(rawValue: object["layout"]?.stringValue ?? "") ?? .singleFullscreen
        self.units = object["units"]?.stringValue ?? "fahrenheit"
        self.unitSymbol = object["unitSymbol"]?.stringValue ?? (units == "celsius" ? "C" : "F")
        self.forecastDays = object["forecastDays"]?.integerValue ?? 5
        self.showRadar = object["showRadar"]?.boolValue ?? true
        self.updatedAt = object["updatedAt"]?.stringValue ?? "-"
        self.locations = object["locations"]?.arrayValue?.compactMap(Self.location(from:)) ?? Self.placeholder.locations
        self.timestamp = timestamp
    }

    private static func location(from value: JSONValue) -> WeatherLocation? {
        guard let object = value.objectValue else { return nil }
        return WeatherLocation(
            name: object["name"]?.stringValue ?? object["location"]?.stringValue ?? "Weather",
            latitude: object["latitude"]?.doubleValue ?? 0,
            longitude: object["longitude"]?.doubleValue ?? 0,
            temperature: object["temperature"]?.doubleValue ?? 0,
            high: object["high"]?.doubleValue ?? 0,
            low: object["low"]?.doubleValue ?? 0,
            condition: object["condition"]?.stringValue ?? "Current Conditions",
            icon: object["icon"]?.stringValue ?? "cloud.fill",
            alert: object["alert"]?.stringValue ?? "",
            humidity: object["humidity"]?.doubleValue ?? 0,
            windMph: object["windMph"]?.doubleValue ?? 0,
            radarURL: object["radarURL"]?.stringValue ?? "",
            hourly: object["hourly"]?.arrayValue?.compactMap(hour(from:)) ?? [],
            daily: object["daily"]?.arrayValue?.compactMap(day(from:)) ?? []
        )
    }

    private static func hour(from value: JSONValue) -> WeatherHour? {
        guard let object = value.objectValue else { return nil }
        return WeatherHour(
            time: object["time"]?.stringValue ?? "-",
            icon: object["icon"]?.stringValue ?? "cloud.fill",
            temperature: object["temperature"]?.doubleValue ?? 0
        )
    }

    private static func day(from value: JSONValue) -> WeatherForecastDay? {
        guard let object = value.objectValue else { return nil }
        return WeatherForecastDay(
            day: object["day"]?.stringValue ?? "-",
            icon: object["icon"]?.stringValue ?? "cloud.fill",
            condition: object["condition"]?.stringValue ?? "-",
            low: object["low"]?.doubleValue ?? 0,
            high: object["high"]?.doubleValue ?? 0
        )
    }
}

final class WeatherDashboardView: NSView {
    var snapshot: WeatherSnapshot {
        didSet { needsDisplay = true }
    }
    var theme: PanelTheme {
        didSet { needsDisplay = true }
    }

    init(snapshot: WeatherSnapshot, theme: PanelTheme) {
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
        drawAtmosphericBackground()
        switch snapshot.layout {
        case .singleFullscreen:
            drawSingleFullscreen()
        case .twoLocationHalves:
            drawTwoLocationHalves()
        case .multiLocationWidgets:
            drawMultiLocationWidgets()
        }
    }

    private func drawSingleFullscreen() {
        let gap = theme.spacing
        let currentWidth = bounds.width * 0.32
        let forecastWidth = bounds.width * 0.32
        let mapWidth = bounds.width - currentWidth - forecastWidth - gap * 2
        let current = NSRect(x: 0, y: 0, width: currentWidth, height: bounds.height)
        let forecast = NSRect(x: current.maxX + gap, y: 0, width: forecastWidth, height: bounds.height)
        let radar = NSRect(x: forecast.maxX + gap, y: 0, width: mapWidth, height: bounds.height)
        let location = snapshot.locations.first ?? WeatherSnapshot.placeholder.locations[0]
        drawCurrentCard(location, in: current, compact: false, includeHourly: true)
        drawForecastStack(location, in: forecast, maxDays: 5)
        if snapshot.showRadar {
            drawRadarCard(location, in: radar)
        } else {
            drawForecastStack(location, in: radar, maxDays: 5)
        }
    }

    private func drawTwoLocationHalves() {
        let gap = theme.spacing
        let halfWidth = (bounds.width - gap) / 2
        let first = snapshot.locations.first ?? WeatherSnapshot.placeholder.locations[0]
        let second = snapshot.locations.dropFirst().first ?? first
        drawHalfLocation(first, in: NSRect(x: 0, y: 0, width: halfWidth, height: bounds.height))
        drawHalfLocation(second, in: NSRect(x: halfWidth + gap, y: 0, width: halfWidth, height: bounds.height))
    }

    private func drawMultiLocationWidgets() {
        let gap = theme.spacing
        let columns = 3
        let rows = 1
        let tileWidth = (bounds.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let tileHeight = (bounds.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
        let locations = Array(snapshot.locations.prefix(3))
        for (index, location) in locations.enumerated() {
            let rect = NSRect(x: CGFloat(index) * (tileWidth + gap), y: 0, width: tileWidth, height: tileHeight)
            drawCurrentCard(location, in: rect, compact: true, includeHourly: false)
            drawMiniForecast(location, in: rect.insetBy(dx: 18, dy: 16))
        }
    }

    private func drawHalfLocation(_ location: WeatherLocation, in rect: NSRect) {
        let gap = theme.spacing
        let left = NSRect(x: rect.minX, y: rect.minY, width: rect.width * 0.46, height: rect.height)
        let right = NSRect(x: left.maxX + gap, y: rect.minY, width: rect.width - left.width - gap, height: rect.height)
        drawCurrentCard(location, in: left, compact: true, includeHourly: true)
        drawForecastStack(location, in: right, maxDays: min(5, snapshot.forecastDays))
    }

    private func drawCurrentCard(_ location: WeatherLocation, in rect: NSRect, compact: Bool, includeHourly: Bool) {
        drawGlassCard(in: rect)
        let inset: CGFloat = compact ? 18 : 26
        let top = rect.maxY - inset
        drawText(location.name, in: NSRect(x: rect.minX + inset, y: top - 34, width: rect.width * 0.55, height: 32), size: compact ? 25 : 32, weight: .bold, color: .white)
        drawSymbol(location.icon, in: NSRect(x: rect.maxX - inset - 46, y: top - 40, width: 42, height: 36), size: compact ? 25 : 32, color: .white)
        drawText("\(rounded(location.temperature))°", in: NSRect(x: rect.minX + inset, y: top - (compact ? 94 : 118), width: rect.width * 0.44, height: compact ? 64 : 84), size: compact ? 54 : 76, weight: .light, color: .white)
        drawText(location.condition, in: NSRect(x: rect.midX - 8, y: top - 74, width: rect.width * 0.46, height: 28), size: compact ? 20 : 26, weight: .semibold, color: .white)
        drawText("H:\(rounded(location.high))° L:\(rounded(location.low))°", in: NSRect(x: rect.midX - 8, y: top - 104, width: rect.width * 0.46, height: 24), size: compact ? 17 : 22, weight: .medium, color: .white.withAlphaComponent(0.92))
        let alertY = top - (compact ? 136 : 158)
        strokeLine(y: alertY, in: rect.insetBy(dx: inset, dy: 0))
        drawText(location.alert.isEmpty ? "Humidity \(rounded(location.humidity))% · Wind \(rounded(location.windMph)) mph" : location.alert, in: NSRect(x: rect.minX + inset, y: alertY - 34, width: rect.width - inset * 2, height: 26), size: compact ? 18 : 24, weight: .medium, color: .white)
        strokeLine(y: alertY - 44, in: rect.insetBy(dx: inset, dy: 0))
        if includeHourly {
            drawHourly(location.hourly, in: NSRect(x: rect.minX + inset, y: rect.minY + 18, width: rect.width - inset * 2, height: max(90, alertY - rect.minY - 70)))
        }
    }

    private func drawForecastStack(_ location: WeatherLocation, in rect: NSRect, maxDays: Int) {
        drawGlassCard(in: rect)
        let inset: CGFloat = 20
        drawText("5-DAY FORECAST", in: NSRect(x: rect.minX + inset, y: rect.maxY - 42, width: rect.width - inset * 2, height: 24), size: 17, weight: .bold, color: .white.withAlphaComponent(0.86))
        let days = Array(location.daily.prefix(maxDays))
        let rowHeight = min(70, (rect.height - 70) / CGFloat(max(1, days.count)))
        let lowMin = days.map(\.low).min() ?? 0
        let highMax = days.map(\.high).max() ?? 100
        for (index, day) in days.enumerated() {
            let y = rect.maxY - 70 - CGFloat(index + 1) * rowHeight
            drawDailyRow(day, lowMin: lowMin, highMax: highMax, in: NSRect(x: rect.minX + inset, y: y, width: rect.width - inset * 2, height: rowHeight))
        }
    }

    private func drawMiniForecast(_ location: WeatherLocation, in rect: NSRect) {
        let days = Array(location.daily.prefix(min(3, snapshot.forecastDays)))
        let rowHeight: CGFloat = 34
        let startY = rect.minY + 12
        for (index, day) in days.enumerated() {
            let y = startY + CGFloat(days.count - index - 1) * rowHeight
            drawText(day.day, in: NSRect(x: rect.minX, y: y, width: 52, height: 22), size: 17, weight: .semibold, color: .white)
            drawSymbol(day.icon, in: NSRect(x: rect.minX + 58, y: y - 2, width: 26, height: 24), size: 18, color: iconColor(day.icon))
            drawText("\(rounded(day.low))°", in: NSRect(x: rect.maxX - 116, y: y, width: 44, height: 22), size: 16, weight: .medium, color: .white.withAlphaComponent(0.48))
            drawText("\(rounded(day.high))°", in: NSRect(x: rect.maxX - 50, y: y, width: 48, height: 22), size: 18, weight: .semibold, color: .white)
        }
    }

    private func drawHourly(_ hours: [WeatherHour], in rect: NSRect) {
        let visible = Array(hours.prefix(6))
        guard !visible.isEmpty else { return }
        let width = rect.width / CGFloat(visible.count)
        for (index, hour) in visible.enumerated() {
            let x = rect.minX + CGFloat(index) * width
            drawText(hour.time, in: NSRect(x: x, y: rect.maxY - 22, width: width, height: 18), size: 16, weight: .semibold, color: .white.withAlphaComponent(0.72), alignment: .center)
            drawSymbol(hour.icon, in: NSRect(x: x + width / 2 - 16, y: rect.midY - 12, width: 32, height: 30), size: 23, color: iconColor(hour.icon))
            drawText("\(rounded(hour.temperature))°", in: NSRect(x: x, y: rect.minY + 2, width: width, height: 24), size: 23, weight: .medium, color: .white, alignment: .center)
        }
    }

    private func drawDailyRow(_ day: WeatherForecastDay, lowMin: Double, highMax: Double, in rect: NSRect) {
        strokeLine(y: rect.maxY - 1, in: rect)
        drawText(day.day, in: NSRect(x: rect.minX, y: rect.midY - 13, width: 60, height: 26), size: 24, weight: .semibold, color: .white)
        drawSymbol(day.icon, in: NSRect(x: rect.minX + 80, y: rect.midY - 17, width: 40, height: 34), size: 27, color: iconColor(day.icon))
        drawText("\(rounded(day.low))°", in: NSRect(x: rect.minX + 142, y: rect.midY - 13, width: 54, height: 26), size: 23, weight: .medium, color: .white.withAlphaComponent(0.42))
        drawRangeBar(low: day.low, high: day.high, min: lowMin, max: highMax, in: NSRect(x: rect.minX + 220, y: rect.midY - 4, width: rect.width - 300, height: 9))
        drawText("\(rounded(day.high))°", in: NSRect(x: rect.maxX - 58, y: rect.midY - 13, width: 58, height: 26), size: 24, weight: .semibold, color: .white, alignment: .right)
    }

    private func drawRadarCard(_ location: WeatherLocation, in rect: NSRect) {
        drawGlassCard(in: rect)
        let inset: CGFloat = 22
        drawText("RADAR", in: NSRect(x: rect.minX + inset, y: rect.maxY - 42, width: rect.width - inset * 2, height: 24), size: 18, weight: .bold, color: .white.withAlphaComponent(0.86))
        let map = rect.insetBy(dx: inset, dy: 54)
        let path = NSBezierPath(roundedRect: map, xRadius: 14, yRadius: 14)
        NSColor(calibratedRed: 0.12, green: 0.22, blue: 0.35, alpha: 0.78).setFill()
        path.fill()
        theme.accent.withAlphaComponent(0.24).setStroke()
        path.lineWidth = 1
        path.stroke()

        for step in stride(from: map.minX + 34, through: map.maxX, by: 46) {
            theme.accent.withAlphaComponent(0.10).setStroke()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: step, y: map.minY))
            line.line(to: NSPoint(x: step - 54, y: map.maxY))
            line.lineWidth = 1
            line.stroke()
        }

        let storm = NSBezierPath(ovalIn: NSRect(x: map.midX - 74, y: map.midY - 42, width: 148, height: 84))
        NSColor.systemGreen.withAlphaComponent(0.35).setFill()
        storm.fill()
        NSColor.systemYellow.withAlphaComponent(0.42).setFill()
        NSBezierPath(ovalIn: NSRect(x: map.midX - 28, y: map.midY - 18, width: 66, height: 42)).fill()
        NSColor.systemRed.withAlphaComponent(0.32).setFill()
        NSBezierPath(ovalIn: NSRect(x: map.midX - 2, y: map.midY - 4, width: 30, height: 22)).fill()
        drawText(location.name, in: NSRect(x: map.minX + 16, y: map.minY + 16, width: map.width - 32, height: 28), size: 22, weight: .semibold, color: .white)
        drawText("lat \(String(format: "%.2f", location.latitude)) · lon \(String(format: "%.2f", location.longitude))", in: NSRect(x: map.minX + 16, y: map.minY + 44, width: map.width - 32, height: 20), size: 13, weight: .medium, color: .white.withAlphaComponent(0.70))
    }

    private func drawAtmosphericBackground() {
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.23, alpha: 1),
            NSColor(calibratedRed: 0.06, green: 0.11, blue: 0.24, alpha: 1),
            NSColor(calibratedRed: 0.04, green: 0.07, blue: 0.13, alpha: 1)
        ])
        gradient?.draw(in: bounds, angle: -12)
    }

    private func drawGlassCard(in rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 26, yRadius: 26)
        NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.18, alpha: 0.88).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.28).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawRangeBar(low: Double, high: Double, min minimum: Double, max maximum: Double, in rect: NSRect) {
        let denominator = maximum == minimum ? 1 : maximum - minimum
        let start = rect.minX + rect.width * CGFloat((low - minimum) / denominator)
        let end = rect.minX + rect.width * CGFloat((high - minimum) / denominator)
        NSColor.black.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
        let fillRect = NSRect(x: Swift.min(start, end), y: rect.minY, width: Swift.max(8, abs(end - start)), height: rect.height)
        NSGradient(colors: [NSColor.systemYellow, NSColor.systemOrange, NSColor.systemRed])?.draw(in: NSBezierPath(roundedRect: fillRect, xRadius: rect.height / 2, yRadius: rect.height / 2), angle: 0)
    }

    private func strokeLine(y: CGFloat, in rect: NSRect) {
        NSColor.white.withAlphaComponent(0.28).setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: y))
        path.line(to: NSPoint(x: rect.maxX, y: y))
        path.lineWidth = 1
        path.stroke()
    }

    private func drawSymbol(_ name: String, in rect: NSRect, size: CGFloat, color: NSColor) {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
        let tinted = NSImage(size: image.size)
        tinted.lockFocus()
        image.draw(at: .zero, from: NSRect(origin: .zero, size: image.size), operation: .sourceOver, fraction: 1)
        color.setFill()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.draw(in: rect, from: NSRect(origin: .zero, size: tinted.size), operation: .sourceOver, fraction: 1)
    }

    private func iconColor(_ icon: String) -> NSColor {
        if icon.contains("sun") || icon.contains("sunrise") { return NSColor.systemYellow }
        if icon.contains("bolt") { return NSColor.systemCyan }
        if icon.contains("rain") || icon.contains("drizzle") { return NSColor.systemTeal }
        return .white
    }

    private func drawText(
        _ text: String,
        in rect: NSRect,
        size: CGFloat,
        weight: NSFont.Weight,
        color: NSColor,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = alignment
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        NSAttributedString(string: text, attributes: attributes).draw(in: rect)
    }

    private func rounded(_ value: Double) -> String {
        String(format: "%.0f", value)
    }
}
