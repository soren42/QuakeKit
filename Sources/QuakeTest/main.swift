import Foundation
import QuakeHID
import QuakePluginAPI
import QuakeRuntime

var failures: [String] = []

@MainActor
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        failures.append(message)
    }
}

@MainActor
func run(_ name: String, _ body: () -> Void) {
    let before = failures.count
    body()
    let passed = failures.count == before
    print("\(passed ? "ok" : "FAIL") \(name)")
}

run("protocol vectors") {
    expect(QuakeProtocol.screenOn == [0xA3, 0x03, 0x01, 0x04, 0x01, 0x06], "screenOn vector changed")
    expect(QuakeProtocol.setBrightness(255) == [0xA3, 0x03, 0x01, 0x05, 0xFF, 0x06], "brightness vector changed")
    expect(QuakeProtocol.ping == [0xA3, 0x02, 0x02, 0xEF, 0xF1], "ping vector changed")
    expect(QuakeProtocol.decodeControlReport([0xA3, 0x03, 0x03, 0x01, 0x01]) == [.knob(.rotate(direction: 1))], "knob clockwise decode failed")
    expect(QuakeProtocol.decodeControlReport([0xA3, 0x03, 0x03, 0x01, 0x02]) == [.knob(.rotate(direction: -1))], "knob counterclockwise decode failed")
    expect(QuakeProtocol.decodeControlReport([0xA3, 0x03, 0x03, 0x02, 0x02]) == [.knob(.press(index: 2))], "knob press decode failed")
    expect(QuakeProtocol.decodeControlReport([0xA3, 0x03, 0x03, 0x02, 0x05]) == [.knob(.holdStart)], "knob hold start decode failed")
    expect(QuakeProtocol.decodeControlReport([0xA3, 0x03, 0x03, 0x02, 0xFF]) == [.knob(.holdEnd)], "knob hold end decode failed")
    expect(
        QuakeProtocol.decodeTouchReport([0xA3, 0x1C, 0x03, 0x1A, 0x01, 0x01, 0xE0, 0x01, 0x80, 0x07]) ==
        [.touch([TouchPoint(phase: .down, x: 1920, y: 480)])],
        "touch decode failed"
    )
}

run("knob ring arbitration") {
    var ring = KnobRingCoordinator()
    let now = Date(timeIntervalSince1970: 1_000)
    let themedRing = ThemeKnobRing(
        idle: ThemeKnobRingState(color: "#111111", intensity: 0.2, animation: .solid),
        focus: ThemeKnobRingState(color: "#222222", intensity: 0.6, animation: .pulse),
        danger: ThemeKnobRingState(color: "#FF0000", intensity: 1, animation: .flash)
    )
    expect(ring.resolve(theme: themedRing, now: now)?.state == .idle, "idle fallback failed")
    ring.submit(KnobRingRequest(source: "focus", state: .focus, priority: .focus, ttl: 1, createdAt: now))
    ring.submit(KnobRingRequest(source: "critical", state: .danger, priority: .systemCritical, ttl: 5, createdAt: now))
    expect(ring.resolve(theme: themedRing, now: now.addingTimeInterval(0.5))?.state == .danger, "priority resolution failed")
    expect(ring.resolve(theme: themedRing, now: now.addingTimeInterval(6))?.state == .idle, "TTL expiry failed")
}

let packagesURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Examples/Plugins", isDirectory: true)
let loadResults = PluginPackageLoader.loadPackages(from: packagesURL)
let packages = loadResults.compactMap { result -> PluginPackage? in
    if case .success(let package, _) = result { return package }
    return nil
}

run("bundled plugin package validation") {
    expect(packages.count >= 6, "expected at least six bundled plugin packages")
    expect(loadResults.allSatisfy { result in
        if case .success = result { return true }
        return false
    }, "one or more bundled plugin packages failed validation")
}

run("plugin action execution") {
    let host = PluginExecutionHost(packages: packages)
    expect(host.invokeAction(pluginID: "echo", actionID: "echo.say").response.ok, "echo action failed")
    expect(host.invokeAction(pluginID: "system_monitor", actionID: "system.refresh").response.ok, "system refresh action failed")
    expect(host.invokeAction(pluginID: "ai_agent", actionID: "agent.listen").response.ok, "agent listen action failed")
}

run("validator rejects dangling stream references") {
    let manifest = PluginManifest(
        id: "bad_plugin",
        name: "Bad Plugin",
        version: "0.1.0",
        entry: PluginEntry(transport: .nativeSwift),
        views: [
            PluginView(id: "bad.view", title: "Bad View", dataStreamID: "missing.stream")
        ]
    )
    expect(!PluginManifestValidator.validate(manifest).isValid, "dangling view stream was accepted")
}

if failures.isEmpty {
    print("QuakeKit tests passed.")
} else {
    for failure in failures {
        fputs("error: \(failure)\n", stderr)
    }
    exit(1)
}
