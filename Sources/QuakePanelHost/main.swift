import AppKit
import Foundation
import QuakeHID
import QuakePluginAPI
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
    private let pluginPackages = PanelPluginLoader.loadSamplePackages()
    private let themePackages = PanelThemeLoader.loadSamplePackages()
    private lazy var pages = ShellCatalog.defaultPages(pluginPackages: pluginPackages, themePackages: themePackages)

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
            let view = PanelView(frame: contentFrame, pages: pages, themePackages: themePackages, portraitMode: !launchOptions.debugWindow && frame.height > frame.width)
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
        panelWindow.title = "QuakeKit Panel"
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

enum PanelPluginLoader {
    static func loadSamplePackages() -> [PluginPackage] {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let directory = root.appendingPathComponent("Examples/Plugins", isDirectory: true)
        let results = PluginPackageLoader.loadPackages(from: directory)
        var packages: [PluginPackage] = []

        for result in results {
            switch result {
            case .success(let package, let warnings):
                packages.append(package)
                log("plugin loaded \(package.manifest.id) views=\(package.manifest.views.count)")
                for warning in warnings {
                    log("plugin warning \(package.manifest.id): \(warning)")
                }
            case .failure(let url, let errors):
                log("plugin failed \(url.lastPathComponent): \(errors.joined(separator: "; "))")
            }
        }

        return packages
    }
}

enum PanelThemeLoader {
    static func loadSamplePackages() -> [ThemePackage] {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let directory = root.appendingPathComponent("Examples/Themes", isDirectory: true)
        let results = ThemePackageLoader.loadPackages(from: directory)
        var packages: [ThemePackage] = []

        for result in results {
            switch result {
            case .success(let package, let warnings):
                packages.append(package)
                log("theme loaded \(package.manifest.id) colors=\(package.manifest.palette.colors.count)")
                for warning in warnings {
                    log("theme warning \(package.manifest.id): \(warning)")
                }
            case .failure(let url, let errors):
                log("theme failed \(url.lastPathComponent): \(errors.joined(separator: "; "))")
            }
        }

        return packages
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
    case selectTheme(Int)
    case cycleAccent
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

struct PanelTheme: Equatable {
    var name: String
    var background: NSColor
    var surface: NSColor
    var surfaceRaised: NSColor
    var border: NSColor
    var textPrimary: NSColor
    var textSecondary: NSColor
    var accent: NSColor
    var success: NSColor
    var warning: NSColor
    var danger: NSColor
    var cornerRadius: CGFloat
    var borderWidth: CGFloat
    var spacing: CGFloat

    static let fallback = PanelTheme(
        name: "Fallback",
        background: NSColor(calibratedRed: 0.02, green: 0.05, blue: 0.07, alpha: 1),
        surface: NSColor(calibratedRed: 0.075, green: 0.095, blue: 0.125, alpha: 1),
        surfaceRaised: NSColor(calibratedRed: 0.12, green: 0.24, blue: 0.28, alpha: 1),
        border: NSColor(calibratedRed: 0.20, green: 0.25, blue: 0.31, alpha: 1),
        textPrimary: .white,
        textSecondary: NSColor(calibratedRed: 0.68, green: 0.77, blue: 0.86, alpha: 1),
        accent: NSColor(calibratedRed: 0.49, green: 1.0, blue: 0.70, alpha: 1),
        success: NSColor(calibratedRed: 0.42, green: 1.0, blue: 0.56, alpha: 1),
        warning: NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.40, alpha: 1),
        danger: NSColor(calibratedRed: 1.0, green: 0.36, blue: 0.48, alpha: 1),
        cornerRadius: 8,
        borderWidth: 1,
        spacing: 10
    )

    static func from(_ manifest: ThemeManifest) -> PanelTheme {
        let palette = manifest.palette
        let semantic = palette.semanticColors
        let fallback = PanelTheme.fallback

        func color(_ reference: String?, _ fallbackColor: NSColor) -> NSColor {
            guard let reference else { return fallbackColor }
            if let direct = NSColor(hex: reference) {
                return direct
            }
            if let token = palette.colors[reference], let tokenColor = NSColor(hex: token.value) {
                return tokenColor
            }
            return fallbackColor
        }

        return PanelTheme(
            name: manifest.name,
            background: color(semantic?.background, fallback.background),
            surface: color(semantic?.surface, fallback.surface),
            surfaceRaised: color(semantic?.surfaceRaised, fallback.surfaceRaised),
            border: color(semantic?.border, fallback.border),
            textPrimary: color(semantic?.textPrimary, fallback.textPrimary),
            textSecondary: color(semantic?.textSecondary, fallback.textSecondary),
            accent: color(semantic?.accent, fallback.accent),
            success: color(semantic?.success, fallback.success),
            warning: color(semantic?.warning, fallback.warning),
            danger: color(semantic?.danger, fallback.danger),
            cornerRadius: CGFloat(manifest.metrics?.cornerRadius ?? Double(fallback.cornerRadius)),
            borderWidth: CGFloat(manifest.metrics?.borderWidth ?? Double(fallback.borderWidth)),
            spacing: CGFloat(manifest.metrics?.spacing ?? Double(fallback.spacing))
        )
    }

    func withAccent(_ accent: NSColor) -> PanelTheme {
        var copy = self
        copy.accent = accent
        return copy
    }
}

extension NSColor {
    convenience init?(hex: String) {
        guard hex.hasPrefix("#") else { return nil }
        let body = String(hex.dropFirst())
        guard body.count == 6 || body.count == 8, let value = UInt64(body, radix: 16) else { return nil }
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
        if body.count == 8 {
            red = CGFloat((value & 0xFF00_0000) >> 24) / 255
            green = CGFloat((value & 0x00FF_0000) >> 16) / 255
            blue = CGFloat((value & 0x0000_FF00) >> 8) / 255
            alpha = CGFloat(value & 0x0000_00FF) / 255
        } else {
            red = CGFloat((value & 0xFF0000) >> 16) / 255
            green = CGFloat((value & 0x00FF00) >> 8) / 255
            blue = CGFloat(value & 0x0000FF) / 255
            alpha = 1
        }
        self.init(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }
}

enum ShellCatalog {
    static func defaultPages(pluginPackages: [PluginPackage], themePackages: [ThemePackage]) -> [ShellPage] {
        let widgetTiles = pluginTiles(
            from: pluginPackages,
            presentationFilter: { $0 == .widget || $0 == .pageAndWidget },
            emptyTitle: "No Widgets",
            emptySubtitle: "Add plugin views"
        )
        let appTiles = pluginTiles(
            from: pluginPackages,
            presentationFilter: { $0 == .page || $0 == .pageAndWidget },
            emptyTitle: "No Apps",
            emptySubtitle: "Add full-page views"
        )
        let themeTiles = themeTiles(from: themePackages)

        return [
            ShellPage(title: "Home", kind: .grid, tiles: [
            ShellTile(title: "Runtime", subtitle: "Live host status", action: .openPage(4)),
            ShellTile(title: "Widgets", subtitle: "\(widgetTiles.count) compact views", action: .openPage(1)),
            ShellTile(title: "Apps", subtitle: "\(appTiles.count) full pages", action: .openPage(2)),
            ShellTile(title: "Themes", subtitle: "\(themePackages.count) installed", action: .openPage(3)),
            ShellTile(title: "HID", subtitle: "Control online", action: .openPage(4)),
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
            ShellPage(title: "Widgets", kind: .grid, tiles: widgetTiles),
            ShellPage(title: "Apps", kind: .grid, tiles: appTiles),
            ShellPage(title: "Themes", kind: .grid, tiles: themeTiles),
            ShellPage(title: "Runtime", kind: .runtimeStatus, tiles: [])
        ]
    }

    private static func pluginTiles(
        from packages: [PluginPackage],
        presentationFilter: (PluginView.Presentation) -> Bool,
        emptyTitle: String,
        emptySubtitle: String
    ) -> [ShellTile] {
        let tiles = packages.flatMap { package in
            package.manifest.views.compactMap { view -> ShellTile? in
                let presentation = view.presentation ?? .page
                guard presentationFilter(presentation) else { return nil }
                let type = view.type?.rawValue ?? package.manifest.entry.transport.rawValue
                return ShellTile(
                    title: view.title,
                    subtitle: "\(package.manifest.name) · \(type)",
                    action: .setStatus("\(package.manifest.name): \(view.title)")
                )
            }
        }

        if !tiles.isEmpty {
            return tiles
        }

        return [
            ShellTile(title: emptyTitle, subtitle: emptySubtitle, action: .setStatus(emptySubtitle))
        ]
    }

    private static func themeTiles(from packages: [ThemePackage]) -> [ShellTile] {
        var tiles = packages.enumerated().map { index, package in
            ShellTile(
                title: package.manifest.name,
                subtitle: package.manifest.description ?? package.manifest.id,
                action: .selectTheme(index)
            )
        }

        tiles.append(ShellTile(
            title: "Accent",
            subtitle: "Cycle test colors",
            action: .cycleAccent
        ))

        return tiles.isEmpty
            ? [ShellTile(title: "No Themes", subtitle: "Add .quakekittheme packages", action: .setStatus("No themes installed"))]
            : tiles
    }
}

final class PanelView: NSView {
    var selectedIndex: Int = 0 {
        didSet { updateSelection() }
    }
    var status: String = "Starting" {
        didSet { updateStatus() }
    }
    private let pages: [ShellPage]
    private let themePackages: [ThemePackage]
    private let columns = 8
    private let rows = 2
    private let portraitMode: Bool
    private var currentPageIndex = 0
    private var activeThemeIndex = 0
    private var activeTheme: PanelTheme
    private var accentCycleIndex = 0
    private var runtime = RuntimeSnapshot()
    private var tileViews: [TileCellView] = []
    private var runtimeRows: [StatusRowView] = []
    private var pageLabels: [NSTextField] = []
    private let statusLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")

    init(frame frameRect: NSRect, pages: [ShellPage], themePackages: [ThemePackage], portraitMode: Bool) {
        self.pages = pages
        self.themePackages = themePackages
        self.portraitMode = portraitMode
        self.activeTheme = themePackages.first.map { PanelTheme.from($0.manifest) } ?? .fallback
        super.init(frame: frameRect)
        wantsLayer = true
        autoresizingMask = [.width, .height]
        layer?.backgroundColor = activeTheme.background.cgColor
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
        case .selectTheme(let index):
            selectTheme(index)
        case .cycleAccent:
            cycleAccent()
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
                let view = TileCellView(tile: tile, theme: activeTheme)
                view.translatesAutoresizingMaskIntoConstraints = true
                addSubview(view)
                return view
            }
        case .runtimeStatus:
            runtimeRows = RuntimeStatusModel.rows(from: runtime).map { row in
                let view = StatusRowView(title: row.title, value: row.value, theme: activeTheme)
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
        let gap = activeTheme.spacing
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
        let gap = activeTheme.spacing
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
        titleLabel.stringValue = "QuakeKit"
        titleLabel.textColor = activeTheme.textPrimary
        layer?.backgroundColor = activeTheme.background.cgColor
        for (index, label) in pageLabels.enumerated() {
            let active = index == currentPageIndex
            label.layer?.backgroundColor = (active
                ? activeTheme.surfaceRaised
                : activeTheme.surface).cgColor
            label.textColor = active ? activeTheme.textPrimary : activeTheme.textSecondary
            label.layer?.borderWidth = active ? max(2, activeTheme.borderWidth) : activeTheme.borderWidth
            label.layer?.borderColor = (active
                ? activeTheme.accent
                : activeTheme.border).cgColor
        }
        statusLabel.textColor = activeTheme.accent
        tileViews.forEach { $0.theme = activeTheme }
        runtimeRows.forEach { $0.theme = activeTheme }
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

    private func selectTheme(_ index: Int) {
        guard themePackages.indices.contains(index) else { return }
        activeThemeIndex = index
        activeTheme = PanelTheme.from(themePackages[index].manifest)
        status = "Theme \(activeTheme.name)"
        log("theme selected \(themePackages[index].manifest.id)")
        updateChrome()
        rebuildPageContent()
    }

    private func cycleAccent() {
        let accents = [
            activeTheme.accent,
            activeTheme.success,
            activeTheme.warning,
            activeTheme.danger,
            NSColor(calibratedRed: 0.36, green: 0.78, blue: 1.0, alpha: 1),
            NSColor(calibratedRed: 1.0, green: 0.42, blue: 0.86, alpha: 1)
        ]
        accentCycleIndex = (accentCycleIndex + 1) % accents.count
        activeTheme = activeTheme.withAccent(accents[accentCycleIndex])
        status = "Accent override \(accentCycleIndex + 1)"
        updateChrome()
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
        let text = "QUAKEKIT DISPLAY TEST \(phase)"
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
    var theme: PanelTheme {
        didSet { applyTheme() }
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")

    init(title: String, value: String, theme: PanelTheme) {
        self.value = value
        self.theme = theme
        super.init(frame: .zero)
        wantsLayer = true

        titleLabel.stringValue = title
        titleLabel.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        titleLabel.backgroundColor = .clear

        valueLabel.stringValue = value
        valueLabel.font = NSFont.monospacedSystemFont(ofSize: 24, weight: .semibold)
        valueLabel.backgroundColor = .clear
        valueLabel.lineBreakMode = .byTruncatingTail

        addSubview(titleLabel)
        addSubview(valueLabel)
        applyTheme()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        titleLabel.frame = NSRect(x: 16, y: bounds.height - 40, width: bounds.width - 32, height: 22)
        valueLabel.frame = NSRect(x: 16, y: 24, width: bounds.width - 32, height: 34)
    }

    private func applyTheme() {
        layer?.cornerRadius = theme.cornerRadius
        layer?.borderWidth = theme.borderWidth
        layer?.borderColor = theme.border.cgColor
        layer?.backgroundColor = theme.surface.cgColor
        titleLabel.textColor = theme.textSecondary
        valueLabel.textColor = theme.textPrimary
    }
}

final class TileCellView: NSView {
    var isSelected: Bool = false {
        didSet { applyStyle() }
    }
    var theme: PanelTheme {
        didSet { applyStyle() }
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    init(tile: ShellTile, theme: PanelTheme) {
        self.theme = theme
        super.init(frame: .zero)
        wantsLayer = true

        titleLabel.stringValue = tile.title
        titleLabel.font = NSFont.systemFont(ofSize: 25, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.backgroundColor = .clear

        subtitleLabel.stringValue = tile.subtitle
        subtitleLabel.font = NSFont.systemFont(ofSize: 16, weight: .regular)
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
        layer?.cornerRadius = theme.cornerRadius
        layer?.backgroundColor = (isSelected
            ? theme.surfaceRaised
            : theme.surface).cgColor
        layer?.borderColor = (isSelected
            ? theme.accent
            : theme.border).cgColor
        layer?.borderWidth = isSelected ? max(3, theme.borderWidth) : theme.borderWidth
        titleLabel.textColor = theme.textPrimary
        subtitleLabel.textColor = theme.textSecondary
    }
}
