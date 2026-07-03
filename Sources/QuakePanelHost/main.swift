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
    private var ringCoordinator = KnobRingCoordinator()
    private var ringTimer: Timer?
    private var lastRingOutput: KnobRingResolvedOutput?
    private let pluginPackages = PanelPluginLoader.loadSamplePackages()
    private let themePackages = PanelThemeLoader.loadSamplePackages()

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("applicationDidFinishLaunching debugWindow=\(launchOptions.debugWindow) displayTest=\(launchOptions.displayTest) mainScreen=\(launchOptions.mainScreen) noHID=\(launchOptions.noHID)")
        NSApp.activate(ignoringOtherApps: true)
        openPanelWindow()
        if launchOptions.noHID {
            log("HID disabled by --no-hid; touch and knob input will not be available")
            panelView?.status = "Display only, HID disabled"
        } else {
            startDevice()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ringTimer?.invalidate()
        ringTimer = nil
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
            let view = PanelView(
                frame: contentFrame,
                pluginPackages: pluginPackages,
                themePackages: themePackages,
                portraitMode: !launchOptions.debugWindow && frame.height > frame.width
            )
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
            requestKnobRing(state: .success, priority: .focus, ttl: 1.2, source: "hid")
            startRingTimer()
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
            requestKnobRing(state: .focus, priority: .focus, ttl: 0.8, source: "touch")
            panelView?.recordTouch(point)
            panelView?.touch(logicalX: CGFloat(point.x), logicalY: CGFloat(point.y))
        case .knob(let event):
            panelView?.recordKnob(event)
            requestKnobRing(state: .focus, priority: .focus, ttl: 0.8, source: "knob")
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

    private func startRingTimer() {
        ringTimer?.invalidate()
        ringTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyKnobRing()
            }
        }
        applyKnobRing()
    }

    private func requestKnobRing(
        state: KnobRingSemanticState,
        priority: KnobRingPriority,
        ttl: TimeInterval?,
        source: String
    ) {
        ringCoordinator.submit(KnobRingRequest(source: source, state: state, priority: priority, ttl: ttl))
        applyKnobRing()
    }

    private func applyKnobRing() {
        guard let device else { return }
        guard let output = panelView?.resolvedKnobRingOutput(using: &ringCoordinator) else {
            if lastRingOutput != nil {
                _ = device.turnKnobRingOff()
                lastRingOutput = nil
                log("knob ring off")
            }
            return
        }

        guard output != lastRingOutput else { return }
        let ok = device.applyKnobRing(output)
        lastRingOutput = output
        log("knob ring \(output.state.rawValue) source=\(output.source) color=\(output.color) intensity=\(String(format: "%.2f", output.intensity)) animation=\(output.animation.rawValue) ok=\(ok)")
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
    case openPluginView(pluginID: String, viewID: String)
    case invokePluginAction(pluginID: String, actionID: String)
    case selectTheme(Int)
    case editThemeOption(String)
    case resetThemeOverrides
}

struct ShellPage: Equatable {
    var title: String
    var kind: Kind
    var tiles: [ShellTile]

    enum Kind: Equatable {
        case grid
        case runtimeStatus
        case pluginView(pluginID: String, viewID: String)
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

struct ThemeUserConfiguration: Codable, Equatable {
    var activeThemeID: String?
    var overrides: [String: JSONValue]

    init(activeThemeID: String? = nil, overrides: [String: JSONValue] = [:]) {
        self.activeThemeID = activeThemeID
        self.overrides = overrides
    }
}

enum ThemeConfigurationStore {
    static func load() -> ThemeUserConfiguration {
        guard let url = configURL(), let data = try? Data(contentsOf: url) else {
            return ThemeUserConfiguration()
        }
        do {
            return try JSONDecoder().decode(ThemeUserConfiguration.self, from: data)
        } catch {
            log("theme config load failed: \(error)")
            return ThemeUserConfiguration()
        }
    }

    static func save(_ configuration: ThemeUserConfiguration) {
        guard let url = configURL() else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(configuration).write(to: url, options: .atomic)
        } catch {
            log("theme config save failed: \(error)")
        }
    }

    private static func configURL() -> URL? {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return directory?
            .appendingPathComponent("QuakeKit", isDirectory: true)
            .appendingPathComponent("theme-config.json")
    }
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

    static func from(_ manifest: ThemeManifest, overrides: [String: JSONValue] = [:]) -> PanelTheme {
        let palette = manifest.palette
        let semantic = palette.semanticColors
        let fallback = PanelTheme.fallback

        func color(_ reference: String?, _ fallbackColor: NSColor) -> NSColor {
            guard let reference else { return fallbackColor }
            if let direct = NSColor(hex: reference) {
                return direct
            }
            if let override = overrides["palette.colors.\(reference).value"]?.stringValue, let overrideColor = NSColor(hex: override) {
                return overrideColor
            }
            if let token = palette.colors[reference], let tokenColor = NSColor(hex: token.value) {
                return tokenColor
            }
            return fallbackColor
        }

        func overrideMetric(_ path: String, _ base: CGFloat) -> CGFloat {
            guard let value = overrides[path]?.doubleValue else { return base }
            return CGFloat(max(0, value))
        }

        let baseSpacing = overrideMetric("metrics.spacing", CGFloat(manifest.metrics?.spacing ?? Double(fallback.spacing)))
        let densitySpacing: CGFloat
        switch overrides["metrics.density"]?.stringValue ?? manifest.metrics?.density?.rawValue {
        case "compact":
            densitySpacing = min(baseSpacing, 8)
        case "comfortable":
            densitySpacing = max(baseSpacing, 12)
        default:
            densitySpacing = baseSpacing
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
            cornerRadius: overrideMetric("metrics.cornerRadius", CGFloat(manifest.metrics?.cornerRadius ?? Double(fallback.cornerRadius))),
            borderWidth: CGFloat(manifest.metrics?.borderWidth ?? Double(fallback.borderWidth)),
            spacing: densitySpacing
        )
    }

    func withAccent(_ accent: NSColor) -> PanelTheme {
        var copy = self
        copy.accent = accent
        return copy
    }
}

extension JSONValue {
    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var doubleValue: Double? {
        switch self {
        case .double(let value):
            return value
        case .integer(let value):
            return Double(value)
        default:
            return nil
        }
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
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
    static func defaultPages(
        pluginPackages: [PluginPackage],
        themePackages: [ThemePackage],
        activeThemeIndex: Int,
        overrides: [String: JSONValue]
    ) -> [ShellPage] {
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
        let actionTiles = pluginActionTiles(from: pluginPackages)
        let themeTiles = themeTiles(from: themePackages, activeThemeIndex: activeThemeIndex, overrides: overrides)

        return [
            ShellPage(title: "Home", kind: .grid, tiles: [
            ShellTile(title: "Runtime", subtitle: "Live host status", action: .openPage(4)),
            ShellTile(title: "Widgets", subtitle: "\(widgetTiles.count) compact views", action: .openPage(1)),
            ShellTile(title: "Apps", subtitle: "\(appTiles.count + actionTiles.count) entries", action: .openPage(2)),
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
            ShellPage(title: "Apps", kind: .grid, tiles: appTiles + actionTiles),
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
                    action: .openPluginView(pluginID: package.manifest.id, viewID: view.id)
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

    private static func pluginActionTiles(from packages: [PluginPackage]) -> [ShellTile] {
        packages.flatMap { package in
            package.manifest.actions.map { action in
                ShellTile(
                    title: action.title,
                    subtitle: "\(package.manifest.name) · action",
                    action: .invokePluginAction(pluginID: package.manifest.id, actionID: action.id)
                )
            }
        }
    }

    private static func themeTiles(from packages: [ThemePackage], activeThemeIndex: Int, overrides: [String: JSONValue]) -> [ShellTile] {
        var tiles = packages.enumerated().map { index, package in
            ShellTile(
                title: index == activeThemeIndex ? "\(package.manifest.name) *" : package.manifest.name,
                subtitle: package.manifest.description ?? package.manifest.id,
                action: .selectTheme(index)
            )
        }

        if packages.indices.contains(activeThemeIndex) {
            tiles.append(contentsOf: packages[activeThemeIndex].manifest.options.map { option in
                ShellTile(
                    title: option.title,
                    subtitle: optionSubtitle(option, overrides: overrides),
                    action: .editThemeOption(option.id)
                )
            })
        }

        tiles.append(ShellTile(title: "Reset", subtitle: "Clear overrides", action: .resetThemeOverrides))

        return tiles.isEmpty
            ? [ShellTile(title: "No Themes", subtitle: "Add .quakekittheme packages", action: .setStatus("No themes installed"))]
            : tiles
    }

    private static func optionSubtitle(_ option: ThemeOption, overrides: [String: JSONValue]) -> String {
        let current = overrides[option.target] ?? option.defaultValue
        switch option.type {
        case .color:
            return "Color \(display(current))"
        case .number:
            let range = [option.minimum, option.maximum].compactMap { $0.map { String($0) } }.joined(separator: "...")
            return range.isEmpty ? "Value \(display(current))" : "\(display(current)) · range \(range)"
        case .boolean:
            return display(current)
        case .choice:
            return "\(display(current)) · \(option.choices.count) choices"
        }
    }

    private static func display(_ value: JSONValue) -> String {
        switch value {
        case .string(let value):
            return value
        case .integer(let value):
            return "\(value)"
        case .double(let value):
            return String(format: "%.1f", value)
        case .bool(let value):
            return value ? "on" : "off"
        default:
            return "set"
        }
    }
}

final class PanelView: NSView {
    var selectedIndex: Int = 0 {
        didSet { updateSelection() }
    }
    var status: String = "Starting" {
        didSet { updateStatus() }
    }
    private let pluginPackages: [PluginPackage]
    private let pluginRuntime: PluginExecutionHost
    private let themePackages: [ThemePackage]
    private var pages: [ShellPage]
    private let columns = 8
    private let rows = 2
    private let portraitMode: Bool
    private var currentPageIndex = 0
    private var transientPage: ShellPage?
    private var activeThemeIndex = 0
    private var activeTheme: PanelTheme
    private var themeConfiguration: ThemeUserConfiguration
    private var pluginDataStore = PluginDataStore()
    private var runtime = RuntimeSnapshot()
    private var tileViews: [TileCellView] = []
    private var runtimeRows: [StatusRowView] = []
    private var pageLabels: [NSTextField] = []
    private let statusLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")

    init(frame frameRect: NSRect, pluginPackages: [PluginPackage], themePackages: [ThemePackage], portraitMode: Bool) {
        self.pluginPackages = pluginPackages
        self.pluginRuntime = PluginExecutionHost(packages: pluginPackages)
        self.themePackages = themePackages
        self.portraitMode = portraitMode
        self.themeConfiguration = ThemeConfigurationStore.load()
        if let activeThemeID = themeConfiguration.activeThemeID,
           let index = themePackages.firstIndex(where: { $0.manifest.id == activeThemeID }) {
            self.activeThemeIndex = index
        }
        self.pages = ShellCatalog.defaultPages(
            pluginPackages: pluginPackages,
            themePackages: themePackages,
            activeThemeIndex: activeThemeIndex,
            overrides: themeConfiguration.overrides
        )
        self.activeTheme = themePackages.indices.contains(activeThemeIndex)
            ? PanelTheme.from(themePackages[activeThemeIndex].manifest, overrides: themeConfiguration.overrides)
            : .fallback
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
        case .openPluginView(let pluginID, let viewID):
            openPluginView(pluginID: pluginID, viewID: viewID)
        case .invokePluginAction(let pluginID, let actionID):
            invokePluginAction(pluginID: pluginID, actionID: actionID)
        case .selectTheme(let index):
            selectTheme(index)
        case .editThemeOption(let id):
            editThemeOption(id)
        case .resetThemeOverrides:
            resetThemeOverrides()
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
        transientPage ?? pages[currentPageIndex]
    }

    private func openPage(_ index: Int) {
        guard pages.indices.contains(index) else { return }
        guard currentPageIndex != index || transientPage != nil else { return }
        transientPage = nil
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
        case .pluginView(let pluginID, let viewID):
            runtimeRows = pluginViewRows(pluginID: pluginID, viewID: viewID).map { row in
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
        if currentPage.kind == .runtimeStatus || isPluginView(currentPage.kind) {
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
        let rowCount = max(1, Int(ceil(Double(runtimeRows.count) / Double(columns))))
        let rowHeight = (rect.height - gap * CGFloat(max(0, rowCount - 1))) / CGFloat(rowCount)
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

    private func openPluginView(pluginID: String, viewID: String) {
        guard let package = pluginPackages.first(where: { $0.manifest.id == pluginID }),
              let view = package.manifest.views.first(where: { $0.id == viewID }) else {
            status = "Plugin view missing"
            return
        }
        transientPage = ShellPage(title: view.title, kind: .pluginView(pluginID: pluginID, viewID: viewID), tiles: [])
        selectedIndex = 0
        status = "\(package.manifest.name) view"
        refreshData(for: view, package: package)
        log("plugin view opened \(pluginID).\(viewID)")
        rebuildPageContent()
    }

    private func pluginViewRows(pluginID: String, viewID: String) -> [(title: String, value: String)] {
        guard let package = pluginPackages.first(where: { $0.manifest.id == pluginID }),
              let view = package.manifest.views.first(where: { $0.id == viewID }) else {
            return [("Plugin View", "missing")]
        }

        var rows = [
            ("Plugin", package.manifest.name),
            ("View", view.title),
            ("Type", view.type?.rawValue ?? "unspecified"),
            ("Presentation", view.presentation?.rawValue ?? "page"),
            ("Entrypoint", view.entryPath ?? package.manifest.entry.url?.relativeString ?? package.manifest.entry.command ?? "-"),
            ("Data Stream", view.dataStreamID ?? "-"),
            ("Preferred Size", "\(view.preferredWidth ?? 0)x\(view.preferredHeight ?? 0)"),
            ("Package", package.baseURL.lastPathComponent)
        ]

        if let streamID = view.dataStreamID, let snapshot = pluginDataStore.snapshot(pluginID: pluginID, streamID: streamID) {
            rows.append(("Latest Data", summarize(snapshot.payload)))
            rows.append(("Updated", relativeTime(snapshot.timestamp)))
        }

        return rows
    }

    private func refreshData(for view: PluginView, package: PluginPackage) {
        guard let streamID = view.dataStreamID, let action = package.manifest.actions.first else { return }
        let result = pluginRuntime.invokeAction(pluginID: package.manifest.id, actionID: action.id)
        if let payload = result.response.result, result.response.ok {
            pluginDataStore.set(pluginID: package.manifest.id, streamID: streamID, payload: payload)
        } else if let error = result.response.error {
            status = "\(package.manifest.id): \(error)"
        }
    }

    private func selectTheme(_ index: Int) {
        guard themePackages.indices.contains(index) else { return }
        activeThemeIndex = index
        themeConfiguration.activeThemeID = themePackages[index].manifest.id
        themeConfiguration.overrides.removeAll()
        ThemeConfigurationStore.save(themeConfiguration)
        rebuildPages()
        activeTheme = PanelTheme.from(themePackages[index].manifest)
        status = "Theme \(activeTheme.name)"
        log("theme selected \(themePackages[index].manifest.id)")
        updateChrome()
        rebuildPageContent()
    }

    private func editThemeOption(_ id: String) {
        guard let option = activeThemeManifest?.options.first(where: { $0.id == id }) else {
            status = "Missing option \(id)"
            return
        }

        let value = nextValue(for: option)
        themeConfiguration.activeThemeID = activeThemeManifest?.id
        themeConfiguration.overrides[option.target] = value
        ThemeConfigurationStore.save(themeConfiguration)
        activeTheme = activeThemeManifest.map { PanelTheme.from($0, overrides: themeConfiguration.overrides) } ?? .fallback
        rebuildPages()
        status = "\(option.title): \(display(value))"
        log("theme option \(option.id)=\(display(value))")
        updateChrome()
        rebuildPageContent()
    }

    private func resetThemeOverrides() {
        themeConfiguration.activeThemeID = activeThemeManifest?.id
        themeConfiguration.overrides.removeAll()
        ThemeConfigurationStore.save(themeConfiguration)
        activeTheme = activeThemeManifest.map { PanelTheme.from($0) } ?? .fallback
        rebuildPages()
        status = "Theme overrides reset"
        updateChrome()
        rebuildPageContent()
    }

    private func invokePluginAction(pluginID: String, actionID: String) {
        let result = pluginRuntime.invokeAction(pluginID: pluginID, actionID: actionID)
        if result.response.ok {
            if let value = result.response.result {
                status = "\(pluginID): \(summarize(value))"
            } else {
                status = "\(pluginID).\(actionID) complete"
            }
        } else {
            status = "\(pluginID): \(result.response.error ?? "action failed")"
        }
        log("plugin action \(pluginID).\(actionID) ok=\(result.response.ok) duration=\(String(format: "%.3f", result.duration))s")
    }

    private var activeThemeManifest: ThemeManifest? {
        guard themePackages.indices.contains(activeThemeIndex) else { return nil }
        return themePackages[activeThemeIndex].manifest
    }

    func resolvedKnobRingOutput(using coordinator: inout KnobRingCoordinator) -> KnobRingResolvedOutput? {
        guard var output = coordinator.resolve(theme: activeThemeManifest?.hardware?.knobRing) else {
            return nil
        }
        output.color = resolvedColorReference(output.color)
        return output
    }

    private func resolvedColorReference(_ reference: String) -> String {
        if NSColor(hex: reference) != nil {
            return reference
        }
        if let override = themeConfiguration.overrides["palette.colors.\(reference).value"]?.stringValue {
            return override
        }
        if let color = activeThemeManifest?.palette.colors[reference]?.value {
            return color
        }
        return activeThemeManifest?.palette.colors["accent"]?.value ?? "#7CFFD1"
    }

    private func rebuildPages() {
        pages = ShellCatalog.defaultPages(
            pluginPackages: pluginPackages,
            themePackages: themePackages,
            activeThemeIndex: activeThemeIndex,
            overrides: themeConfiguration.overrides
        )
        for (index, label) in pageLabels.enumerated() where pages.indices.contains(index) {
            label.stringValue = "\(index + 1) \(pages[index].title)"
        }
    }

    private func nextValue(for option: ThemeOption) -> JSONValue {
        switch option.type {
        case .color:
            let swatches = colorSwatches(for: option)
            let current = themeConfiguration.overrides[option.target]?.stringValue ?? option.defaultValue.stringValue
            let currentIndex = current.flatMap { swatches.firstIndex(of: $0) } ?? 0
            let index = (currentIndex + 1) % swatches.count
            return .string(swatches[index])
        case .choice:
            guard !option.choices.isEmpty else { return option.defaultValue }
            let current = themeConfiguration.overrides[option.target] ?? option.defaultValue
            let currentIndex = option.choices.firstIndex(of: current) ?? 0
            let index = (currentIndex + 1) % option.choices.count
            return option.choices[index]
        case .number:
            let minimum = option.minimum ?? 0
            let maximum = option.maximum ?? max(minimum + 1, 10)
            let steps = 5
            let current = themeConfiguration.overrides[option.target]?.doubleValue ?? option.defaultValue.doubleValue ?? minimum
            let normalized = maximum == minimum ? 0 : (current - minimum) / (maximum - minimum)
            let currentIndex = min(steps - 1, max(0, Int((normalized * Double(steps - 1)).rounded())))
            let index = (currentIndex + 1) % steps
            let value = minimum + (maximum - minimum) * Double(index) / Double(steps - 1)
            return .double(value)
        case .boolean:
            let next = !(themeConfiguration.overrides[option.target]?.boolValue ?? option.defaultValue.boolValue ?? false)
            return .bool(next)
        }
    }

    private func colorSwatches(for option: ThemeOption) -> [String] {
        let defaultColor = option.defaultValue.stringValue ?? activeThemeManifest?.palette.colors["accent"]?.value ?? "#7CFFD1"
        return [
            defaultColor,
            activeThemeManifest?.palette.colors["success"]?.value ?? "#6CFF8F",
            activeThemeManifest?.palette.colors["warning"]?.value ?? "#FFD166",
            activeThemeManifest?.palette.colors["danger"]?.value ?? "#FF5C7A",
            "#5CC8FF",
            "#FF6BDA"
        ]
    }

    private func display(_ value: JSONValue) -> String {
        switch value {
        case .string(let value):
            return value
        case .integer(let value):
            return "\(value)"
        case .double(let value):
            return String(format: "%.2f", value)
        case .bool(let value):
            return value ? "on" : "off"
        default:
            return "updated"
        }
    }

    private func isPluginView(_ kind: ShellPage.Kind) -> Bool {
        if case .pluginView = kind { return true }
        return false
    }

    private func summarize(_ value: JSONValue) -> String {
        switch value {
        case .object(let object):
            return object.keys.sorted().prefix(4).map { key in
                "\(key)=\(display(object[key] ?? .null))"
            }.joined(separator: " ")
        case .array(let values):
            return "\(values.count) values"
        default:
            return display(value)
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        return seconds == 0 ? "now" : "\(seconds)s ago"
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
