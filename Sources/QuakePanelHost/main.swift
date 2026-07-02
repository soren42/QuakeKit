import AppKit
import Foundation
import QuakeHID
import QuakeRuntime

func log(_ message: String) {
    fputs("[quake-panel] \(message)\n", stderr)
}

let launchOptions = PanelLaunchOptions(arguments: CommandLine.arguments.dropFirst())
let app = NSApplication.shared
let delegate = PanelAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

struct PanelLaunchOptions {
    var debugWindow: Bool
    var displayTest: Bool
    var mainScreen: Bool
    var noHID: Bool

    init(arguments: ArraySlice<String>) {
        let values = Set(arguments)
        self.debugWindow = values.contains("--debug-window")
        self.displayTest = values.contains("--display-test")
        self.mainScreen = values.contains("--main-screen")
        self.noHID = values.contains("--no-hid")
    }
}

@MainActor
final class PanelAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var panelView: PanelView?
    private var testView: DisplayTestView?
    private var device: QuakeDevice?
    private let tiles = DemoTiles.defaultTiles

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("applicationDidFinishLaunching debugWindow=\(launchOptions.debugWindow) displayTest=\(launchOptions.displayTest) mainScreen=\(launchOptions.mainScreen) noHID=\(launchOptions.noHID)")
        NSApp.activate(ignoringOtherApps: true)
        openPanelWindow()
        if launchOptions.noHID {
            panelView?.status = "Display debug, HID disabled"
        } else {
            startDevice()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        device?.stop()
    }

    private func openPanelWindow() {
        for (index, screen) in NSScreen.screens.enumerated() {
            log("screen[\(index)] frame=\(format(screen.frame)) visible=\(format(screen.visibleFrame)) quakeLike=\(DisplayLocator.isQuakeLike(screen.frame.size))")
        }
        let targetScreen = launchOptions.mainScreen ? NSScreen.main : (DisplayLocator.quakeScreen() ?? NSScreen.main)
        let frame = targetScreen?.frame ?? NSRect(x: 80, y: 80, width: 960, height: 240)
        let quakeLike = !launchOptions.mainScreen && DisplayLocator.isQuakeLike(frame.size)
        let logicalSize: NSSize
        if launchOptions.displayTest {
            logicalSize = frame.size
        } else if launchOptions.debugWindow {
            logicalSize = NSSize(width: min(1280, max(640, frame.width - 80)), height: min(360, max(240, frame.height - 80)))
        } else {
            logicalSize = quakeLike ? frame.size : NSSize(width: 960, height: 240)
        }
        let origin: NSPoint
        if launchOptions.displayTest {
            origin = frame.origin
        } else if launchOptions.debugWindow {
            origin = NSPoint(x: frame.minX + 40, y: frame.minY + max(20, (frame.height - logicalSize.height) / 2))
        } else {
            origin = quakeLike ? frame.origin : NSPoint(x: frame.midX - logicalSize.width / 2, y: frame.midY - logicalSize.height / 2)
        }
        let rect = NSRect(origin: origin, size: logicalSize)
        log("target frame=\(format(frame)) window rect=\(format(rect))")

        let contentFrame = NSRect(origin: .zero, size: logicalSize)
        let panelContentView: NSView
        if launchOptions.displayTest {
            let view = DisplayTestView(frame: contentFrame)
            panelContentView = view
            testView = view
        } else {
            let view = PanelView(frame: contentFrame, tiles: tiles, portraitMode: !launchOptions.debugWindow && frame.height > frame.width)
            panelContentView = view
            panelView = view
        }

        let style: NSWindow.StyleMask = launchOptions.displayTest || (!launchOptions.debugWindow && quakeLike)
            ? [.borderless]
            : [.titled, .closable, .miniaturizable, .resizable]
        let panelWindow = NSWindow(
            contentRect: contentFrame,
            styleMask: style,
            backing: .buffered,
            defer: false,
            screen: targetScreen
        )
        panelWindow.title = "OpenQuake Panel"
        panelWindow.backgroundColor = .black
        panelWindow.isOpaque = true
        panelWindow.contentView = panelContentView
        panelWindow.setFrame(rect, display: true)
        panelWindow.makeKeyAndOrderFront(nil)
        panelWindow.orderFrontRegardless()
        if launchOptions.displayTest {
            panelWindow.level = .screenSaver
            panelWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        } else if quakeLike && !launchOptions.debugWindow {
            panelWindow.level = .floating
            panelWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        } else {
            panelWindow.level = .normal
        }
        panelContentView.needsDisplay = true
        panelContentView.displayIfNeeded()
        log("window visible=\(panelWindow.isVisible) frame=\(format(panelWindow.frame)) content=\(format(panelContentView.frame)) level=\(panelWindow.level.rawValue)")

        self.window = panelWindow
    }

    private func startDevice() {
        let deliver: @MainActor (RuntimeEvent) -> Void = { [weak self] event in
            self?.handle(event)
        }
        let quake = QuakeDevice { [weak self] event in
            Task { @MainActor in
                if self != nil {
                    deliver(event)
                }
            }
        }
        do {
            try quake.start(wake: true)
            for diagnostic in quake.diagnostics {
                log("hid \(diagnostic)")
            }
            device = quake
            panelView?.status = "HID connected"
        } catch {
            log("hid unavailable: \(error)")
            panelView?.status = "HID unavailable: \(error)"
        }
    }

    private func handle(_ runtimeEvent: RuntimeEvent) {
        switch runtimeEvent.event {
        case .connected(let interface):
            log("event connected \(interface)")
            panelView?.status = "\(interface) connected"
        case .touch(let points):
            guard let point = points.first(where: { $0.phase == .down }) ?? points.first else { return }
            log("event touch x=\(point.x) y=\(point.y)")
            panelView?.touch(logicalX: CGFloat(point.x), logicalY: CGFloat(480 - point.y))
        case .knob(let event):
            switch event {
            case .rotate(let direction):
                log("event knob rotate \(direction)")
                panelView?.moveSelection(direction > 0 ? -1 : 1)
            case .press(let index):
                log("event knob press \(index)")
                if index == 2 {
                    panelView?.status = "Page selector will live here"
                } else {
                    panelView?.activateSelection()
                }
            case .holdStart:
                log("event knob hold start")
                panelView?.status = "Hold started"
            case .holdEnd:
                log("event knob hold end")
                panelView?.status = "Hold ended"
            }
        case .state(let state):
            log("event state \(state)")
            if case .pong = state {
                panelView?.lastPong = Date()
            }
        default:
            break
        }
    }
}

func format(_ rect: NSRect) -> String {
    "x:\(Int(rect.origin.x)) y:\(Int(rect.origin.y)) w:\(Int(rect.size.width)) h:\(Int(rect.size.height))"
}

enum DisplayLocator {
    static func quakeScreen() -> NSScreen? {
        NSScreen.screens.first { isQuakeLike($0.frame.size) }
    }

    static func isQuakeLike(_ size: NSSize) -> Bool {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        return (width == 1920 && height == 480) || (width == 480 && height == 1920)
    }
}

struct DemoTile: Equatable {
    var title: String
    var subtitle: String
}

enum DemoTiles {
    static let defaultTiles: [DemoTile] = [
        DemoTile(title: "Runtime", subtitle: "Event bus"),
        DemoTile(title: "Plugins", subtitle: "Manifest API"),
        DemoTile(title: "HID", subtitle: "Control online"),
        DemoTile(title: "Touch", subtitle: "Awaiting input"),
        DemoTile(title: "Knob", subtitle: "Rotate/press"),
        DemoTile(title: "Pages", subtitle: "Native grid"),
        DemoTile(title: "Data", subtitle: "Providers"),
        DemoTile(title: "Settings", subtitle: "Soon"),
        DemoTile(title: "Actions", subtitle: "Host routed"),
        DemoTile(title: "Views", subtitle: "Swift/AppKit"),
        DemoTile(title: "Dashboards", subtitle: "WKWebView later"),
        DemoTile(title: "Secrets", subtitle: "Keychain later"),
        DemoTile(title: "Metrics", subtitle: "Plugin later"),
        DemoTile(title: "Music", subtitle: "Plugin later"),
        DemoTile(title: "HA", subtitle: "Plugin later"),
        DemoTile(title: "Editor", subtitle: "Next phase")
    ]
}

final class PanelView: NSView {
    var selectedIndex: Int = 0 {
        didSet { updateSelection() }
    }
    var status: String = "Starting" {
        didSet { updateStatus() }
    }
    var lastPong: Date? {
        didSet { updateStatus() }
    }

    private let tiles: [DemoTile]
    private let columns = 8
    private let rows = 2
    private let portraitMode: Bool
    private var tileViews: [TileCellView] = []
    private let statusLabel = NSTextField(labelWithString: "")

    init(frame frameRect: NSRect, tiles: [DemoTile], portraitMode: Bool) {
        self.tiles = tiles
        self.portraitMode = portraitMode
        super.init(frame: frameRect)
        wantsLayer = true
        autoresizingMask = [.width, .height]
        layer?.backgroundColor = NSColor(calibratedRed: 0.02, green: 0.05, blue: 0.07, alpha: 1).cgColor
        log("PanelView init frame=\(format(frameRect)) portraitMode=\(portraitMode)")
        setupSubviews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        layoutTiles()
    }

    func moveSelection(_ delta: Int) {
        selectedIndex = (selectedIndex + delta + tiles.count) % tiles.count
        status = "Selected \(tiles[selectedIndex].title)"
    }

    func activateSelection() {
        status = "Activated \(tiles[selectedIndex].title)"
    }

    func touch(logicalX: CGFloat, logicalY: CGFloat) {
        let clampedX = max(0, min(1919, logicalX))
        let clampedY = max(0, min(479, logicalY))
        let column = min(columns - 1, max(0, Int(clampedX / (1920 / CGFloat(columns)))))
        let row = min(rows - 1, max(0, Int(clampedY / (480 / CGFloat(rows)))))
        let index = row * columns + column
        if tiles.indices.contains(index) {
            selectedIndex = index
            activateSelection()
        }
    }

    private func setupSubviews() {
        tileViews = tiles.enumerated().map { index, tile in
            let view = TileCellView(tile: tile)
            view.translatesAutoresizingMaskIntoConstraints = true
            addSubview(view)
            return view
        }

        statusLabel.font = NSFont.monospacedSystemFont(ofSize: 15, weight: .medium)
        statusLabel.textColor = NSColor(calibratedRed: 0.49, green: 1.0, blue: 0.70, alpha: 1)
        statusLabel.backgroundColor = .clear
        statusLabel.lineBreakMode = .byTruncatingTail
        addSubview(statusLabel)
        updateSelection()
        updateStatus()
    }

    private func layoutTiles() {
        let gap: CGFloat = 10
        let inset: CGFloat = 14
        let statusHeight: CGFloat = 30
        let gridRect = bounds.insetBy(dx: inset, dy: inset).offsetBy(dx: 0, dy: statusHeight / 2)
        let usableHeight = gridRect.height - statusHeight
        let tileWidth = (gridRect.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let tileHeight = (usableHeight - gap * CGFloat(rows - 1)) / CGFloat(rows)

        for index in tileViews.indices {
            let column = index % columns
            let row = index / columns
            let x = gridRect.minX + CGFloat(column) * (tileWidth + gap)
            let y = gridRect.maxY - CGFloat(row + 1) * tileHeight - CGFloat(row) * gap
            tileViews[index].frame = NSRect(x: x, y: y, width: tileWidth, height: tileHeight)
        }
        statusLabel.frame = NSRect(x: inset + 4, y: 6, width: bounds.width - (inset + 4) * 2, height: 24)
    }

    private func updateSelection() {
        for index in tileViews.indices {
            tileViews[index].isSelected = index == selectedIndex
        }
    }

    private func updateStatus() {
        let pong = lastPong.map { " · pong \(Int(Date().timeIntervalSince($0)))s ago" } ?? ""
        statusLabel.stringValue = "OpenQuake Native · \(status)\(pong)"
    }
}

final class DisplayTestView: NSView {
    private let colors: [NSColor] = [.red, .green, .blue, .white, .black, .magenta, .cyan, .yellow]
    private var phase = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        autoresizingMask = [.width, .height]
        Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.advancePhase()
            }
        }
        log("DisplayTestView init frame=\(format(frameRect))")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let background = colors[phase % colors.count]
        background.setFill()
        bounds.fill()

        drawEdgeMarkers()
        drawBands()
        drawLabel()
    }

    private func advancePhase() {
        phase += 1
        needsDisplay = true
    }

    private func drawEdgeMarkers() {
        NSColor.black.withAlphaComponent(0.45).setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 8, dy: 8))
        border.lineWidth = 16
        border.stroke()

        NSColor.white.setStroke()
        let inner = NSBezierPath(rect: bounds.insetBy(dx: 26, dy: 26))
        inner.lineWidth = 4
        inner.stroke()
    }

    private func drawBands() {
        let bandWidth = max(1, bounds.width / CGFloat(colors.count))
        for (index, color) in colors.enumerated() {
            color.setFill()
            NSRect(x: CGFloat(index) * bandWidth, y: 0, width: bandWidth, height: 42).fill()
            NSRect(x: CGFloat(index) * bandWidth, y: bounds.height - 42, width: bandWidth, height: 42).fill()
        }
    }

    private func drawLabel() {
        let text = "OPENQUAKE DISPLAY TEST \(phase)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 54, weight: .black),
            .foregroundColor: NSColor.white,
            .strokeColor: NSColor.black,
            .strokeWidth: -4
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributed.size()
        let textRect = NSRect(
            x: max(20, bounds.midX - textSize.width / 2),
            y: max(64, bounds.midY - textSize.height / 2),
            width: min(textSize.width, bounds.width - 40),
            height: textSize.height
        )
        attributed.draw(in: textRect)
    }
}

final class TileCellView: NSView {
    var isSelected: Bool = false {
        didSet { applyStyle() }
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    init(tile: DemoTile) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1

        titleLabel.stringValue = tile.title
        titleLabel.font = NSFont.systemFont(ofSize: 25, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.backgroundColor = .clear

        subtitleLabel.stringValue = tile.subtitle
        subtitleLabel.font = NSFont.systemFont(ofSize: 16, weight: .regular)
        subtitleLabel.textColor = NSColor(calibratedRed: 0.68, green: 0.77, blue: 0.86, alpha: 1)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.backgroundColor = .clear

        addSubview(titleLabel)
        addSubview(subtitleLabel)
        applyStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        titleLabel.frame = NSRect(x: 14, y: bounds.height - 62, width: bounds.width - 28, height: 34)
        subtitleLabel.frame = NSRect(x: 14, y: 18, width: bounds.width - 28, height: 24)
    }

    private func applyStyle() {
        layer?.backgroundColor = (isSelected
            ? NSColor(calibratedRed: 0.12, green: 0.24, blue: 0.28, alpha: 1)
            : NSColor(calibratedRed: 0.075, green: 0.095, blue: 0.125, alpha: 1)).cgColor
        layer?.borderColor = (isSelected
            ? NSColor(calibratedRed: 0.49, green: 1.0, blue: 0.70, alpha: 1)
            : NSColor(calibratedRed: 0.20, green: 0.25, blue: 0.31, alpha: 1)).cgColor
        layer?.borderWidth = isSelected ? 3 : 1
    }
}
