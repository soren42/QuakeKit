import AppKit
import Foundation
import IOKit.pwr_mgt
import QuakeHID
import QuakePluginAPI
import QuakeRuntime

private let quakeLogQueue = DispatchQueue(label: "com.soren42.quakekit.log")

enum QuakeHostResources {
    static let bundle: Bundle = {
        let resourceBundle = Bundle.main.resourceURL?
            .appendingPathComponent("QuakeKit_QuakePanelHost.bundle", isDirectory: true)
        if let resourceBundle, let bundle = Bundle(url: resourceBundle) {
            return bundle
        }
        // SwiftPM command-line builds retain their generated resource bundle.
        return Bundle.module
    }()
}

func log(_ message: String) {
    let line = "[quake-panel] \(ISO8601DateFormatter().string(from: Date())) \(message)\n"
    fputs(line, stderr)
    quakeLogQueue.async {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let directory = support.appendingPathComponent("QuakeKit/Logs", isDirectory: true)
        let url = directory.appendingPathComponent("quake-panel.log")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
            try handle.close()
        } catch {
            // stderr remains available for command-line launches.
        }
    }
}

let launchOptions = PanelLaunchOptions(arguments: CommandLine.arguments.dropFirst())
let app = NSApplication.shared
let delegate = PanelAppDelegate()
app.delegate = delegate
app.setActivationPolicy(launchOptions.foregroundApp ? .regular : .accessory)
app.mainMenu = NSMenu()
app.run()

struct PanelLaunchOptions {
    var debugWindow: Bool
    var displayTest: Bool
    var mainScreen: Bool
    var noHID: Bool
    var sharedHID: Bool
    var strictHIDSeize: Bool
    var simpleFullscreen: Bool
    var foregroundApp: Bool
    var keepAliveProfile: QuakeDevice.KeepAliveProfile
    var startupProfile: QuakeDevice.StartupProfile

    init(arguments: ArraySlice<String>) {
        let rawArguments = Array(arguments)
        let values = Set(rawArguments)
        self.debugWindow = values.contains("--debug-window")
        self.displayTest = values.contains("--display-test")
        self.mainScreen = values.contains("--main-screen")
        self.noHID = values.contains("--no-hid")
        self.sharedHID = values.contains("--shared-hid")
        self.strictHIDSeize = values.contains("--strict-hid-seize")
        self.simpleFullscreen = values.contains("--simple-fullscreen")
        self.foregroundApp = values.contains("--foreground")
        self.keepAliveProfile = Self.parseKeepAliveProfile(from: rawArguments)
        self.startupProfile = Self.parseStartupProfile(from: rawArguments)
    }

    var hidOpenMode: QuakeDevice.OpenMode {
        if sharedHID { return .shared }
        if strictHIDSeize { return .seizeRequired }
        return .seizePreferred
    }

    private static func parseKeepAliveProfile(from arguments: [String]) -> QuakeDevice.KeepAliveProfile {
        guard let index = arguments.firstIndex(of: "--keepalive"), arguments.indices.contains(index + 1) else {
            return .vendor
        }
        return QuakeDevice.KeepAliveProfile(rawValue: arguments[index + 1]) ?? .vendor
    }

    private static func parseStartupProfile(from arguments: [String]) -> QuakeDevice.StartupProfile {
        guard let index = arguments.firstIndex(of: "--startup"), arguments.indices.contains(index + 1) else {
            return .teejs
        }
        return QuakeDevice.StartupProfile(rawValue: arguments[index + 1]) ?? .teejs
    }
}

@MainActor
final class PanelAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var window: NSWindow?
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var panelView: PanelView?
    private var testView: DisplayTestView?
    private var device: QuakeDevice?
    private var ringCoordinator = KnobRingCoordinator()
    private var ringTimer: Timer?
    private var pointerGuardTimer: Timer?
    private var lastRingOutput: KnobRingResolvedOutput?
    private var displaySleepAssertionID: IOPMAssertionID = 0
    private let audioService = QuakeAudioService()
    private let pluginPackages = PanelPluginLoader.loadSamplePackages()
    private let themePackages = PanelThemeLoader.loadSamplePackages()

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("applicationDidFinishLaunching debugWindow=\(launchOptions.debugWindow) displayTest=\(launchOptions.displayTest) mainScreen=\(launchOptions.mainScreen) noHID=\(launchOptions.noHID) hidOpenMode=\(launchOptions.hidOpenMode) sharedHID=\(launchOptions.sharedHID) strictHIDSeize=\(launchOptions.strictHIDSeize) simpleFullscreen=\(launchOptions.simpleFullscreen) foreground=\(launchOptions.foregroundApp) startup=\(launchOptions.startupProfile.rawValue) keepAlive=\(launchOptions.keepAliveProfile.rawValue)")
        requestInputMonitoringAccessIfNeeded()
        configureStatusItem()
        if launchOptions.foregroundApp || launchOptions.debugWindow {
            NSApp.activate(ignoringOtherApps: true)
        }
        startPointerGuard()
        acquireDisplaySleepAssertion()
        openPanelWindow()
        observeDisplayChanges()
        if launchOptions.noHID {
            log("HID disabled by --no-hid; touch and knob input will not be available")
            panelView?.status = "Display only, HID disabled"
        } else {
            startDevice()
        }
    }

    /// The DK touch collection advertises `RequiresTCCAuthorization`. A Finder
    /// launch is a distinct TCC identity from Codex or Terminal, so ask under
    /// the shipped app bundle before opening the HID managers.
    private func requestInputMonitoringAccessIfNeeded() {
        guard #available(macOS 10.15, *) else { return }
        if CGPreflightListenEventAccess() {
            log("Input Monitoring access already authorized")
            return
        }
        let granted = CGRequestListenEventAccess()
        log("Input Monitoring access requested immediateGrant=\(granted)")
        guard !granted else { return }
        DispatchQueue.main.async { [weak self] in
            guard self != nil else { return }
            let alert = NSAlert()
            alert.messageText = "QuakeKit Needs Input Monitoring"
            alert.informativeText = "macOS must allow QuakeKit to read the DK-QUAKE touchscreen. Enable QuakeKit in Privacy & Security > Input Monitoring, then quit and reopen QuakeKit."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Open Input Monitoring")
            alert.addButton(withTitle: "Continue Without Touch")
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ringTimer?.invalidate()
        ringTimer = nil
        pointerGuardTimer?.invalidate()
        pointerGuardTimer = nil
        NotificationCenter.default.removeObserver(self)
        device?.stop()
        releaseDisplaySleepAssertion()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let icon = statusIconImage() {
            item.length = NSStatusItem.squareLength
            item.button?.image = icon
            item.button?.imagePosition = .imageOnly
            item.button?.imageScaling = .scaleProportionallyDown
        } else {
            item.button?.title = "QK"
        }
        item.button?.toolTip = "QuakeKit"

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(statusMenuCaption(id: "caption", title: "QuakeKit 1.0.0"))
        menu.addItem(statusMenuItem(id: "panel", title: "Show Panel", symbol: "display", action: #selector(showPanelWindow), keyEquivalent: "P"))
        menu.addItem(statusMenuItem(id: "settings", title: "Open Settings...", symbol: "gearshape", action: #selector(openSettingsWindow), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(statusMenuCaption(id: "audioHeader", title: "AUDIO"))
        menu.addItem(statusMenuItem(id: "microphone", title: "Microphone", symbol: "mic", action: #selector(requestMicrophoneAccess), keyEquivalent: ""))
        menu.addItem(statusMenuItem(id: "record", title: "Record Meeting (30s)", symbol: "record.circle", action: #selector(recordMeetingClip), keyEquivalent: ""))
        menu.addItem(statusMenuItem(id: "speak", title: "Test Speaker", symbol: "speaker.wave.2", action: #selector(speakTestPhrase), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(statusMenuCaption(id: "activeHeader", title: "ACTIVE"))
        menu.addItem(statusMenuItem(id: "activeMenu", title: "Menu", symbol: "rectangle.leftthird.inset.filled", action: #selector(openSettingsWindow), keyEquivalent: ""))
        menu.addItem(statusMenuItem(id: "activeTheme", title: "Theme", symbol: "paintpalette", action: #selector(openSettingsWindow), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(statusMenuItem(id: "quit", title: "Quit QuakeKit", symbol: "power", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    private func statusMenuItem(id: String, title: String, symbol: String? = nil, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.identifier = NSUserInterfaceItemIdentifier(id)
        item.target = self
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        }
        return item
    }

    private func statusMenuCaption(id: String, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.identifier = NSUserInterfaceItemIdentifier(id)
        item.isEnabled = false
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items {
            switch item.identifier?.rawValue {
            case "caption":
                item.title = "QuakeKit 1.0.0 · \(window?.isVisible == true ? "panel awake" : "panel hidden") · \(pluginPackages.count) plugins"
            case "settings":
                item.title = settingsWindow?.isVisible == true ? "Open Settings... (Open)" : "Open Settings..."
                item.state = settingsWindow?.isVisible == true ? .on : .off
            case "panel":
                item.title = window?.isVisible == true ? "Show Panel (Visible)" : "Show Panel"
                item.state = window?.isVisible == true ? .on : .off
                item.isEnabled = window != nil
            case "microphone":
                item.title = "Microphone: \(audioService.capturePermissionDescription)"
            case "record":
                item.title = audioService.isRecording ? "Stop Recording" : "Record Meeting (30s)"
                item.isEnabled = audioService.capturePermissionDescription != "denied"
            case "speak":
                item.isEnabled = true
            case "activeMenu":
                item.title = "Menu: \(PanelMenuTemplate(menuID: QuakeSettingsStore.load().mainMenuViewID).displayName)"
            case "activeTheme":
                let activeID = ThemeConfigurationStore.load().activeThemeID
                item.title = "Theme: \(themePackages.first(where: { $0.manifest.id == activeID })?.manifest.name ?? themePackages.first?.manifest.name ?? "Fallback")"
            default:
                break
            }
        }
    }

    private func statusIconImage() -> NSImage? {
        guard let url = QuakeHostResources.bundle.url(forResource: "StatusIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }

    private func startPointerGuard() {
        guard !launchOptions.debugWindow, !launchOptions.mainScreen else { return }
        pointerGuardTimer?.invalidate()
        pointerGuardTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            Task { @MainActor in
                guard let quakeScreen = DisplayLocator.quakeScreen(),
                      let primaryScreen = NSScreen.screens.first(where: { !DisplayLocator.isQuakeLike($0.frame.size) }) ?? NSScreen.main else {
                    return
                }
                let mouse = NSEvent.mouseLocation
                guard quakeScreen.frame.contains(mouse) else { return }
                let target = NSPoint(x: primaryScreen.frame.midX, y: primaryScreen.frame.midY)
                CGWarpMouseCursorPosition(target)
            }
        }
    }

    @objc private func showPanelWindow() {
        window?.orderFrontRegardless()
    }

    @objc private func requestMicrophoneAccess() {
        if audioService.capturePermissionDescription == "denied" || audioService.capturePermissionDescription == "restricted" {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
            panelView?.status = "Open Privacy & Security to allow microphone access"
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let granted = await audioService.requestCapturePermission()
            let status = granted ? "Microphone authorized" : "Microphone denied"
            log("audio \(status) current=\(audioService.capturePermissionDescription)")
            panelView?.status = status
        }
    }

    @objc private func recordMeetingClip() {
        if audioService.isRecording {
            audioService.stopRecording()
            panelView?.status = "Meeting recording stopped"
            return
        }
        do {
            let url = try audioService.startMeetingClip(duration: 30)
            log("audio recording started \(url.path)")
            panelView?.status = "Recording 30s meeting clip"
        } catch {
            log("audio recording failed: \(error)")
            panelView?.status = "Audio record failed: \(error)"
        }
    }

    @objc private func speakTestPhrase() {
        audioService.speak("QuakeKit voice output is ready.")
        panelView?.status = "Speaker test sent"
    }

    @objc private func openSettingsWindow() {
        if let settingsWindow {
            if let view = settingsWindow.contentView as? QuakeSettingsWindowView {
                view.reload(settings: QuakeSettingsStore.load(), themeConfiguration: ThemeConfigurationStore.load())
            }
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let screen = NSScreen.screens.first { !DisplayLocator.isQuakeLike($0.frame.size) } ?? NSScreen.main
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 160, y: 160, width: 1100, height: 720)
        let size = NSSize(width: min(920, screenFrame.width - 80), height: min(620, screenFrame.height - 80))
        let rect = NSRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        let view = QuakeSettingsWindowView(
            frame: NSRect(origin: .zero, size: size),
            pluginPackages: pluginPackages,
            themePackages: themePackages,
            settings: QuakeSettingsStore.load(),
            themeConfiguration: ThemeConfigurationStore.load(),
            microphoneStatus: { [weak self] in self?.audioService.capturePermissionDescription ?? "unknown" },
            onRequestMicrophoneAccess: { [weak self] in self?.requestMicrophoneAccess() },
            onRecordMeetingClip: { [weak self] in self?.recordMeetingClip() },
            onSpeakTest: { [weak self] in self?.speakTestPhrase() },
            onConfigurationChanged: { [weak self] in
                self?.panelView?.reloadConfigurationsFromDisk()
            }
        )
        let settingsWindow = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        settingsWindow.title = "QuakeKit Settings"
        settingsWindow.contentView = view
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.makeKeyAndOrderFront(nil)
        self.settingsWindow = settingsWindow
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func observeDisplayChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displayConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func displayConfigurationChanged() {
        log("display configuration changed")
        _ = device?.sendControlFrameReliably(QuakeProtocol.screenOn)
        reframePanelWindow()
    }

    private func acquireDisplaySleepAssertion() {
        guard displaySleepAssertionID == 0 else { return }
        var assertionID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "QuakeKit panel is owning the DK-QUAKE display" as CFString,
            &assertionID
        )
        if result == kIOReturnSuccess {
            displaySleepAssertionID = assertionID
            log("display sleep assertion acquired id=\(assertionID)")
        } else {
            log("display sleep assertion failed \(result)")
        }
    }

    private func releaseDisplaySleepAssertion() {
        guard displaySleepAssertionID != 0 else { return }
        let result = IOPMAssertionRelease(displaySleepAssertionID)
        log("display sleep assertion released id=\(displaySleepAssertionID) result=\(result)")
        displaySleepAssertionID = 0
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
        panelWindow.hidesOnDeactivate = false
        panelWindow.isMovable = launchOptions.debugWindow
        panelWindow.isMovableByWindowBackground = false
        panelWindow.contentView = panelContentView
        panelWindow.setFrame(rect, display: true)
        panelWindow.makeKeyAndOrderFront(nil)
        panelWindow.orderFrontRegardless()
        if launchOptions.displayTest {
            panelWindow.level = .screenSaver
            panelWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        } else if quakeLike && !launchOptions.debugWindow {
            panelWindow.level = .screenSaver
            panelWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            applyPanelPresentationOptions()
            if launchOptions.simpleFullscreen {
                panelWindow.toggleFullScreen(nil)
            }
        } else {
            panelWindow.level = .normal
        }
        panelContentView.needsDisplay = true
        panelContentView.displayIfNeeded()
        log("window visible=\(panelWindow.isVisible) frame=\(format(panelWindow.frame)) content=\(format(panelContentView.frame)) level=\(panelWindow.level.rawValue)")

        self.window = panelWindow
    }

    private func applyPanelPresentationOptions() {
        let options: NSApplication.PresentationOptions = [
            .hideDock,
            .hideMenuBar,
            .disableAppleMenu
        ]
        NSApp.presentationOptions = options
    }

    private func reframePanelWindow() {
        guard let panelWindow = window else {
            openPanelWindow()
            return
        }
        let targetScreen = launchOptions.mainScreen ? NSScreen.main : (DisplayLocator.quakeScreen() ?? NSScreen.main)
        guard let targetScreen else { return }
        let frame = targetScreen.frame
        let quakeLike = !launchOptions.mainScreen && DisplayLocator.isQuakeLike(frame.size)
        let logicalSize = quakeLike && !launchOptions.debugWindow ? frame.size : panelWindow.frame.size
        let origin = quakeLike && !launchOptions.debugWindow
            ? frame.origin
            : NSPoint(x: frame.midX - logicalSize.width / 2, y: frame.midY - logicalSize.height / 2)
        let rect = NSRect(origin: origin, size: logicalSize)
        panelWindow.setFrame(rect, display: true)
        if quakeLike && !launchOptions.debugWindow {
            panelWindow.level = .screenSaver
            applyPanelPresentationOptions()
        }
        panelWindow.orderFrontRegardless()
        log("window reframed=\(format(panelWindow.frame)) target=\(format(frame))")
    }

    private func startDevice() {
        let deliver: @MainActor (RuntimeEvent) -> Void = { [weak self] event in
            self?.handle(event)
        }
        let quake = QuakeDevice(
            openMode: launchOptions.hidOpenMode,
            keepAliveProfile: launchOptions.keepAliveProfile,
            startupProfile: launchOptions.startupProfile,
            diagnosticHandler: { message in
                log("hid \(message)")
            }
        ) { [weak self] event in
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
            if launchOptions.startupProfile == .diagnostic {
                applyStartupDeviceSettings()
            }
            requestKnobRing(state: .success, priority: .focus, ttl: 1.2, source: "hid")
            startRingTimer()
        } catch {
            log("hid unavailable: \(error)")
            panelView?.status = "HID unavailable: \(error)"
        }
    }

    private func applyStartupDeviceSettings() {
        guard let device else { return }
        let ledOK = device.setKnobRing(enabled: true)
        let micOK = device.setMic(false)
        log("startup device settings knobRing=\(ledOK) micOff=\(micOK)")
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let device = self?.device else { return }
                let screenOK = device.sendControlFrameReliably(QuakeProtocol.screenOn)
                let micOK = device.setMic(false)
                log("startup device reassert screenOn=\(screenOK) micOff=\(micOK)")
            }
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
                panelView?.moveSelection(direction > 0 ? 1 : -1)
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
    /// RC1 presents one Music applet and one AI Command Center. Older example
    /// package IDs remain importable as references but are not launcher entries.
    private static let supersededPackageIDs: Set<String> = [
        "spotify_controls", "spotify_current_track", "ai_agent_companions", "ai_workbench",
        "claude_harness", "chatgpt_harness", "cursor_harness", "deepseek_harness",
        "gemini_harness", "grok_harness"
    ]

    static func loadSamplePackages() -> [PluginPackage] {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let directories = [
            root.appendingPathComponent("Examples/Plugins", isDirectory: true),
            Bundle.main.resourceURL?.appendingPathComponent("Examples/Plugins", isDirectory: true),
            try? QuakePackageLocations.installedPluginDirectory()
        ].compactMap { $0 }
        var packagesByID: [String: PluginPackage] = [:]

        for directory in directories {
            let results = PluginPackageLoader.loadPackages(from: directory)
            for result in results {
                switch result {
                case .success(let package, let warnings):
                    guard !supersededPackageIDs.contains(package.manifest.id) else {
                        log("plugin skipped \(package.manifest.id): superseded by RC1 consolidated applet")
                        continue
                    }
                    packagesByID[package.manifest.id] = package
                    log("plugin loaded \(package.manifest.id) views=\(package.manifest.views.count) source=\(package.baseURL.path)")
                    for warning in warnings {
                        log("plugin warning \(package.manifest.id): \(warning)")
                    }
                case .failure(let url, let errors):
                    log("plugin failed \(url.lastPathComponent): \(errors.joined(separator: "; "))")
                }
            }
        }

        return packagesByID.values.sorted { $0.manifest.name < $1.manifest.name }
    }
}

enum PanelThemeLoader {
    static func loadSamplePackages() -> [ThemePackage] {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let directories = [
            root.appendingPathComponent("Examples/Themes", isDirectory: true),
            Bundle.main.resourceURL?.appendingPathComponent("Examples/Themes", isDirectory: true),
            try? QuakePackageLocations.installedThemeDirectory()
        ].compactMap { $0 }
        var packagesByID: [String: ThemePackage] = [:]

        for directory in directories {
            let results = ThemePackageLoader.loadPackages(from: directory)
            for result in results {
                switch result {
                case .success(let package, let warnings):
                    packagesByID[package.manifest.id] = package
                    log("theme loaded \(package.manifest.id) colors=\(package.manifest.palette.colors.count) source=\(package.baseURL.path)")
                    for warning in warnings {
                        log("theme warning \(package.manifest.id): \(warning)")
                    }
                case .failure(let url, let errors):
                    log("theme failed \(url.lastPathComponent): \(errors.joined(separator: "; "))")
                }
            }
        }

        return packagesByID.values.sorted { $0.manifest.name < $1.manifest.name }
    }
}

struct ShellTile: Equatable {
    var title: String
    var subtitle: String
    var action: ShellAction
    var icon: String? = nil
    var widget: WidgetPreviewRef? = nil
}

struct WidgetPreviewRef: Equatable {
    var pluginID: String
    var viewID: String
    var streamID: String?
}

struct WidgetPreviewData: Equatable {
    var value: String
    var detail: String
    var state: String?

    static func from(_ value: JSONValue?) -> WidgetPreviewData? {
        guard let object = value?.objectValue else { return nil }
        if let locations = object["locations"]?.arrayValue,
           let location = locations.first?.objectValue {
            let temperature = location["temperature"]?.doubleValue.map { String(format: "%.0f°", $0) } ?? "-"
            return WidgetPreviewData(value: temperature, detail: location["condition"]?.stringValue ?? location["name"]?.stringValue ?? "Weather", state: location["name"]?.stringValue)
        }
        if let track = object["track"]?.objectValue {
            return WidgetPreviewData(value: track["title"]?.stringValue ?? "No track", detail: track["artist"]?.stringValue ?? object["provider"]?.stringValue ?? "Music", state: object["playing"]?.boolValue == true ? "Playing" : "Paused")
        }
        if let rows = object["rows"]?.arrayValue,
           let row = rows.first?.objectValue {
            return WidgetPreviewData(value: row["value"]?.stringValue ?? "-", detail: row["detail"]?.stringValue ?? row["title"]?.stringValue ?? "Ready", state: object["status"]?.stringValue)
        }
        let preferred = ["cpu", "status", "state", "value", "title"]
        for key in preferred {
            if let item = object[key] {
                return WidgetPreviewData(value: WidgetPreviewData.display(item), detail: key.replacingOccurrences(of: "_", with: " ").capitalized, state: object["status"]?.stringValue)
            }
        }
        if let key = object.keys.sorted().first, let item = object[key] {
            return WidgetPreviewData(value: WidgetPreviewData.display(item), detail: key.replacingOccurrences(of: "_", with: " ").capitalized, state: nil)
        }
        return nil
    }

    private static func display(_ value: JSONValue) -> String {
        switch value {
        case .string(let value): return value
        case .integer(let value): return "\(value)"
        case .double(let value): return String(format: "%.1f", value)
        case .bool(let value): return value ? "On" : "Off"
        case .array(let values): return "\(values.count)"
        case .object(let values): return "\(values.count)"
        case .null: return "-"
        }
    }
}

enum ShellAction: Equatable {
    case openPage(Int)
    case setStatus(String)
    case openPluginView(pluginID: String, viewID: String)
    case invokePluginAction(pluginID: String, actionID: String)
    case selectTheme(Int)
    case editThemeOption(String)
    case resetThemeOverrides
    case editGlobalSetting(String)
    case openCarouselSettings
    case toggleCarousel
    case editCarouselDuration
    case toggleCarouselWidget(String)
    case openPluginSettings(String)
    case editPluginSetting(pluginID: String, settingID: String)
    case resetPluginSettings(String)
}

enum PanelPageLayout: Equatable {
    case grid
    case fullScreen
    case halfAndGrid
    case twoHalves
    case thirds
    case quarters
}

struct ShellPage: Equatable {
    var title: String
    var kind: Kind
    var layout: PanelPageLayout
    var tiles: [ShellTile]

    enum Kind: Equatable {
        case grid
        case runtimeStatus
        case pluginView(pluginID: String, viewID: String)
    }

    init(title: String, kind: Kind, layout: PanelPageLayout = .grid, tiles: [ShellTile]) {
        self.title = title
        self.kind = kind
        self.layout = layout
        self.tiles = tiles
    }
}

struct CarouselWidgetRef: Equatable {
    var id: String
    var pluginID: String
    var pluginName: String
    var viewID: String
    var title: String
}

struct MainMenuWidgetRef: Equatable {
    static let builtInID = "builtin:classic"

    var id: String
    var pluginID: String?
    var pluginName: String
    var viewID: String?
    var title: String
    var detail: String
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

struct QuakeSettingsConfiguration: Codable, Equatable {
    var defaultPageIndex: Int
    var mainMenuViewID: String
    var menuSettings: [String: JSONValue]
    var carousel: CarouselConfiguration
    var pluginSettings: [String: [String: JSONValue]]

    private enum CodingKeys: String, CodingKey {
        case defaultPageIndex
        case mainMenuViewID
        case menuSettings
        case carousel
        case pluginSettings
    }

    init(
        defaultPageIndex: Int = 0,
        mainMenuViewID: String = "builtin:status-rail",
        menuSettings: [String: JSONValue] = [:],
        carousel: CarouselConfiguration = CarouselConfiguration(),
        pluginSettings: [String: [String: JSONValue]] = [:]
    ) {
        self.defaultPageIndex = defaultPageIndex
        self.mainMenuViewID = mainMenuViewID
        self.menuSettings = menuSettings
        self.carousel = carousel
        self.pluginSettings = pluginSettings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.defaultPageIndex = try container.decodeIfPresent(Int.self, forKey: .defaultPageIndex) ?? 0
        self.mainMenuViewID = try container.decodeIfPresent(String.self, forKey: .mainMenuViewID) ?? "builtin:status-rail"
        self.menuSettings = try container.decodeIfPresent([String: JSONValue].self, forKey: .menuSettings) ?? [:]
        self.carousel = try container.decodeIfPresent(CarouselConfiguration.self, forKey: .carousel) ?? CarouselConfiguration()
        self.pluginSettings = try container.decodeIfPresent([String: [String: JSONValue]].self, forKey: .pluginSettings) ?? [:]
    }
}

struct CarouselConfiguration: Codable, Equatable {
    var enabled: Bool
    var intervalSeconds: Int
    var widgetIDs: [String]

    init(enabled: Bool = false, intervalSeconds: Int = 15, widgetIDs: [String] = []) {
        self.enabled = enabled
        self.intervalSeconds = intervalSeconds
        self.widgetIDs = widgetIDs
    }
}

enum QuakeSettingsStore {
    static func load() -> QuakeSettingsConfiguration {
        guard let url = configURL(), let data = try? Data(contentsOf: url) else {
            return QuakeSettingsConfiguration()
        }
        do {
            var configuration = try JSONDecoder().decode(QuakeSettingsConfiguration.self, from: data)
            migrateToRC1MenuDefault(&configuration)
            return configuration
        } catch {
            log("settings config load failed: \(error)")
            return QuakeSettingsConfiguration()
        }
    }

    private static func migrateToRC1MenuDefault(_ configuration: inout QuakeSettingsConfiguration) {
        let key = "migration.rc1.statusRail"
        guard configuration.menuSettings[key]?.boolValue != true else { return }
        if configuration.mainMenuViewID == MainMenuWidgetRef.builtInID || configuration.mainMenuViewID == "main_menu_classic:classic" {
            configuration.mainMenuViewID = "builtin:status-rail"
        }
        configuration.menuSettings[key] = .bool(true)
        save(configuration)
    }

    static func save(_ configuration: QuakeSettingsConfiguration) {
        guard let url = configURL() else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(configuration).write(to: url, options: .atomic)
        } catch {
            log("settings config save failed: \(error)")
        }
    }

    private static func configURL() -> URL? {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return directory?
            .appendingPathComponent("QuakeKit", isDirectory: true)
            .appendingPathComponent("settings.json")
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

    var integerValue: Int? {
        switch self {
        case .integer(let value):
            return value
        case .double(let value):
            return Int(value)
        default:
            return nil
        }
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
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
        overrides: [String: JSONValue],
        settingsConfiguration: QuakeSettingsConfiguration
    ) -> [ShellPage] {
        let themeLayout = themePackages.indices.contains(activeThemeIndex)
            ? panelLayout(from: themePackages[activeThemeIndex].manifest.layout?.defaultPageStyle)
            : .grid
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
        let settingsTiles = settingsTiles(
            pluginPackages: pluginPackages,
            themePackages: themePackages,
            settingsConfiguration: settingsConfiguration
        )
        let languageTiles = pluginLanguageTiles()
        let homeTiles: [ShellTile]
        if PanelMenuTemplate(menuID: settingsConfiguration.mainMenuViewID) != .classic {
            homeTiles = homeWidgetTiles(from: widgetTiles)
        } else {
            homeTiles = mainMenuTiles(
                from: pluginPackages,
                selectedMenuID: settingsConfiguration.mainMenuViewID,
                widgetCount: widgetTiles.count,
                appCount: appTiles.count + actionTiles.count,
                themeCount: themePackages.count
            )
        }

        return [
            ShellPage(title: "Home", kind: .grid, layout: themeLayout == .grid ? .halfAndGrid : themeLayout, tiles: homeTiles),
            ShellPage(title: "Widgets", kind: .grid, layout: themeLayout, tiles: widgetTiles),
            ShellPage(title: "Apps", kind: .grid, layout: themeLayout == .grid ? .twoHalves : themeLayout, tiles: appTiles + actionTiles),
            ShellPage(title: "Themes", kind: .grid, tiles: themeTiles),
            ShellPage(title: "Settings", kind: .grid, tiles: settingsTiles),
            ShellPage(title: "Runtime", kind: .runtimeStatus, layout: .quarters, tiles: []),
            ShellPage(title: "Plugin APIs", kind: .grid, layout: .quarters, tiles: languageTiles)
        ]
    }

    static func mainMenuRefs(from packages: [PluginPackage]) -> [MainMenuWidgetRef] {
        let packaged = packages.flatMap { package in
            package.manifest.views.compactMap { view -> MainMenuWidgetRef? in
                guard view.presentation == .mainMenu else { return nil }
                return MainMenuWidgetRef(
                    id: "\(package.manifest.id):\(view.id)",
                    pluginID: package.manifest.id,
                    pluginName: package.manifest.name,
                    viewID: view.id,
                    title: view.title,
                    detail: "\(package.manifest.name) · \(view.menuItems.count) menu items"
                )
            }
        }
        return [
            MainMenuWidgetRef(
                id: MainMenuWidgetRef.builtInID,
                pluginID: nil,
                pluginName: "QuakeKit",
                viewID: nil,
                title: "Classic Built-in Menu",
                detail: "Host fallback menu"
            ),
            MainMenuWidgetRef(
                id: "builtin:status-rail",
                pluginID: nil,
                pluginName: "QuakeKit",
                viewID: nil,
                title: "Status Rail",
                detail: "RC2 default · persistent left navigation rail"
            ),
            MainMenuWidgetRef(
                id: "builtin:radial-orbit",
                pluginID: nil,
                pluginName: "QuakeKit",
                viewID: nil,
                title: "Radial Orbit",
                detail: "RC2 alternate · hub and orbit navigation"
            ),
            MainMenuWidgetRef(
                id: "builtin:ambient-marquee",
                pluginID: nil,
                pluginName: "QuakeKit",
                viewID: nil,
                title: "Ambient Marquee",
                detail: "RC2 alternate · ambient hero and bottom dock"
            )
        ] + packaged.sorted { $0.title < $1.title }
    }

    private static func mainMenuTiles(
        from packages: [PluginPackage],
        selectedMenuID: String,
        widgetCount: Int,
        appCount: Int,
        themeCount: Int
    ) -> [ShellTile] {
        if selectedMenuID != MainMenuWidgetRef.builtInID,
           let package = packages.first(where: { package in
               package.manifest.views.contains { "\(package.manifest.id):\($0.id)" == selectedMenuID && $0.presentation == .mainMenu }
           }),
           let view = package.manifest.views.first(where: { "\(package.manifest.id):\($0.id)" == selectedMenuID && $0.presentation == .mainMenu }),
           !view.menuItems.isEmpty {
            let tiles = view.menuItems
                .sorted { ($0.order ?? 0, $0.title) < ($1.order ?? 0, $1.title) }
                .map { menuTile(from: $0, package: package) }
            if !tiles.isEmpty {
                return tiles
            }
        }
        return builtInMainMenuTiles(widgetCount: widgetCount, appCount: appCount, themeCount: themeCount)
    }

    private static func builtInMainMenuTiles(widgetCount: Int, appCount: Int, themeCount: Int) -> [ShellTile] {
        [
            ShellTile(title: "Runtime", subtitle: "Live device and host state", action: .openPage(5), icon: "waveform.path.ecg"),
            ShellTile(title: "Widgets", subtitle: "\(widgetCount) installed views", action: .openPage(1), icon: "square.grid.2x2"),
            ShellTile(title: "Apps", subtitle: "\(appCount) applets and actions", action: .openPage(2), icon: "app.dashed"),
            ShellTile(title: "Themes", subtitle: "\(themeCount) installed themes", action: .openPage(3), icon: "paintpalette"),
            ShellTile(title: "Settings", subtitle: "Panel, menu, and plugin configuration", action: .openPage(4), icon: "gearshape"),
            ShellTile(title: "Plugin APIs", subtitle: "Swift · HTML · PHP · shell", action: .openPage(6), icon: "chevron.left.forwardslash.chevron.right")
        ]
    }

    private static func homeWidgetTiles(from widgetTiles: [ShellTile]) -> [ShellTile] {
        let preferred = ["weather", "system_monitor", "music_now_playing", "ai_agent", "native_status"]
        let ordered = preferred.compactMap { id in
            widgetTiles.first { $0.widget?.pluginID == id }
        }
        let remainder = widgetTiles.filter { tile in
            !ordered.contains(where: { $0.widget == tile.widget })
        }
        let tiles = Array((ordered + remainder).prefix(6))
        return tiles.isEmpty ? [ShellTile(title: "No Home Widgets", subtitle: "Install a widget-capable plugin", action: .openPage(1), icon: "square.grid.2x2")] : tiles
    }

    private static func menuTile(from item: PluginMenuItem, package: PluginPackage) -> ShellTile {
        ShellTile(
            title: item.title,
            subtitle: item.subtitle ?? package.manifest.name,
            action: menuAction(from: item),
            icon: item.icon
        )
    }

    private static func menuAction(from item: PluginMenuItem) -> ShellAction {
        switch item.action {
        case "page":
            if let target = item.target, let index = pageIndex(for: target) {
                return .openPage(index)
            }
            return .setStatus("Unknown page \(item.target ?? "-")")
        case "pluginView":
            if let target = item.target {
                let parts = target.split(separator: ":", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    return .openPluginView(pluginID: parts[0], viewID: parts[1])
                }
            }
            return .setStatus("Plugin view target missing")
        case "pluginAction":
            if let target = item.target {
                let parts = target.split(separator: ":", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    return .invokePluginAction(pluginID: parts[0], actionID: parts[1])
                }
            }
            return .setStatus("Plugin action target missing")
        case "carousel":
            switch item.target {
            case "toggle":
                return .toggleCarousel
            case "duration":
                return .editCarouselDuration
            default:
                return .openCarouselSettings
            }
        case "settings":
            if let target = item.target, target.hasPrefix("plugin:") {
                return .openPluginSettings(String(target.dropFirst("plugin:".count)))
            }
            return .openPage(4)
        case "status":
            return .setStatus(item.target ?? item.subtitle ?? item.title)
        default:
            return .setStatus("Unsupported menu action \(item.action)")
        }
    }

    private static func pageIndex(for target: String) -> Int? {
        switch target.lowercased() {
        case "home", "0": return 0
        case "widgets", "1": return 1
        case "apps", "2": return 2
        case "themes", "3": return 3
        case "settings", "4": return 4
        case "runtime", "5": return 5
        case "pluginapis", "plugin_apis", "plugin-apis", "api", "apis", "6": return 6
        default: return nil
        }
    }

    private static func panelLayout(from style: ThemePageStyle?) -> PanelPageLayout {
        switch style {
        case .fullScreen:
            return .fullScreen
        case .halfAndGrid:
            return .halfAndGrid
        case .twoHalves:
            return .twoHalves
        case .thirds:
            return .thirds
        case .quarters:
            return .quarters
        case .grid, .none:
            return .grid
        }
    }

    private static func pluginLanguageTiles() -> [ShellTile] {
        [
            ShellTile(title: "Swift", subtitle: "nativeSwift bundles", action: .setStatus("Swift plugins target native host APIs and future in-process loading"), icon: "swift"),
            ShellTile(title: "HTML", subtitle: "webView/webCanvas", action: .setStatus("HTML plugins render packaged documents or canvas applets"), icon: "globe"),
            ShellTile(title: "PHP", subtitle: "stdio JSON over php", action: .setStatus("PHP plugins run as process adapters with settings in environment variables"), icon: "terminal"),
            ShellTile(title: "Bash", subtitle: "POSIX shell adapters", action: .setStatus("Shell plugins run local process adapters and return JSON payloads"), icon: "chevron.left.forwardslash.chevron.right")
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
                guard presentation != .mainMenu else { return nil }
                guard presentationFilter(presentation) else { return nil }
                let type = view.type?.rawValue ?? package.manifest.entry.transport.rawValue
                return ShellTile(
                    title: view.title,
                    subtitle: "\(package.manifest.name) · \(type)",
                    action: .openPluginView(pluginID: package.manifest.id, viewID: view.id),
                    icon: view.icon ?? defaultIcon(for: package.manifest.id),
                    widget: presentation == .widget || presentation == .pageAndWidget
                        ? WidgetPreviewRef(pluginID: package.manifest.id, viewID: view.id, streamID: view.dataStreamID)
                        : nil
                )
            }
        }

        if !tiles.isEmpty {
            return tiles
        }

        return [
            ShellTile(title: emptyTitle, subtitle: emptySubtitle, action: .setStatus(emptySubtitle), icon: "square.dashed")
        ]
    }

    private static func defaultIcon(for pluginID: String) -> String {
        switch pluginID {
        case "system_monitor": return "gauge.with.dots.needle.67percent"
        case "weather": return "cloud.sun"
        case "music_now_playing": return "music.note"
        case "ai_agent": return "sparkles"
        case "agenda": return "calendar"
        case "timers": return "timer"
        case "markets": return "chart.line.uptrend.xyaxis"
        case "sports_scores": return "sportscourt"
        case "home_assistant": return "house"
        case "octoprint": return "cube.transparent"
        case "security_cameras": return "video"
        case "ubiquiti_network": return "network"
        case "obs_controls": return "dot.radiowaves.left.and.right"
        case "discord_companion": return "bubble.left.and.bubble.right"
        case "hotkey_grid", "affinity_photo_hotkeys": return "command"
        case "affinity_photo2": return "photo"
        case "clipboard_notes": return "doc.on.clipboard"
        case "meeting_notes": return "mic"
        case "terminal_companion", "terminal_companions": return "terminal"
        case "youtube_companion", "youtube_media_companion": return "play.rectangle"
        case "app_context": return "rectangle.on.rectangle"
        default: return "square.grid.2x2"
        }
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

    private static func settingsTiles(
        pluginPackages: [PluginPackage],
        themePackages: [ThemePackage],
        settingsConfiguration: QuakeSettingsConfiguration
    ) -> [ShellTile] {
        var tiles = [
            ShellTile(
                title: "Default Page",
                subtitle: "Page \(settingsConfiguration.defaultPageIndex + 1)",
                action: .editGlobalSetting("defaultPage")
            ),
            ShellTile(
                title: "Carousel",
                subtitle: settingsConfiguration.carousel.enabled ? "Every \(settingsConfiguration.carousel.intervalSeconds)s" : "Off",
                action: .openCarouselSettings
            ),
            ShellTile(
                title: "Plugins",
                subtitle: "\(pluginPackages.count) loaded",
                action: .setStatus("Install plugins with quake-probe --install-package <path>")
            ),
            ShellTile(
                title: "Themes",
                subtitle: "\(themePackages.count) loaded",
                action: .setStatus("Install themes with quake-probe --install-package <path>")
            )
        ]

        tiles.append(contentsOf: pluginPackages.filter { !$0.manifest.settings.isEmpty }.map { package in
            ShellTile(
                title: package.manifest.name,
                subtitle: "\(package.manifest.settings.count) settings",
                action: .openPluginSettings(package.manifest.id)
            )
        })

        return tiles
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
        didSet { updateSelection(); needsLayout = true }
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
    private var gridSubpageIndex = 0
    private var activeThemeIndex = 0
    private var activeTheme: PanelTheme
    private var themeConfiguration: ThemeUserConfiguration
    private var settingsConfiguration: QuakeSettingsConfiguration
    private var pluginDataStore = PluginDataStore()
    private var runtime = RuntimeSnapshot()
    private var carouselTimer: Timer?
    private var carouselIndex = 0
    private var tileViews: [TileCellView] = []
    private var runtimeRows: [StatusRowView] = []
    private var systemDashboardView: SystemMonitorDashboardView?
    private var weatherDashboardView: WeatherDashboardView?
    private var dataBoardView: DataBoardView?
    private var pageLabels: [NSTextField] = []
    private let themeBackgroundView = ThemeBackgroundImageView(frame: .zero)
    private let menuChromeView = MenuChromeView(frame: .zero)
    private let statusLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let previousGridPad = ArrowPadView(direction: .previous)
    private let nextGridPad = ArrowPadView(direction: .next)

    init(frame frameRect: NSRect, pluginPackages: [PluginPackage], themePackages: [ThemePackage], portraitMode: Bool) {
        self.pluginPackages = pluginPackages
        self.pluginRuntime = PluginExecutionHost(packages: pluginPackages)
        self.themePackages = themePackages
        self.portraitMode = portraitMode
        self.themeConfiguration = ThemeConfigurationStore.load()
        self.settingsConfiguration = QuakeSettingsStore.load()
        if let activeThemeID = themeConfiguration.activeThemeID,
           let index = themePackages.firstIndex(where: { $0.manifest.id == activeThemeID }) {
            self.activeThemeIndex = index
        }
        self.pages = ShellCatalog.defaultPages(
            pluginPackages: pluginPackages,
            themePackages: themePackages,
            activeThemeIndex: activeThemeIndex,
            overrides: themeConfiguration.overrides,
            settingsConfiguration: settingsConfiguration
        )
        self.currentPageIndex = min(max(0, settingsConfiguration.defaultPageIndex), max(0, self.pages.count - 1))
        self.activeTheme = themePackages.indices.contains(activeThemeIndex)
            ? PanelTheme.from(themePackages[activeThemeIndex].manifest, overrides: themeConfiguration.overrides)
            : .fallback
        super.init(frame: frameRect)
        wantsLayer = true
        autoresizingMask = [.width, .height]
        layer?.backgroundColor = activeTheme.background.cgColor
        log("PanelView init frame=\(format(frameRect)) portraitMode=\(portraitMode)")
        setupSubviews()
        restartCarousel()
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
        let count = visibleTiles.count
        guard count > 0 else { return }
        let proposedIndex = selectedIndex + delta
        if proposedIndex < 0 {
            if showPreviousGridSubpage() {
                selectedIndex = visibleTiles.count - 1
            }
            return
        }
        if proposedIndex >= count {
            if showNextGridSubpage() {
                selectedIndex = 0
            }
            return
        }
        selectedIndex = proposedIndex
        status = "Selected \(visibleTiles[selectedIndex].title)"
    }

    func activateSelection() {
        guard visibleTiles.indices.contains(selectedIndex) else {
            status = "Runtime page active"
            return
        }
        let tile = visibleTiles[selectedIndex]
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
        case .editGlobalSetting(let id):
            editGlobalSetting(id)
        case .openCarouselSettings:
            openCarouselSettings()
        case .toggleCarousel:
            toggleCarousel()
        case .editCarouselDuration:
            editCarouselDuration()
        case .toggleCarouselWidget(let id):
            toggleCarouselWidget(id)
        case .openPluginSettings(let pluginID):
            openPluginSettings(pluginID: pluginID)
        case .editPluginSetting(let pluginID, let settingID):
            editPluginSetting(pluginID: pluginID, settingID: settingID)
        case .resetPluginSettings(let pluginID):
            resetPluginSettings(pluginID)
        }
    }

    func touch(logicalX: CGFloat, logicalY: CGFloat) {
        let points = touchPointCandidates(logicalX: logicalX, logicalY: logicalY)
        if let pageIndex = points.lazy.compactMap({ self.menuChromeView.navigationIndex(at: $0) }).first {
            log("touch route chrome raw=\(Int(logicalX)),\(Int(logicalY)) page=\(pageIndex)")
            openPage(pageIndex)
            return
        }
        if activeMenuTemplate == .classic,
           let pageIndex = points.lazy.compactMap({ point in self.pageLabels.firstIndex(where: { $0.frame.insetBy(dx: -18, dy: -14).contains(point) }) }).first {
            log("touch route classic-tab raw=\(Int(logicalX)),\(Int(logicalY)) page=\(pageIndex)")
            openPage(pageIndex)
            return
        }
        if activeMenuTemplate == .classic {
            for point in points where point.y > bounds.height - 92 && point.x >= 300 {
                let pageIndex = Int((point.x - 300) / 140)
                if pages.indices.contains(pageIndex) {
                    log("touch route classic-page raw=\(Int(logicalX)),\(Int(logicalY)) page=\(pageIndex)")
                    openPage(pageIndex)
                    return
                }
            }
        }

        guard currentPage.kind == .grid else {
            log("touch route ignored non-grid raw=\(Int(logicalX)),\(Int(logicalY)) page=\(currentPage.title)")
            return
        }
        for point in points {
            if !previousGridPad.isHidden && previousGridPad.frame.contains(point) {
                log("touch route grid-previous raw=\(Int(logicalX)),\(Int(logicalY))")
                _ = showPreviousGridSubpage()
                return
            }
            if !nextGridPad.isHidden && nextGridPad.frame.contains(point) {
                log("touch route grid-next raw=\(Int(logicalX)),\(Int(logicalY))")
                _ = showNextGridSubpage()
                return
            }
        }
        for point in points {
            if let index = tileViews.firstIndex(where: { $0.frame.contains(point) }), visibleTiles.indices.contains(index) {
                // A physical panel tap is an explicit activation, not merely a
                // focus move. Knob rotation remains the focus-selection path.
                selectedIndex = index
                log("touch route tile raw=\(Int(logicalX)),\(Int(logicalY)) candidate=\(Int(point.x)),\(Int(point.y)) tile=\(visibleTiles[index].title)")
                activateSelection()
                return
            }
        }
        let candidateText = points.map { "\(Int($0.x)),\(Int($0.y))" }.joined(separator: " | ")
        log("touch route miss raw=\(Int(logicalX)),\(Int(logicalY)) candidates=[\(candidateText)] page=\(currentPage.title) tiles=\(tileViews.count)")
    }

    /// DK touch coordinates use a top-origin panel space. Menu chrome is drawn
    /// in AppKit's bottom-origin space, so normalize and flip only at that seam.
    private func touchPointCandidates(logicalX: CGFloat, logicalY: CGFloat) -> [NSPoint] {
        let x = normalizedTouchCoordinate(logicalX, panelExtent: 1920, viewExtent: bounds.width)
        let topOriginY = normalizedTouchCoordinate(logicalY, panelExtent: 480, viewExtent: bounds.height)
        let points = [
            NSPoint(x: x, y: bounds.height - topOriginY),
            NSPoint(x: x, y: topOriginY),
            NSPoint(x: logicalX, y: logicalY)
        ]
        return points.reduce(into: []) { result, point in
            if !result.contains(where: { abs($0.x - point.x) < 0.5 && abs($0.y - point.y) < 0.5 }) {
                result.append(point)
            }
        }
    }

    private func normalizedTouchCoordinate(_ value: CGFloat, panelExtent: CGFloat, viewExtent: CGFloat) -> CGFloat {
        guard panelExtent > 0, viewExtent > 0 else { return value }
        if value > panelExtent * 1.1 {
            // Some macOS HID collections expose a 12-bit axis instead of pixels.
            let rawExtent: CGFloat = value <= 4095 ? 4095 : 65535
            return min(max(0, value / rawExtent * viewExtent), viewExtent)
        }
        return min(max(0, value / panelExtent * viewExtent), viewExtent)
    }

    func nextPage() {
        openPage((currentPageIndex + 1) % pages.count)
    }

    func reloadConfigurationsFromDisk() {
        themeConfiguration = ThemeConfigurationStore.load()
        settingsConfiguration = QuakeSettingsStore.load()
        if let activeThemeID = themeConfiguration.activeThemeID,
           let index = themePackages.firstIndex(where: { $0.manifest.id == activeThemeID }) {
            activeThemeIndex = index
        }
        activeTheme = themePackages.indices.contains(activeThemeIndex)
            ? PanelTheme.from(themePackages[activeThemeIndex].manifest, overrides: themeConfiguration.overrides)
            : .fallback
        rebuildPages()
        currentPageIndex = min(max(0, currentPageIndex), max(0, pages.count - 1))
        status = "Settings reloaded"
        restartCarousel()
        rebuildPageContent()
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
        themeBackgroundView.autoresizingMask = [.width, .height]
        addSubview(themeBackgroundView)

        menuChromeView.autoresizingMask = [.width, .height]
        addSubview(menuChromeView)

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
        previousGridPad.theme = activeTheme
        nextGridPad.theme = activeTheme
        previousGridPad.isHidden = true
        nextGridPad.isHidden = true
        addSubview(previousGridPad)
        addSubview(nextGridPad)
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
        gridSubpageIndex = 0
        selectedIndex = 0
        status = "Page \(pages[index].title)"
        log("shell page \(index): \(pages[index].title)")
        rebuildPageContent()
    }

    private func rebuildPageContent() {
        tileViews.forEach { $0.removeFromSuperview() }
        runtimeRows.forEach { $0.removeFromSuperview() }
        systemDashboardView?.removeFromSuperview()
        weatherDashboardView?.removeFromSuperview()
        dataBoardView?.removeFromSuperview()
        tileViews.removeAll()
        runtimeRows.removeAll()
        systemDashboardView = nil
        weatherDashboardView = nil
        dataBoardView = nil
        previousGridPad.isHidden = true
        nextGridPad.isHidden = true

        switch currentPage.kind {
        case .grid:
            clampGridSubpage()
            refreshWidgetPreviews(for: visibleTiles)
            tileViews = visibleTiles.map { tile in
                let view = TileCellView(
                    tile: tile,
                    preview: widgetPreview(for: tile),
                    orbitMode: activeMenuTemplate == .radialOrbit,
                    theme: activeTheme
                )
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
            if pluginID == "system_monitor", viewID == "system.overview" {
                let view = SystemMonitorDashboardView(snapshot: systemMonitorSnapshot(), theme: activeTheme)
                view.translatesAutoresizingMaskIntoConstraints = true
                addSubview(view)
                systemDashboardView = view
            } else if pluginID == "weather", viewID == "weather.canvas" {
                let view = WeatherDashboardView(snapshot: weatherSnapshot(), theme: activeTheme)
                view.translatesAutoresizingMaskIntoConstraints = true
                addSubview(view)
                weatherDashboardView = view
            } else if let dataBoard = dataBoardSnapshot(pluginID: pluginID, viewID: viewID) {
                let view = DataBoardView(snapshot: dataBoard, theme: activeTheme)
                view.translatesAutoresizingMaskIntoConstraints = true
                addSubview(view)
                dataBoardView = view
            } else {
                runtimeRows = pluginViewRows(pluginID: pluginID, viewID: viewID).map { row in
                    let view = StatusRowView(title: row.title, value: row.value, theme: activeTheme)
                    view.translatesAutoresizingMaskIntoConstraints = true
                    addSubview(view)
                    return view
                }
            }
        }

        updateSelection()
        updateChrome()
        updateStatus()
        needsLayout = true
    }

    private func layoutChrome() {
        menuChromeView.frame = bounds
        let usesTemplateChrome = activeMenuTemplate != .classic
        titleLabel.isHidden = usesTemplateChrome
        statusLabel.isHidden = usesTemplateChrome
        let inset: CGFloat = 16
        themeBackgroundView.frame = bounds
        titleLabel.frame = NSRect(x: inset, y: bounds.height - 46, width: 280, height: 30)
        let tabY = bounds.height - 48
        for (index, label) in pageLabels.enumerated() {
            label.isHidden = usesTemplateChrome
            label.frame = NSRect(x: 320 + CGFloat(index) * 120, y: tabY, width: 104, height: 28)
        }
        statusLabel.frame = NSRect(x: inset + 4, y: 8, width: bounds.width - (inset + 4) * 2, height: 24)
        layoutGridPads()
    }

    private func layoutContent() {
        let contentRect = menuChromeView.contentRect(in: bounds)
        if let systemDashboardView {
            systemDashboardView.frame = contentRect
            return
        }
        if let weatherDashboardView {
            weatherDashboardView.frame = contentRect
            return
        }
        if let dataBoardView {
            dataBoardView.frame = contentRect
            return
        }
        if currentPage.kind == .runtimeStatus || isPluginView(currentPage.kind) {
            layoutRuntimeRows(in: contentRect)
            return
        }
        var gridRect = contentRect
        if gridSubpageCount > 1 {
            gridRect = gridRect.insetBy(dx: 36, dy: 0)
        }
        layoutTiles(in: gridRect)
        updateGridPads()
    }

    private func layoutTiles(in rect: NSRect) {
        if activeMenuTemplate == .radialOrbit {
            layoutOrbitTiles(in: rect)
            return
        }
        if activeMenuTemplate == .ambientMarquee && currentPage.title == "Home" {
            layoutTileGrid(indices: Array(tileViews.indices), in: rect, columns: 2, rows: 3)
            return
        }
        switch currentPage.layout {
        case .grid:
            layoutTileGrid(indices: Array(tileViews.indices), in: rect, columns: columns, rows: rows)
        case .fullScreen:
            for index in tileViews.indices {
                tileViews[index].frame = index == 0 ? rect : .zero
            }
        case .halfAndGrid:
            layoutHalfAndGrid(in: rect)
        case .twoHalves:
            layoutTileGrid(indices: Array(tileViews.indices), in: rect, columns: 2, rows: 1)
        case .thirds:
            layoutTileGrid(indices: Array(tileViews.indices), in: rect, columns: 3, rows: 1)
        case .quarters:
            layoutTileGrid(indices: Array(tileViews.indices), in: rect, columns: 2, rows: 2)
        }
    }

    private func layoutOrbitTiles(in rect: NSRect) {
        let pitch: CGFloat = 74
        let centerY = rect.midY
        for index in tileViews.indices {
            let distance = index - selectedIndex
            guard abs(distance) <= 3 else {
                tileViews[index].frame = .zero
                continue
            }
            let scale = max(0.68, 1 - CGFloat(abs(distance)) * 0.12)
            let height: CGFloat = 60 * scale
            let width: CGFloat = min(rect.width - 12, 520 * scale)
            let x = rect.minX + CGFloat(abs(distance)) * 30
            let y = centerY - height / 2 - CGFloat(distance) * pitch
            tileViews[index].frame = NSRect(x: x, y: y, width: width, height: height)
        }
    }

    private func layoutHalfAndGrid(in rect: NSRect) {
        guard !tileViews.isEmpty else { return }
        let gap = activeTheme.spacing
        let featureWidth = floor((rect.width - gap) * 0.48)
        let gridRect = NSRect(
            x: rect.minX + featureWidth + gap,
            y: rect.minY,
            width: rect.width - featureWidth - gap,
            height: rect.height
        )
        tileViews[0].frame = NSRect(x: rect.minX, y: rect.minY, width: featureWidth, height: rect.height)
        if tileViews.count > 1 {
            layoutTileGrid(indices: Array(tileViews.indices.dropFirst()), in: gridRect, columns: 2, rows: 3)
        }
    }

    private func layoutTileGrid(indices: [Int], in rect: NSRect, columns: Int, rows: Int) {
        guard columns > 0, rows > 0 else { return }
        let gap = activeTheme.spacing
        let tileWidth = (rect.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let tileHeight = (rect.height - gap * CGFloat(rows - 1)) / CGFloat(rows)

        for (offset, index) in indices.enumerated() where tileViews.indices.contains(index) {
            let column = offset % columns
            let row = offset / columns
            if row >= rows {
                tileViews[index].frame = .zero
                continue
            }
            let x = rect.minX + CGFloat(column) * (tileWidth + gap)
            let y = rect.maxY - CGFloat(row + 1) * tileHeight - CGFloat(row) * gap
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
        let usesTemplateChrome = activeMenuTemplate != .classic
        titleLabel.isHidden = usesTemplateChrome
        statusLabel.isHidden = usesTemplateChrome
        pageLabels.forEach { $0.isHidden = usesTemplateChrome }
        titleLabel.stringValue = "QuakeKit"
        titleLabel.textColor = activeTheme.textPrimary
        layer?.backgroundColor = activeTheme.background.cgColor
        themeBackgroundView.configure(package: activeThemePackage)
        menuChromeView.template = activeMenuTemplate
        menuChromeView.theme = activeTheme
        menuChromeView.pages = pages
        menuChromeView.selectedPageIndex = currentPageIndex
        menuChromeView.status = status
        menuChromeView.menuSettings = settingsConfiguration.menuSettings
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
        systemDashboardView?.theme = activeTheme
        weatherDashboardView?.theme = activeTheme
        dataBoardView?.theme = activeTheme
        previousGridPad.theme = activeTheme
        nextGridPad.theme = activeTheme
    }

    private func updateStatus() {
        let pong = runtime.lastPong.map { " · pong \(Int(Date().timeIntervalSince($0)))s ago" } ?? ""
        statusLabel.stringValue = "\(currentPage.title) · \(status)\(pong)"
        menuChromeView.status = "\(currentPage.title) · \(status)\(pong)"
    }

    private var activeMenuTemplate: PanelMenuTemplate {
        PanelMenuTemplate(menuID: settingsConfiguration.mainMenuViewID)
    }

    private func updateRuntimeRows() {
        guard currentPage.kind == .runtimeStatus else { return }
        let rows = RuntimeStatusModel.rows(from: runtime)
        for index in runtimeRows.indices where rows.indices.contains(index) {
            runtimeRows[index].value = rows[index].value
        }
    }

    private var tilesPerGridSubpage: Int {
        switch currentPage.layout {
        case .grid:
            return columns * rows
        case .fullScreen:
            return 1
        case .halfAndGrid:
            return 7
        case .twoHalves:
            return 2
        case .thirds:
            return 3
        case .quarters:
            return 4
        }
    }

    private var gridSubpageCount: Int {
        guard currentPage.kind == .grid else { return 1 }
        return max(1, Int(ceil(Double(currentPage.tiles.count) / Double(tilesPerGridSubpage))))
    }

    private var visibleTiles: [ShellTile] {
        guard currentPage.kind == .grid else { return currentPage.tiles }
        let start = gridSubpageIndex * tilesPerGridSubpage
        guard start < currentPage.tiles.count else { return [] }
        let end = min(currentPage.tiles.count, start + tilesPerGridSubpage)
        return Array(currentPage.tiles[start..<end])
    }

    private func clampGridSubpage() {
        gridSubpageIndex = min(max(0, gridSubpageIndex), gridSubpageCount - 1)
        selectedIndex = min(max(0, selectedIndex), max(0, visibleTiles.count - 1))
    }

    @discardableResult
    private func showPreviousGridSubpage() -> Bool {
        guard currentPage.kind == .grid, gridSubpageIndex > 0 else { return false }
        gridSubpageIndex -= 1
        selectedIndex = 0
        status = "Page \(currentPage.title) \(gridSubpageIndex + 1)/\(gridSubpageCount)"
        rebuildPageContent()
        return true
    }

    @discardableResult
    private func showNextGridSubpage() -> Bool {
        guard currentPage.kind == .grid, gridSubpageIndex + 1 < gridSubpageCount else { return false }
        gridSubpageIndex += 1
        selectedIndex = 0
        status = "Page \(currentPage.title) \(gridSubpageIndex + 1)/\(gridSubpageCount)"
        rebuildPageContent()
        return true
    }

    private func layoutGridPads() {
        let padWidth: CGFloat = 28
        previousGridPad.frame = NSRect(x: 0, y: 58, width: padWidth, height: max(60, bounds.height - 96))
        nextGridPad.frame = NSRect(x: bounds.width - padWidth, y: 58, width: padWidth, height: max(60, bounds.height - 96))
    }

    private func updateGridPads() {
        let hasOverflow = currentPage.kind == .grid && gridSubpageCount > 1
        previousGridPad.isHidden = !hasOverflow || gridSubpageIndex == 0
        nextGridPad.isHidden = !hasOverflow || gridSubpageIndex + 1 >= gridSubpageCount
        previousGridPad.needsDisplay = true
        nextGridPad.needsDisplay = true
    }

    private func openPluginView(pluginID: String, viewID: String) {
        guard let package = pluginPackages.first(where: { $0.manifest.id == pluginID }),
              let view = package.manifest.views.first(where: { $0.id == viewID }) else {
            status = "Plugin view missing"
            return
        }
        transientPage = ShellPage(
            title: view.title,
            kind: .pluginView(pluginID: pluginID, viewID: viewID),
            layout: panelLayout(for: view),
            tiles: []
        )
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

        let entrypoint = view.entryPath
            ?? package.manifest.entry.url?.relativeString
            ?? package.manifest.entry.command
            ?? "-"
        let preferredWidth = view.preferredWidth ?? 0
        let preferredHeight = view.preferredHeight ?? 0

        var rows: [(title: String, value: String)] = [
            ("Plugin", package.manifest.name),
            ("View", view.title),
            ("Type", view.type?.rawValue ?? "unspecified"),
            ("Presentation", view.presentation?.rawValue ?? "page"),
            ("Layout", view.layout?.rawValue ?? "host default"),
            ("Entrypoint", entrypoint),
            ("Data Stream", view.dataStreamID ?? "-"),
            ("Preferred Size", "\(preferredWidth)x\(preferredHeight)"),
            ("Package", package.baseURL.lastPathComponent)
        ]

        if let streamID = view.dataStreamID, let snapshot = pluginDataStore.snapshot(pluginID: pluginID, streamID: streamID) {
            rows.append(contentsOf: dataRows(from: snapshot.payload))
            rows.append(("Updated", relativeTime(snapshot.timestamp)))
        }

        return rows
    }

    private func dataRows(from value: JSONValue) -> [(title: String, value: String)] {
        guard case .object(let object) = value else {
            return [("Latest Data", summarize(value))]
        }

        return object.keys.sorted().prefix(10).map { key in
            (title: titleize(key), value: display(object[key] ?? .null))
        }
    }

    private func systemMonitorSnapshot() -> SystemMonitorSnapshot {
        guard let snapshot = pluginDataStore.snapshot(pluginID: "system_monitor", streamID: "system.metrics") else {
            return .placeholder
        }
        return SystemMonitorSnapshot(value: snapshot.payload, timestamp: snapshot.timestamp)
    }

    private func weatherSnapshot() -> WeatherSnapshot {
        guard let snapshot = pluginDataStore.snapshot(pluginID: "weather", streamID: "weather.current") else {
            return .placeholder
        }
        return WeatherSnapshot(value: snapshot.payload, timestamp: snapshot.timestamp)
    }

    private func dataBoardSnapshot(pluginID: String, viewID: String) -> DataBoardSnapshot? {
        guard let package = pluginPackages.first(where: { $0.manifest.id == pluginID }),
              let view = package.manifest.views.first(where: { $0.id == viewID }),
              view.type == .dataDriven || view.dataStreamID != nil else {
            return nil
        }
        let snapshot = view.dataStreamID.flatMap { pluginDataStore.snapshot(pluginID: pluginID, streamID: $0) }
        return DataBoardSnapshot(
            pluginName: package.manifest.name,
            viewTitle: view.title,
            value: snapshot?.payload,
            timestamp: snapshot?.timestamp
        )
    }

    private func refreshData(for view: PluginView, package: PluginPackage) {
        guard let streamID = view.dataStreamID, let action = package.manifest.actions.first else { return }
        let result = pluginRuntime.invokeAction(
            pluginID: package.manifest.id,
            actionID: action.id,
            settings: settingsConfiguration.pluginSettings[package.manifest.id] ?? [:]
        )
        if let payload = result.response.result, result.response.ok {
            pluginDataStore.set(pluginID: package.manifest.id, streamID: streamID, payload: payload)
        } else if let error = result.response.error {
            status = "\(package.manifest.id): \(error)"
        }
    }

    private func refreshWidgetPreviews(for tiles: [ShellTile]) {
        var refreshed = Set<String>()
        for tile in tiles {
            guard let ref = tile.widget,
                  let package = pluginPackages.first(where: { $0.manifest.id == ref.pluginID }),
                  let view = package.manifest.views.first(where: { $0.id == ref.viewID }),
                  view.dataStreamID != nil else { continue }
            let key = "\(ref.pluginID):\(ref.viewID)"
            guard refreshed.insert(key).inserted else { continue }
            refreshData(for: view, package: package)
        }
    }

    private func widgetPreview(for tile: ShellTile) -> WidgetPreviewData? {
        guard let ref = tile.widget,
              let streamID = ref.streamID,
              let snapshot = pluginDataStore.snapshot(pluginID: ref.pluginID, streamID: streamID) else {
            return nil
        }
        return WidgetPreviewData.from(snapshot.payload)
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

    private func editGlobalSetting(_ id: String) {
        switch id {
        case "defaultPage":
            settingsConfiguration.defaultPageIndex = (settingsConfiguration.defaultPageIndex + 1) % max(1, pages.count)
            QuakeSettingsStore.save(settingsConfiguration)
            rebuildPages()
            status = "Default page: \(pages[settingsConfiguration.defaultPageIndex].title)"
            rebuildPageContent()
        default:
            status = "Unknown setting \(id)"
        }
    }

    private func openCarouselSettings() {
        transientPage = ShellPage(title: "Carousel", kind: .grid, tiles: carouselTiles())
        selectedIndex = 0
        gridSubpageIndex = 0
        status = "Carousel settings"
        rebuildPageContent()
    }

    private func carouselTiles() -> [ShellTile] {
        let refs = carouselWidgetRefs()
        var tiles = [
            ShellTile(
                title: "Enabled",
                subtitle: settingsConfiguration.carousel.enabled ? "On" : "Off",
                action: .toggleCarousel
            ),
            ShellTile(
                title: "Duration",
                subtitle: "\(settingsConfiguration.carousel.intervalSeconds)s per widget",
                action: .editCarouselDuration
            )
        ]

        tiles.append(contentsOf: refs.map { ref in
            let included = carouselIncludedWidgetIDs().contains(ref.id)
            return ShellTile(
                title: included ? "\(ref.title) *" : ref.title,
                subtitle: "\(ref.pluginName) · \(included ? "included" : "skipped")",
                action: .toggleCarouselWidget(ref.id)
            )
        })
        return tiles
    }

    private func toggleCarousel() {
        settingsConfiguration.carousel.enabled.toggle()
        QuakeSettingsStore.save(settingsConfiguration)
        rebuildPages()
        refreshCarouselTransientPage()
        restartCarousel()
        status = "Carousel \(settingsConfiguration.carousel.enabled ? "on" : "off")"
    }

    private func editCarouselDuration() {
        let choices = [5, 10, 15, 30, 60]
        let currentIndex = choices.firstIndex(of: settingsConfiguration.carousel.intervalSeconds) ?? 2
        settingsConfiguration.carousel.intervalSeconds = choices[(currentIndex + 1) % choices.count]
        QuakeSettingsStore.save(settingsConfiguration)
        rebuildPages()
        refreshCarouselTransientPage()
        restartCarousel()
        status = "Carousel duration \(settingsConfiguration.carousel.intervalSeconds)s"
    }

    private func toggleCarouselWidget(_ id: String) {
        var ids = carouselIncludedWidgetIDs()
        if ids.contains(id) {
            ids.removeAll { $0 == id }
        } else {
            ids.append(id)
        }
        settingsConfiguration.carousel.widgetIDs = ids
        QuakeSettingsStore.save(settingsConfiguration)
        refreshCarouselTransientPage()
        restartCarousel()
        status = "Carousel widgets \(ids.count)"
    }

    private func refreshCarouselTransientPage() {
        if transientPage?.title == "Carousel" {
            transientPage = ShellPage(title: "Carousel", kind: .grid, tiles: carouselTiles())
            rebuildPageContent()
        }
    }

    private func restartCarousel() {
        carouselTimer?.invalidate()
        carouselTimer = nil
        guard settingsConfiguration.carousel.enabled, !carouselWidgetRefs().isEmpty else { return }
        let interval = TimeInterval(max(5, settingsConfiguration.carousel.intervalSeconds))
        carouselTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.advanceCarousel()
            }
        }
    }

    private func advanceCarousel() {
        let refs = carouselWidgetRefs().filter { carouselIncludedWidgetIDs().contains($0.id) }
        guard !refs.isEmpty else { return }
        let ref = refs[carouselIndex % refs.count]
        carouselIndex = (carouselIndex + 1) % refs.count
        openPluginView(pluginID: ref.pluginID, viewID: ref.viewID)
        status = "Carousel \(ref.title)"
    }

    private func carouselIncludedWidgetIDs() -> [String] {
        let explicit = settingsConfiguration.carousel.widgetIDs
        if !explicit.isEmpty { return explicit }
        return carouselWidgetRefs().map(\.id)
    }

    private func carouselWidgetRefs() -> [CarouselWidgetRef] {
        pluginPackages.flatMap { package in
            package.manifest.views.compactMap { view in
                let presentation = view.presentation ?? .page
                guard presentation != .mainMenu else { return nil }
                guard presentation == .widget || presentation == .pageAndWidget else { return nil }
                return CarouselWidgetRef(
                    id: "\(package.manifest.id):\(view.id)",
                    pluginID: package.manifest.id,
                    pluginName: package.manifest.name,
                    viewID: view.id,
                    title: view.title
                )
            }
        }
    }

    private func openPluginSettings(pluginID: String) {
        guard let package = pluginPackages.first(where: { $0.manifest.id == pluginID }) else {
            status = "Plugin settings missing"
            return
        }
        transientPage = ShellPage(
            title: "\(package.manifest.name) Settings",
            kind: .grid,
            tiles: pluginSettingsTiles(for: package)
        )
        selectedIndex = 0
        gridSubpageIndex = 0
        status = "\(package.manifest.name) settings"
        rebuildPageContent()
    }

    private func pluginSettingsTiles(for package: PluginPackage) -> [ShellTile] {
        var tiles = package.manifest.settings.map { setting in
            ShellTile(
                title: setting.title,
                subtitle: settingSubtitle(setting, pluginID: package.manifest.id),
                action: .editPluginSetting(pluginID: package.manifest.id, settingID: setting.id)
            )
        }
        tiles.append(ShellTile(
            title: "Reset",
            subtitle: "Restore defaults",
            action: .resetPluginSettings(package.manifest.id)
        ))
        return tiles
    }

    private func editPluginSetting(pluginID: String, settingID: String) {
        guard let package = pluginPackages.first(where: { $0.manifest.id == pluginID }),
              let setting = package.manifest.settings.first(where: { $0.id == settingID }) else {
            status = "Missing plugin setting"
            return
        }
        let value = nextValue(for: setting, pluginID: pluginID)
        settingsConfiguration.pluginSettings[pluginID, default: [:]][setting.id] = value
        QuakeSettingsStore.save(settingsConfiguration)
        rebuildPages()
        if transientPage?.title == "\(package.manifest.name) Settings" {
            transientPage = ShellPage(title: "\(package.manifest.name) Settings", kind: .grid, tiles: pluginSettingsTiles(for: package))
        }
        status = "\(setting.title): \(display(value))"
        rebuildPageContent()
    }

    private func resetPluginSettings(_ pluginID: String) {
        guard let package = pluginPackages.first(where: { $0.manifest.id == pluginID }) else {
            status = "Plugin settings missing"
            return
        }
        settingsConfiguration.pluginSettings[pluginID] = nil
        QuakeSettingsStore.save(settingsConfiguration)
        rebuildPages()
        transientPage = ShellPage(title: "\(package.manifest.name) Settings", kind: .grid, tiles: pluginSettingsTiles(for: package))
        status = "\(package.manifest.name) settings reset"
        rebuildPageContent()
    }

    private func invokePluginAction(pluginID: String, actionID: String) {
        let result = pluginRuntime.invokeAction(
            pluginID: pluginID,
            actionID: actionID,
            settings: settingsConfiguration.pluginSettings[pluginID] ?? [:]
        )
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

    private var activeThemePackage: ThemePackage? {
        guard themePackages.indices.contains(activeThemeIndex) else { return nil }
        return themePackages[activeThemeIndex]
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
            overrides: themeConfiguration.overrides,
            settingsConfiguration: settingsConfiguration
        )
        currentPageIndex = min(max(0, currentPageIndex), max(0, pages.count - 1))
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

    private func nextValue(for setting: PluginSetting, pluginID: String) -> JSONValue {
        let current = settingsConfiguration.pluginSettings[pluginID]?[setting.id] ?? setting.defaultValue
        switch setting.type {
        case .choice:
            guard !setting.choices.isEmpty else { return setting.defaultValue }
            let currentIndex = setting.choices.firstIndex(of: current) ?? 0
            return setting.choices[(currentIndex + 1) % setting.choices.count]
        case .boolean:
            return .bool(!(current.boolValue ?? setting.defaultValue.boolValue ?? false))
        case .integer:
            let minimum = Int(setting.minimum ?? 0)
            let maximum = Int(setting.maximum ?? Double(max(minimum + 1, 10)))
            let next = (current.integerValue ?? minimum) + 1
            return .integer(next > maximum ? minimum : next)
        case .number:
            let minimum = setting.minimum ?? 0
            let maximum = setting.maximum ?? max(minimum + 1, 10)
            let steps = 5
            let currentValue = current.doubleValue ?? minimum
            let normalized = maximum == minimum ? 0 : (currentValue - minimum) / (maximum - minimum)
            let currentIndex = min(steps - 1, max(0, Int((normalized * Double(steps - 1)).rounded())))
            let index = (currentIndex + 1) % steps
            return .double(minimum + (maximum - minimum) * Double(index) / Double(steps - 1))
        case .string, .secret:
            return setting.defaultValue
        }
    }

    private func settingSubtitle(_ setting: PluginSetting, pluginID: String) -> String {
        let value = settingsConfiguration.pluginSettings[pluginID]?[setting.id] ?? setting.defaultValue
        switch setting.type {
        case .choice:
            return "\(display(value)) · \(setting.choices.count) choices"
        case .boolean:
            return display(value)
        case .integer, .number:
            let range = [setting.minimum, setting.maximum].compactMap { $0.map { String($0) } }.joined(separator: "...")
            return range.isEmpty ? display(value) : "\(display(value)) · range \(range)"
        case .string:
            return display(value)
        case .secret:
            return "configured"
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

    private func titleize(_ key: String) -> String {
        let spaced = key.reduce(into: "") { result, character in
            if character.isUppercase && !result.isEmpty {
                result.append(" ")
            }
            result.append(character == "_" || character == "-" ? " " : character)
        }
        return spaced
            .split(separator: " ")
            .map { word in word.prefix(1).uppercased() + String(word.dropFirst()) }
            .joined(separator: " ")
    }

    private func isPluginView(_ kind: ShellPage.Kind) -> Bool {
        if case .pluginView = kind { return true }
        return false
    }

    private func panelLayout(for view: PluginView) -> PanelPageLayout {
        switch view.layout {
        case .fullScreen:
            return .fullScreen
        case .halfLeading, .halfTrailing, .halfAndGrid:
            return .halfAndGrid
        case .twoHalves:
            return .twoHalves
        case .thirds:
            return .thirds
        case .quarters:
            return .quarters
        case .grid, .none:
            return .grid
        }
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

final class ThemeBackgroundImageView: NSView {
    private var image: NSImage?
    private var fit: ThemeAsset.ImageFit = .cover
    private var opacity: CGFloat = 0.28
    private var assetKey: String?

    func configure(package: ThemePackage?) {
        guard let package,
              let asset = package.manifest.assets.first(where: { $0.kind == .image && ($0.role == .background || $0.role == nil) }) else {
            image = nil
            assetKey = nil
            needsDisplay = true
            return
        }

        let key = "\(package.manifest.id):\(asset.path)"
        if key != assetKey {
            image = NSImage(contentsOf: package.baseURL.appendingPathComponent(asset.path))
            assetKey = key
        }
        fit = asset.fit ?? .cover
        opacity = CGFloat(min(1, max(0, asset.opacity ?? 0.28)))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let image, image.size.width > 0, image.size.height > 0 else { return }
        let target = targetRect(for: image.size)
        image.draw(in: target, from: NSRect(origin: .zero, size: image.size), operation: .sourceOver, fraction: opacity)
    }

    private func targetRect(for imageSize: NSSize) -> NSRect {
        switch fit {
        case .stretch:
            return bounds
        case .center:
            return NSRect(
                x: bounds.midX - imageSize.width / 2,
                y: bounds.midY - imageSize.height / 2,
                width: imageSize.width,
                height: imageSize.height
            )
        case .contain, .cover, .tile:
            let scaleX = bounds.width / imageSize.width
            let scaleY = bounds.height / imageSize.height
            let scale = fit == .contain ? min(scaleX, scaleY) : max(scaleX, scaleY)
            let size = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
            return NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
        }
    }
}

final class SettingsPlaceholderView: NSView {
    private let titleLabel = NSTextField(labelWithString: "QuakeKit Settings")
    private let tabsLabel = NSTextField(labelWithString: "Global   Themes   Widgets & Apps   Carousel   About")
    private let bodyLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        titleLabel.font = NSFont.systemFont(ofSize: 28, weight: .bold)
        titleLabel.backgroundColor = .clear
        addSubview(titleLabel)

        tabsLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        tabsLabel.textColor = .secondaryLabelColor
        tabsLabel.backgroundColor = .clear
        addSubview(tabsLabel)

        bodyLabel.stringValue = """
        This is the primary-monitor configuration surface for the release app.

        Planned controls:
        - Global launch, display ownership, and panel behavior
        - Theme selection, color overrides, and theme package install/remove
        - Widget/app enablement, settings, install/remove, and permissions
        - Carousel widget set, ordering, and rotation duration
        - About, diagnostics, device firmware, and logs
        """
        bodyLabel.font = NSFont.systemFont(ofSize: 15, weight: .regular)
        bodyLabel.textColor = .labelColor
        bodyLabel.backgroundColor = .clear
        bodyLabel.maximumNumberOfLines = 0
        addSubview(bodyLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 28
        titleLabel.frame = NSRect(x: inset, y: bounds.height - 64, width: bounds.width - inset * 2, height: 36)
        tabsLabel.frame = NSRect(x: inset, y: bounds.height - 98, width: bounds.width - inset * 2, height: 22)
        bodyLabel.frame = NSRect(x: inset, y: 28, width: bounds.width - inset * 2, height: bounds.height - 140)
    }
}

struct SystemMonitorProcess: Equatable {
    var pid: Int
    var name: String
    var cpu: Double
    var memory: Double
}

struct SystemMonitorVolume: Equatable {
    var name: String
    var usedPercent: Double
    var usedGB: Double
    var totalGB: Double
}

struct SystemMonitorSnapshot: Equatable {
    var cpu: Double
    var cpuUser: Double
    var cpuSystem: Double
    var memory: Double
    var memoryMode: String
    var disk: Double
    var hasBattery: Bool
    var battery: Double
    var loadAverage: String
    var loadHistory: [Double]
    var cores: Int
    var processes: Int
    var runningProcesses: Int
    var threads: Int
    var networkInGB: Double
    var networkOutGB: Double
    var diskReadGB: Double
    var diskWrittenGB: Double
    var diskUsedGB: Double
    var diskTotalGB: Double
    var volumes: [SystemMonitorVolume]
    var uptimeSeconds: Int
    var topProcesses: [SystemMonitorProcess]
    var timestamp: Date?

    init(
        cpu: Double,
        cpuUser: Double,
        cpuSystem: Double,
        memory: Double,
        memoryMode: String,
        disk: Double,
        hasBattery: Bool,
        battery: Double,
        loadAverage: String,
        loadHistory: [Double],
        cores: Int,
        processes: Int,
        runningProcesses: Int,
        threads: Int,
        networkInGB: Double,
        networkOutGB: Double,
        diskReadGB: Double,
        diskWrittenGB: Double,
        diskUsedGB: Double,
        diskTotalGB: Double,
        volumes: [SystemMonitorVolume],
        uptimeSeconds: Int,
        topProcesses: [SystemMonitorProcess],
        timestamp: Date?
    ) {
        self.cpu = cpu
        self.cpuUser = cpuUser
        self.cpuSystem = cpuSystem
        self.memory = memory
        self.memoryMode = memoryMode
        self.disk = disk
        self.hasBattery = hasBattery
        self.battery = battery
        self.loadAverage = loadAverage
        self.loadHistory = loadHistory
        self.cores = cores
        self.processes = processes
        self.runningProcesses = runningProcesses
        self.threads = threads
        self.networkInGB = networkInGB
        self.networkOutGB = networkOutGB
        self.diskReadGB = diskReadGB
        self.diskWrittenGB = diskWrittenGB
        self.diskUsedGB = diskUsedGB
        self.diskTotalGB = diskTotalGB
        self.volumes = volumes
        self.uptimeSeconds = uptimeSeconds
        self.topProcesses = topProcesses
        self.timestamp = timestamp
    }

    static let placeholder = SystemMonitorSnapshot(
        cpu: 0,
        cpuUser: 0,
        cpuSystem: 0,
        memory: 0,
        memoryMode: "used",
        disk: 0,
        hasBattery: false,
        battery: 0,
        loadAverage: "-",
        loadHistory: [0, 0, 0, 0],
        cores: 0,
        processes: 0,
        runningProcesses: 0,
        threads: 0,
        networkInGB: 0,
        networkOutGB: 0,
        diskReadGB: 0,
        diskWrittenGB: 0,
        diskUsedGB: 0,
        diskTotalGB: 0,
        volumes: [],
        uptimeSeconds: 0,
        topProcesses: [],
        timestamp: nil
    )

    init(value: JSONValue, timestamp: Date) {
        let object = value.objectValue ?? [:]
        self.cpu = object["cpu"]?.doubleValue ?? 0
        self.cpuUser = object["cpuUser"]?.doubleValue ?? 0
        self.cpuSystem = object["cpuSystem"]?.doubleValue ?? 0
        self.memory = object["memory"]?.doubleValue ?? 0
        self.memoryMode = object["memoryMode"]?.stringValue ?? "used"
        self.disk = object["disk"]?.doubleValue ?? 0
        self.hasBattery = object["hasBattery"]?.boolValue ?? false
        self.battery = object["battery"]?.doubleValue ?? 0
        self.loadAverage = object["loadAverage"]?.stringValue ?? "-"
        self.loadHistory = object["loadHistory"]?.arrayValue?.compactMap(\.doubleValue) ?? [self.cpu]
        self.cores = object["cores"]?.integerValue ?? 0
        self.processes = object["processes"]?.integerValue ?? 0
        self.runningProcesses = object["runningProcesses"]?.integerValue ?? 0
        self.threads = object["threads"]?.integerValue ?? 0
        self.networkInGB = object["networkInGB"]?.doubleValue ?? 0
        self.networkOutGB = object["networkOutGB"]?.doubleValue ?? 0
        self.diskReadGB = object["diskReadGB"]?.doubleValue ?? 0
        self.diskWrittenGB = object["diskWrittenGB"]?.doubleValue ?? 0
        self.diskUsedGB = object["diskUsedGB"]?.doubleValue ?? 0
        self.diskTotalGB = object["diskTotalGB"]?.doubleValue ?? 0
        self.volumes = object["volumes"]?.arrayValue?.compactMap { item in
            guard let volume = item.objectValue else { return nil }
            return SystemMonitorVolume(
                name: volume["name"]?.stringValue ?? "-",
                usedPercent: volume["usedPercent"]?.doubleValue ?? 0,
                usedGB: volume["usedGB"]?.doubleValue ?? 0,
                totalGB: volume["totalGB"]?.doubleValue ?? 0
            )
        } ?? []
        self.uptimeSeconds = object["uptimeSeconds"]?.integerValue ?? 0
        self.topProcesses = object["topProcesses"]?.arrayValue?.compactMap { item in
            guard let process = item.objectValue else { return nil }
            return SystemMonitorProcess(
                pid: process["pid"]?.integerValue ?? 0,
                name: process["name"]?.stringValue ?? "-",
                cpu: process["cpu"]?.doubleValue ?? 0,
                memory: process["memory"]?.doubleValue ?? 0
            )
        } ?? []
        self.timestamp = timestamp
    }
}

final class SystemMonitorDashboardView: NSView {
    var snapshot: SystemMonitorSnapshot {
        didSet { needsDisplay = true }
    }
    var theme: PanelTheme {
        didSet { needsDisplay = true }
    }

    init(snapshot: SystemMonitorSnapshot, theme: PanelTheme) {
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
        drawPanelBackground()
        let gap = theme.spacing
        let leftWidth = bounds.width * 0.30
        let centerWidth = bounds.width * 0.38
        let rightWidth = bounds.width - leftWidth - centerWidth - gap * 2
        let left = NSRect(x: 0, y: 0, width: leftWidth, height: bounds.height)
        let center = NSRect(x: left.maxX + gap, y: 0, width: centerWidth, height: bounds.height)
        let right = NSRect(x: center.maxX + gap, y: 0, width: rightWidth, height: bounds.height)

        drawGaugeCluster(in: left)
        drawLoadAndStorage(in: center)
        drawProcessTable(in: right)
    }

    private func drawPanelBackground() {
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()
        theme.accent.withAlphaComponent(0.18).setStroke()
        let grid = NSBezierPath()
        let step: CGFloat = 36
        var x: CGFloat = 0
        while x <= bounds.width {
            grid.move(to: NSPoint(x: x, y: 0))
            grid.line(to: NSPoint(x: x, y: bounds.height))
            x += step
        }
        var y: CGFloat = 0
        while y <= bounds.height {
            grid.move(to: NSPoint(x: 0, y: y))
            grid.line(to: NSPoint(x: bounds.width, y: y))
            y += step
        }
        grid.lineWidth = 0.5
        grid.stroke()
    }

    private func drawGaugeCluster(in rect: NSRect) {
        let gap = theme.spacing
        let header = NSRect(x: rect.minX, y: rect.maxY - 56, width: rect.width, height: 56)
        drawTitle("SYSTEM", subtitle: uptimeText(snapshot.uptimeSeconds), in: header)

        let batteryCard = snapshot.hasBattery
            ? ("BATT", snapshot.battery, theme.warning, "state \(format(snapshot.battery))%")
            : ("PROC", min(100, Double(snapshot.runningProcesses)), theme.warning, "\(snapshot.processes) total · \(snapshot.runningProcesses) running")
        let cards = [
            ("CPU", snapshot.cpu, theme.accent, "usr \(format(snapshot.cpuUser))% sys \(format(snapshot.cpuSystem))%"),
            (snapshot.memoryMode == "free" ? "RAM FREE" : "RAM USED", snapshot.memory, theme.danger, "\(snapshot.threads) threads"),
            ("DISK", snapshot.disk, theme.success, "\(format(snapshot.diskUsedGB)) / \(format(snapshot.diskTotalGB)) GB"),
            batteryCard
        ]
        let cardHeight = (rect.height - header.height - gap * CGFloat(cards.count - 1)) / CGFloat(cards.count)
        for (index, card) in cards.enumerated() {
            let y = header.minY - gap - CGFloat(index + 1) * cardHeight - CGFloat(index) * gap
            drawMetricCard(title: card.0, value: card.1, color: card.2, detail: card.3, in: NSRect(x: rect.minX, y: y, width: rect.width, height: cardHeight))
        }
    }

    private func drawLoadAndStorage(in rect: NSRect) {
        let gap = theme.spacing
        let top = NSRect(x: rect.minX, y: rect.midY + gap / 2, width: rect.width, height: rect.height / 2 - gap / 2)
        let bottom = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height / 2 - gap / 2)
        drawChartCard(
            title: "LOAD HISTORY",
            subtitle: "avg \(snapshot.loadAverage) across \(snapshot.cores) cores",
            values: normalizedHistory(),
            color: theme.accent,
            in: top
        )
        drawIOCard(in: bottom)
    }

    private func drawProcessTable(in rect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        defer { NSGraphicsContext.restoreGraphicsState() }
        drawCard(in: rect)
        drawText("TOP PROCESSES", in: NSRect(x: rect.minX + 14, y: rect.maxY - 34, width: rect.width - 28, height: 24), size: 16, weight: .bold, color: theme.textPrimary)
        drawText("\(snapshot.processes) total · \(snapshot.runningProcesses) running", in: NSRect(x: rect.minX + 14, y: rect.maxY - 58, width: rect.width - 28, height: 18), size: 12, weight: .medium, color: theme.textSecondary)

        let rows = snapshot.topProcesses.prefix(6)
        let startY = rect.maxY - 88
        let rowHeight: CGFloat = 35
        for (index, process) in rows.enumerated() {
            let y = startY - CGFloat(index) * rowHeight
            let row = NSRect(x: rect.minX + 12, y: y - rowHeight + 6, width: rect.width - 24, height: rowHeight - 6)
            let fill = index % 2 == 0 ? theme.surface.withAlphaComponent(0.48) : theme.surfaceRaised.withAlphaComponent(0.36)
            fill.setFill()
            NSBezierPath(roundedRect: row, xRadius: 5, yRadius: 5).fill()
            drawText(shortProcessName(process.name), in: NSRect(x: row.minX + 8, y: row.minY + 8, width: row.width * 0.46, height: 18), size: 12, weight: .semibold, color: theme.textPrimary)
            drawText("pid \(process.pid)", in: NSRect(x: row.minX + 8, y: row.minY - 7, width: row.width * 0.46, height: 14), size: 9, weight: .regular, color: theme.textSecondary)
            drawBar(value: process.cpu, maximum: 100, color: theme.danger, label: "\(format(process.cpu))%", in: NSRect(x: row.midX, y: row.minY + 8, width: row.width * 0.23, height: 14))
            drawBar(value: process.memory, maximum: 10, color: theme.accent, label: "\(format(process.memory))%", in: NSRect(x: row.minX + row.width * 0.76, y: row.minY + 8, width: row.width * 0.20, height: 14))
        }
    }

    private func drawIOCard(in rect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        defer { NSGraphicsContext.restoreGraphicsState() }
        drawCard(in: rect)
        drawText("I/O MATRIX", in: NSRect(x: rect.minX + 14, y: rect.maxY - 34, width: rect.width - 28, height: 22), size: 16, weight: .bold, color: theme.textPrimary)
        let rows: [(String, Double, Double, NSColor)] = [
            ("NET IN", snapshot.networkInGB, max(snapshot.networkInGB, snapshot.networkOutGB, 1), theme.accent),
            ("NET OUT", snapshot.networkOutGB, max(snapshot.networkInGB, snapshot.networkOutGB, 1), theme.danger),
            ("DISK R", snapshot.diskReadGB, max(snapshot.diskReadGB, snapshot.diskWrittenGB, 1), theme.success),
            ("DISK W", snapshot.diskWrittenGB, max(snapshot.diskReadGB, snapshot.diskWrittenGB, 1), theme.warning)
        ]
        for (index, row) in rows.enumerated() {
            let y = rect.maxY - 66 - CGFloat(index) * 26
            drawText(row.0, in: NSRect(x: rect.minX + 16, y: y, width: 70, height: 18), size: 12, weight: .bold, color: theme.textSecondary)
            drawBar(value: row.1, maximum: row.2, color: row.3, label: "\(format(row.1)) GB", in: NSRect(x: rect.minX + 92, y: y + 1, width: rect.width - 112, height: 16))
        }

        let volumeStartY = rect.minY + 18
        let volumeRows = snapshot.volumes.prefix(3)
        for (index, volume) in volumeRows.enumerated() {
            let y = volumeStartY + CGFloat(volumeRows.count - index - 1) * 23
            drawText(volume.name, in: NSRect(x: rect.minX + 16, y: y, width: 86, height: 16), size: 10, weight: .bold, color: theme.textSecondary)
            drawBar(value: volume.usedPercent, maximum: 100, color: theme.success, label: "\(format(volume.usedGB))/\(format(volume.totalGB)) GB", in: NSRect(x: rect.minX + 108, y: y + 1, width: rect.width - 128, height: 14))
        }
    }

    private func drawMetricCard(title: String, value: Double, color: NSColor, detail: String, in rect: NSRect) {
        drawCard(in: rect)
        drawText(title, in: NSRect(x: rect.minX + 14, y: rect.maxY - 30, width: 80, height: 20), size: 16, weight: .bold, color: theme.textSecondary)
        drawText("\(format(value))%", in: NSRect(x: rect.minX + 100, y: rect.maxY - 38, width: rect.width - 114, height: 32), size: 28, weight: .black, color: color)
        drawBar(value: value, maximum: 100, color: color, label: detail, in: NSRect(x: rect.minX + 14, y: rect.minY + 18, width: rect.width - 28, height: 18))
    }

    private func drawChartCard(title: String, subtitle: String, values: [Double], color: NSColor, in rect: NSRect) {
        drawCard(in: rect)
        drawText(title, in: NSRect(x: rect.minX + 14, y: rect.maxY - 34, width: rect.width - 28, height: 22), size: 16, weight: .bold, color: theme.textPrimary)
        drawText(subtitle, in: NSRect(x: rect.minX + 14, y: rect.maxY - 56, width: rect.width - 28, height: 16), size: 11, weight: .medium, color: theme.textSecondary)
        let chart = NSRect(x: rect.minX + 18, y: rect.minY + 20, width: rect.width - 36, height: rect.height - 88)
        color.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: chart, xRadius: 5, yRadius: 5).fill()
        drawSparkline(values: values, color: color, in: chart.insetBy(dx: 12, dy: 10))
    }

    private func drawCard(in rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: theme.cornerRadius, yRadius: theme.cornerRadius)
        theme.surface.withAlphaComponent(0.76).setFill()
        path.fill()
        theme.border.withAlphaComponent(0.86).setStroke()
        path.lineWidth = theme.borderWidth
        path.stroke()
    }

    private func drawBar(value: Double, maximum: Double, color: NSColor, label: String, in rect: NSRect) {
        let track = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        theme.background.withAlphaComponent(0.8).setFill()
        track.fill()
        let width = rect.width * CGFloat(max(0, min(1, maximum == 0 ? 0 : value / maximum)))
        if width > 0 {
            color.withAlphaComponent(0.88).setFill()
            NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY, width: width, height: rect.height), xRadius: 4, yRadius: 4).fill()
        }
        drawText(label, in: rect.insetBy(dx: 6, dy: 1), size: 10, weight: .bold, color: theme.textPrimary)
    }

    private func drawSparkline(values: [Double], color: NSColor, in rect: NSRect) {
        guard values.count > 1 else { return }
        let maxValue = max(values.max() ?? 1, 1)
        let path = NSBezierPath()
        for (index, value) in values.enumerated() {
            let x = rect.minX + CGFloat(index) * rect.width / CGFloat(values.count - 1)
            let y = rect.minY + rect.height * CGFloat(max(0, min(1, value / maxValue)))
            if index == 0 {
                path.move(to: NSPoint(x: x, y: y))
            } else {
                path.line(to: NSPoint(x: x, y: y))
            }
        }
        color.setStroke()
        path.lineWidth = 3
        path.stroke()
    }

    private func drawTitle(_ title: String, subtitle: String, in rect: NSRect) {
        drawText(title, in: NSRect(x: rect.minX, y: rect.minY + 20, width: rect.width, height: 34), size: 30, weight: .black, color: theme.accent)
        drawText(subtitle, in: NSRect(x: rect.minX + 2, y: rect.minY + 2, width: rect.width, height: 18), size: 12, weight: .medium, color: theme.textSecondary)
    }

    private func drawText(_ text: String, in rect: NSRect, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        NSAttributedString(string: text, attributes: attributes).draw(in: rect)
    }

    private func normalizedHistory() -> [Double] {
        let values = snapshot.loadHistory.map { max(0, min(100, $0)) }
        return values.count > 1 ? values : [0, snapshot.cpu]
    }

    private func format(_ value: Double) -> String {
        value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    private func shortProcessName(_ value: String) -> String {
        if let range = value.range(of: ".app/") {
            let prefix = String(value[..<range.upperBound])
            return URL(fileURLWithPath: prefix).deletingPathExtension().lastPathComponent
        }
        let executable = value.split(separator: " ").first.map(String.init) ?? value
        return URL(fileURLWithPath: executable).lastPathComponent
    }

    private func uptimeText(_ seconds: Int) -> String {
        guard seconds > 0 else { return "uptime -" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        return days > 0 ? "uptime \(days)d \(hours)h" : "uptime \(hours)h"
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

final class ArrowPadView: NSView {
    enum Direction {
        case previous
        case next
    }

    let direction: Direction
    var theme: PanelTheme = .fallback {
        didSet { needsDisplay = true }
    }

    init(direction: Direction) {
        self.direction = direction
        super.init(frame: .zero)
        wantsLayer = true
        autoresizingMask = [.height, .minYMargin, .maxYMargin]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds.insetBy(dx: 4, dy: 4)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        theme.surface.withAlphaComponent(0.85).setFill()
        path.fill()
        theme.border.setStroke()
        path.lineWidth = max(1, theme.borderWidth)
        path.stroke()

        let midX = rect.midX
        let midY = rect.midY
        let arrow = NSBezierPath()
        let width: CGFloat = 8
        let height: CGFloat = 22
        switch direction {
        case .previous:
            arrow.move(to: NSPoint(x: midX + width / 2, y: midY - height / 2))
            arrow.line(to: NSPoint(x: midX - width / 2, y: midY))
            arrow.line(to: NSPoint(x: midX + width / 2, y: midY + height / 2))
        case .next:
            arrow.move(to: NSPoint(x: midX - width / 2, y: midY - height / 2))
            arrow.line(to: NSPoint(x: midX + width / 2, y: midY))
            arrow.line(to: NSPoint(x: midX - width / 2, y: midY + height / 2))
        }
        theme.accent.setStroke()
        arrow.lineWidth = 3
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        arrow.stroke()
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
    private let valueLabel = NSTextField(labelWithString: "")
    private let stateLabel = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private let preview: WidgetPreviewData?
    private let orbitMode: Bool

    init(tile: ShellTile, preview: WidgetPreviewData?, orbitMode: Bool = false, theme: PanelTheme) {
        self.theme = theme
        self.preview = preview
        self.orbitMode = orbitMode
        super.init(frame: .zero)
        wantsLayer = true

        titleLabel.stringValue = tile.title
        titleLabel.font = NSFont.systemFont(ofSize: 19, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.backgroundColor = .clear

        subtitleLabel.stringValue = orbitMode && preview != nil
            ? "\(preview?.value ?? "")  ·  \(preview?.detail ?? "")"
            : preview?.detail ?? tile.subtitle
        subtitleLabel.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.backgroundColor = .clear

        valueLabel.stringValue = preview?.value ?? ""
        valueLabel.font = NSFont.systemFont(ofSize: preview == nil ? 0 : 27, weight: .black)
        valueLabel.lineBreakMode = .byTruncatingTail
        valueLabel.backgroundColor = .clear
        valueLabel.isHidden = preview == nil || orbitMode

        stateLabel.stringValue = preview?.state?.uppercased() ?? ""
        stateLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        stateLabel.alignment = .right
        stateLabel.lineBreakMode = .byTruncatingTail
        stateLabel.backgroundColor = .clear
        stateLabel.isHidden = preview?.state == nil

        if let name = tile.icon, let image = NSImage(systemSymbolName: name, accessibilityDescription: tile.title) {
            iconView.image = image
            iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
            iconView.imageScaling = .scaleProportionallyUpOrDown
        }
        iconView.wantsLayer = true

        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(valueLabel)
        addSubview(stateLabel)
        applyStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        if orbitMode {
            let disc = min(bounds.height, 52)
            iconView.frame = NSRect(x: 0, y: bounds.midY - disc / 2, width: disc, height: disc)
            iconView.layer?.cornerRadius = disc / 2
            titleLabel.frame = NSRect(x: disc + 14, y: bounds.midY + 2, width: bounds.width - disc - 18, height: 20)
            subtitleLabel.frame = NSRect(x: disc + 14, y: bounds.midY - 20, width: bounds.width - disc - 18, height: 18)
            stateLabel.frame = .zero
            return
        }
        iconView.frame = NSRect(x: 14, y: bounds.height - 38, width: 20, height: 20)
        titleLabel.frame = NSRect(x: 42, y: bounds.height - 43, width: bounds.width - 56, height: 24)
        stateLabel.frame = NSRect(x: 14, y: bounds.height - 64, width: bounds.width - 28, height: 14)
        if preview != nil {
            valueLabel.frame = NSRect(x: 14, y: bounds.midY - 16, width: bounds.width - 28, height: 34)
            subtitleLabel.frame = NSRect(x: 14, y: 16, width: bounds.width - 28, height: 22)
        } else {
            subtitleLabel.frame = NSRect(x: 14, y: 18, width: bounds.width - 28, height: 24)
        }
    }

    private func applyStyle() {
        if orbitMode {
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderWidth = 0
            iconView.layer?.cornerRadius = iconView.bounds.width / 2
            iconView.layer?.backgroundColor = (isSelected ? theme.accent.withAlphaComponent(0.18) : theme.surfaceRaised).cgColor
            iconView.layer?.borderWidth = max(1, theme.borderWidth)
            iconView.layer?.borderColor = (isSelected ? theme.accent : theme.border).cgColor
            titleLabel.textColor = isSelected ? theme.accent : theme.textPrimary
            subtitleLabel.textColor = theme.textSecondary
            valueLabel.textColor = theme.accent
            stateLabel.isHidden = true
            iconView.contentTintColor = isSelected ? theme.accent : theme.textSecondary
            return
        }
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
        valueLabel.textColor = theme.accent
        stateLabel.textColor = theme.success
        iconView.contentTintColor = isSelected ? theme.accent : theme.textSecondary
    }
}
