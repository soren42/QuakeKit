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
    private let pages = ShellCatalog.defaultPages

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
            let view = PanelView(frame: contentFrame, pages: pages, portraitMode: !launchOptions.debugWindow && frame.height > frame.width)
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
            panelView?.recordConnection(interface)
        case .touch(let points):
            guard let point = points.first(where: { $0.phase == .down }) ?? points.first else { return }
            log("event touch x=\(point.x) y=\(point.y)")
            panelView?.recordTouch(point)
            panelView?.touch(logicalX: CGFloat(point.x), logicalY: CGFloat(point.y))
        case .knob(let event):
            panelView?.recordKnob(event)
            switch event {
            case .rotate(let direction):
                log("event knob rotate \(direction)")
                panelView?.moveSelection(direction > 0 ? -1 : 1)
            case .press(let index):
                log("event knob press \(index)")
                if index == 2 {
                    panelView?.nextPage()
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
            panelView?.recordState(state)
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

struct ShellTile: Equatable {
    var title: String
    var subtitle: String
    var action: ShellAction
}

enum ShellAction: Equatable {
    case openPage(Int)
    case setStatus(String)
}

struct ShellPage: Equatable {
    var title: String
    var kind: Kind
    var tiles: [ShellTile]

    enum Kind: Equatable {
        case grid
        case runtimeStatus
    }
}

struct RuntimeSnapshot: Equatable {
    var controlConnected = false
    var touchConnected = false
    var firmware = "-"
    var mic = "-"
    var luminance = "-"
    var lastTouch = "-"
    var lastKnob = "-"
    var lastPong: Date?
    var eventCount = 0
}

enum ShellCatalog {
    static let defaultPages: [ShellPage] = [
        ShellPage(title: "Home", kind: .grid, tiles: [
            ShellTile(title: "Runtime", subtitle: "Live host status", action: .openPage(1)),
            ShellTile(title: "Plugins", subtitle: "Manifest API", action: .setStatus("Plugin host shell coming next")),
            ShellTile(title: "HID", subtitle: "Control online", action: .openPage(1)),
            ShellTile(title: "Touch", subtitle: "Tap routing", action: .setStatus("Touch routes through focused tiles")),
            ShellTile(title: "Knob", subtitle: "Focus control", action: .setStatus("Knob rotates focus; press activates")),
            ShellTile(title: "Pages", subtitle: "Press page knob", action: .setStatus("Page knob cycles host pages")),
            ShellTile(title: "Data", subtitle: "Provider slots", action: .setStatus("Data providers will feed widgets")),
            ShellTile(title: "Settings", subtitle: "Host config", action: .setStatus("Settings page stub")),
            ShellTile(title: "Actions", subtitle: "Host routed", action: .setStatus("Action router is local for now")),
            ShellTile(title: "Views", subtitle: "Swift/AppKit", action: .setStatus("Native view surface")),
            ShellTile(title: "Dashboards", subtitle: "Future web view", action: .setStatus("Dashboard embedding later")),
            ShellTile(title: "Secrets", subtitle: "Keychain later", action: .setStatus("Secrets belong in Keychain")),
            ShellTile(title: "Metrics", subtitle: "Widget idea", action: .setStatus("Metrics widget slot")),
            ShellTile(title: "Music", subtitle: "Widget idea", action: .setStatus("Music widget slot")),
            ShellTile(title: "HA", subtitle: "Widget idea", action: .setStatus("Home Assistant widget slot")),
            ShellTile(title: "Editor", subtitle: "Layout tools", action: .setStatus("Widget editor will live here"))
        ]),
        ShellPage(title: "Runtime", kind: .runtimeStatus, tiles: [])
    ]
}

final class PanelView: NSView {
    var selectedIndex: Int = 0 {
        didSet { updateSelection() }
    }
    var status: String = "Starting" {
        didSet { updateStatus() }
    }
    private let pages: [ShellPage]
    private let columns = 8
    private let rows = 2
    private let portraitMode: Bool
    private var currentPageIndex = 0
    private var runtime = RuntimeSnapshot()
    private var tileViews: [TileCellView] = []
    private var runtimeRows: [StatusRowView] = []
    private var pageLabels: [NSTextField] = []
    private let statusLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")

    init(frame frameRect: NSRect, pages: [ShellPage], portraitMode: Bool) {
        self.pages = pages
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
        layoutChrome()
        layoutContent()
    }

    func moveSelection(_ delta: Int) {
        let count = currentPage.tiles.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
        status = "Selected \(currentPage.tiles[selectedIndex].title)"
    }

    func activateSelection() {
        guard currentPage.tiles.indices.contains(selectedIndex) else {
            status = "Runtime page active"
            return
        }
        let tile = currentPage.tiles[selectedIndex]
        switch tile.action {
        case .openPage(let index):
            openPage(index)
        case .setStatus(let message):
            status = message
        }
    }

    func touch(logicalX: CGFloat, logicalY: CGFloat) {
        let point = NSPoint(x: logicalX, y: logicalY)
        if let pageIndex = pageLabels.firstIndex(where: { $0.frame.insetBy(dx: -18, dy: -14).contains(point) }) {
            openPage(pageIndex)
            return
        }
        if logicalY > bounds.height - 92, logicalX >= 300 {
            let pageIndex = Int((logicalX - 300) / 140)
            if pages.indices.contains(pageIndex) {
                openPage(pageIndex)
                return
            }
        }

        guard currentPage.kind == .grid else { return }
        if let index = tileViews.firstIndex(where: { $0.frame.contains(point) }), currentPage.tiles.indices.contains(index) {
            selectedIndex = index
            activateSelection()
        }
    }

    func nextPage() {
        openPage((currentPageIndex + 1) % pages.count)
    }

    func recordConnection(_ interface: String) {
        runtime.eventCount += 1
        if interface == "control" { runtime.controlConnected = true }
        if interface == "touch" { runtime.touchConnected = true }
        status = "\(interface) connected"
        updateRuntimeRows()
    }

    func recordTouch(_ point: TouchPoint) {
        runtime.eventCount += 1
        runtime.lastTouch = "\(point.phase.rawValue) x:\(point.x) y:\(point.y)"
        updateRuntimeRows()
    }

    func recordKnob(_ event: KnobEvent) {
        runtime.eventCount += 1
        switch event {
        case .rotate(let direction):
            runtime.lastKnob = "rotate \(direction)"
        case .press(let index):
            runtime.lastKnob = "press \(index)"
        case .holdStart:
            runtime.lastKnob = "hold start"
        case .holdEnd:
            runtime.lastKnob = "hold end"
        }
        updateRuntimeRows()
    }

    func recordState(_ state: DeviceStateEvent) {
        runtime.eventCount += 1
        switch state {
        case .firmware(let name, let version):
            runtime.firmware = "\(name) / \(version)"
        case .mic(let enabled):
            runtime.mic = enabled ? "on" : "off"
        case .luminance(let value):
            runtime.luminance = "\(value)"
        case .pong:
            runtime.lastPong = Date()
        case .stateSync(let busy):
            status = "State sync \(busy ? "busy" : "ready")"
        case .raw(let command, let payload):
            status = "Raw state \(command) (\(payload.count)b)"
        }
        updateStatus()
        updateRuntimeRows()
    }

    private func setupSubviews() {
        titleLabel.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.backgroundColor = .clear
        addSubview(titleLabel)

        pageLabels = pages.enumerated().map { index, page in
            let label = NSTextField(labelWithString: "\(index + 1) \(page.title)")
            label.font = NSFont.monospacedSystemFont(ofSize: 15, weight: .semibold)
            label.textColor = .white
            label.alignment = .center
            label.backgroundColor = .clear
            label.wantsLayer = true
            label.layer?.cornerRadius = 6
            addSubview(label)
            return label
        }

        statusLabel.font = NSFont.monospacedSystemFont(ofSize: 15, weight: .medium)
        statusLabel.textColor = NSColor(calibratedRed: 0.49, green: 1.0, blue: 0.70, alpha: 1)
        statusLabel.backgroundColor = .clear
        statusLabel.lineBreakMode = .byTruncatingTail
        addSubview(statusLabel)
        rebuildPageContent()
    }

    private var currentPage: ShellPage {
        pages[currentPageIndex]
    }

    private func openPage(_ index: Int) {
        guard pages.indices.contains(index) else { return }
        guard currentPageIndex != index else { return }
        currentPageIndex = index
        selectedIndex = 0
        status = "Page \(pages[index].title)"
        log("shell page \(index): \(pages[index].title)")
        rebuildPageContent()
    }

    private func rebuildPageContent() {
        tileViews.forEach { $0.removeFromSuperview() }
        runtimeRows.forEach { $0.removeFromSuperview() }
        tileViews.removeAll()
        runtimeRows.removeAll()

        switch currentPage.kind {
        case .grid:
            tileViews = currentPage.tiles.map { tile in
                let view = TileCellView(tile: tile)
                view.translatesAutoresizingMaskIntoConstraints = true
                addSubview(view)
                return view
            }
        case .runtimeStatus:
            runtimeRows = RuntimeStatusModel.rows(from: runtime).map { row in
                let view = StatusRowView(title: row.title, value: row.value)
                view.translatesAutoresizingMaskIntoConstraints = true
                addSubview(view)
                return view
            }
        }

        updateSelection()
        updateChrome()
        updateStatus()
        needsLayout = true
    }

    private func layoutChrome() {
        let inset: CGFloat = 16
        titleLabel.frame = NSRect(x: inset, y: bounds.height - 46, width: 280, height: 30)
        let tabY = bounds.height - 48
        for (index, label) in pageLabels.enumerated() {
            label.frame = NSRect(x: 320 + CGFloat(index) * 120, y: tabY, width: 104, height: 28)
        }
        statusLabel.frame = NSRect(x: inset + 4, y: 8, width: bounds.width - (inset + 4) * 2, height: 24)
    }

    private func layoutContent() {
        let gap: CGFloat = 10
        let inset: CGFloat = 16
        let topChrome: CGFloat = 62
        let bottomChrome: CGFloat = 38
        let contentRect = NSRect(x: inset, y: bottomChrome, width: bounds.width - inset * 2, height: bounds.height - topChrome - bottomChrome)
        if currentPage.kind == .runtimeStatus {
            layoutRuntimeRows(in: contentRect)
            return
        }
        let gridRect = contentRect
        let usableHeight = gridRect.height
        let tileWidth = (gridRect.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let tileHeight = (usableHeight - gap * CGFloat(rows - 1)) / CGFloat(rows)

        for index in tileViews.indices {
            let column = index % columns
            let row = index / columns
            let x = gridRect.minX + CGFloat(column) * (tileWidth + gap)
            let y = gridRect.maxY - CGFloat(row + 1) * tileHeight - CGFloat(row) * gap
            tileViews[index].frame = NSRect(x: x, y: y, width: tileWidth, height: tileHeight)
        }
    }

    private func layoutRuntimeRows(in rect: NSRect) {
        let gap: CGFloat = 10
        let columns = 4
        let rowHeight = (rect.height - gap * 1) / 2
        let columnWidth = (rect.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
        for index in runtimeRows.indices {
            let column = index % columns
            let row = index / columns
            runtimeRows[index].frame = NSRect(
                x: rect.minX + CGFloat(column) * (columnWidth + gap),
                y: rect.maxY - CGFloat(row + 1) * rowHeight - CGFloat(row) * gap,
                width: columnWidth,
                height: rowHeight
            )
        }
    }

    private func updateSelection() {
        for index in tileViews.indices {
            tileViews[index].isSelected = index == selectedIndex
        }
    }

    private func updateChrome() {
        titleLabel.stringValue = "OpenQuake"
        for (index, label) in pageLabels.enumerated() {
            let active = index == currentPageIndex
            label.layer?.backgroundColor = (active
                ? NSColor(calibratedRed: 0.12, green: 0.25, blue: 0.29, alpha: 1)
                : NSColor(calibratedRed: 0.06, green: 0.075, blue: 0.095, alpha: 1)).cgColor
            label.layer?.borderWidth = active ? 2 : 1
            label.layer?.borderColor = (active
                ? NSColor(calibratedRed: 0.49, green: 1.0, blue: 0.70, alpha: 1)
                : NSColor(calibratedRed: 0.18, green: 0.22, blue: 0.28, alpha: 1)).cgColor
        }
    }

    private func updateStatus() {
        let pong = runtime.lastPong.map { " · pong \(Int(Date().timeIntervalSince($0)))s ago" } ?? ""
        statusLabel.stringValue = "\(currentPage.title) · \(status)\(pong)"
    }

    private func updateRuntimeRows() {
        guard currentPage.kind == .runtimeStatus else { return }
        let rows = RuntimeStatusModel.rows(from: runtime)
        for index in runtimeRows.indices where rows.indices.contains(index) {
            runtimeRows[index].value = rows[index].value
        }
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

enum RuntimeStatusModel {
    static func rows(from snapshot: RuntimeSnapshot) -> [(title: String, value: String)] {
        [
            ("Control", snapshot.controlConnected ? "connected" : "offline"),
            ("Touch", snapshot.touchConnected ? "connected" : "offline"),
            ("Firmware", snapshot.firmware),
            ("Mic", snapshot.mic),
            ("Luminance", snapshot.luminance),
            ("Last touch", snapshot.lastTouch),
            ("Last knob", snapshot.lastKnob),
            ("Events", "\(snapshot.eventCount)")
        ]
    }
}

final class StatusRowView: NSView {
    var value: String {
        didSet {
            valueLabel.stringValue = value
        }
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")

    init(title: String, value: String) {
        self.value = value
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedRed: 0.20, green: 0.25, blue: 0.31, alpha: 1).cgColor
        layer?.backgroundColor = NSColor(calibratedRed: 0.065, green: 0.085, blue: 0.105, alpha: 1).cgColor

        titleLabel.stringValue = title
        titleLabel.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        titleLabel.textColor = NSColor(calibratedRed: 0.68, green: 0.77, blue: 0.86, alpha: 1)
        titleLabel.backgroundColor = .clear

        valueLabel.stringValue = value
        valueLabel.font = NSFont.monospacedSystemFont(ofSize: 24, weight: .semibold)
        valueLabel.textColor = .white
        valueLabel.backgroundColor = .clear
        valueLabel.lineBreakMode = .byTruncatingTail

        addSubview(titleLabel)
        addSubview(valueLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        titleLabel.frame = NSRect(x: 16, y: bounds.height - 40, width: bounds.width - 32, height: 22)
        valueLabel.frame = NSRect(x: 16, y: 24, width: bounds.width - 32, height: 34)
    }
}

final class TileCellView: NSView {
    var isSelected: Bool = false {
        didSet { applyStyle() }
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    init(tile: ShellTile) {
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
