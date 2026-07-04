import AppKit
import Foundation
import QuakePluginAPI

final class QuakeSettingsWindowView: NSView {
    private enum Section: Int, CaseIterable {
        case global
        case themes
        case widgets
        case carousel
        case plugins
        case about

        var title: String {
            switch self {
            case .global: return "Global"
            case .themes: return "Themes"
            case .widgets: return "Widgets & Apps"
            case .carousel: return "Carousel"
            case .plugins: return "Plugins"
            case .about: return "About"
            }
        }
    }

    private let pluginPackages: [PluginPackage]
    private let themePackages: [ThemePackage]
    private let settings: QuakeSettingsConfiguration
    private let themeConfiguration: ThemeUserConfiguration
    private let titleLabel = NSTextField(labelWithString: "QuakeKit Settings")
    private let sectionControl = NSSegmentedControl(labels: Section.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
    private let scrollView = NSScrollView()
    private let documentView = NSView()
    private let installPluginButton = NSButton(title: "Install Plugin...", target: nil, action: nil)
    private let installThemeButton = NSButton(title: "Install Theme...", target: nil, action: nil)
    private var rowViews: [NSView] = []
    private var activeSection: Section = .global

    init(
        frame frameRect: NSRect,
        pluginPackages: [PluginPackage],
        themePackages: [ThemePackage],
        settings: QuakeSettingsConfiguration,
        themeConfiguration: ThemeUserConfiguration
    ) {
        self.pluginPackages = pluginPackages
        self.themePackages = themePackages
        self.settings = settings
        self.themeConfiguration = themeConfiguration
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        titleLabel.font = NSFont.systemFont(ofSize: 28, weight: .bold)
        titleLabel.backgroundColor = .clear
        addSubview(titleLabel)

        sectionControl.selectedSegment = 0
        sectionControl.target = self
        sectionControl.action = #selector(sectionChanged)
        addSubview(sectionControl)

        installPluginButton.target = self
        installPluginButton.action = #selector(installPlugin)
        addSubview(installPluginButton)

        installThemeButton.target = self
        installThemeButton.action = #selector(installTheme)
        addSubview(installThemeButton)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.documentView = documentView
        addSubview(scrollView)
        rebuildRows()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 28
        titleLabel.frame = NSRect(x: inset, y: bounds.height - 64, width: 320, height: 36)
        sectionControl.frame = NSRect(x: inset, y: bounds.height - 104, width: min(720, bounds.width - inset * 2), height: 28)
        installThemeButton.frame = NSRect(x: bounds.width - inset - 138, y: bounds.height - 62, width: 138, height: 30)
        installPluginButton.frame = NSRect(x: installThemeButton.frame.minX - 150, y: bounds.height - 62, width: 138, height: 30)
        scrollView.frame = NSRect(x: inset, y: inset, width: bounds.width - inset * 2, height: bounds.height - 148)
        layoutRows()
    }

    @objc private func sectionChanged() {
        activeSection = Section(rawValue: sectionControl.selectedSegment) ?? .global
        rebuildRows()
    }

    @objc private func installPlugin() {
        installPackage(title: "Install QuakeKit Plugin")
    }

    @objc private func installTheme() {
        installPackage(title: "Install QuakeKit Theme")
    }

    private func installPackage(title: String) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let installed = try QuakePackageInstaller.installPackage(from: url)
            showAlert(title: "Installed \(installed.kind.rawValue)", message: "\(installed.name) was installed. Restart QuakeKit to reload package discovery.")
        } catch {
            showAlert(title: "Install Failed", message: String(describing: error))
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = title.contains("Failed") ? .warning : .informational
        alert.runModal()
    }

    private func rebuildRows() {
        rowViews.forEach { $0.removeFromSuperview() }
        rowViews.removeAll()
        for row in rowsForActiveSection() {
            let view = SettingsRowView(title: row.title, value: row.value, detail: row.detail)
            documentView.addSubview(view)
            rowViews.append(view)
        }
        needsLayout = true
    }

    private func layoutRows() {
        let width = max(400, scrollView.bounds.width - 18)
        let rowHeight: CGFloat = 72
        let gap: CGFloat = 10
        let totalHeight = CGFloat(rowViews.count) * rowHeight + CGFloat(max(0, rowViews.count - 1)) * gap + 8
        documentView.frame = NSRect(x: 0, y: 0, width: width, height: max(scrollView.bounds.height, totalHeight))
        for (index, row) in rowViews.enumerated() {
            let y = documentView.bounds.height - CGFloat(index + 1) * rowHeight - CGFloat(index) * gap
            row.frame = NSRect(x: 0, y: y, width: width, height: rowHeight)
        }
    }

    private func rowsForActiveSection() -> [(title: String, value: String, detail: String)] {
        switch activeSection {
        case .global:
            return [
                ("Launch Mode", "Menu Bar Accessory", "Release builds run without a Dock tile or application menu by default."),
                ("Default Panel Page", "Page \(settings.defaultPageIndex + 1)", "Controlled from the on-device Settings page today; this window is the release target for richer editing."),
                ("Display Ownership", "Screen-saver level panel", "Panel window hides the menu bar and guards pointer entry on the DK-QUAKE display."),
                ("Package Install Path", "~/Library/Application Support/QuakeKit", "Themes and plugins installed from this window are copied into the user support folder.")
            ]
        case .themes:
            return themePackages.map { package in
                let active = package.manifest.id == themeConfiguration.activeThemeID || (themeConfiguration.activeThemeID == nil && package.manifest.id == themePackages.first?.manifest.id)
                return (
                    package.manifest.name + (active ? " *" : ""),
                    package.manifest.id,
                    "\(package.manifest.palette.colors.count) colors · \(package.manifest.options.count) options · \(package.baseURL.lastPathComponent)"
                )
            }
        case .widgets:
            return pluginPackages.flatMap { package in
                package.manifest.views.map { view in
                    (
                        view.title,
                        package.manifest.name,
                        "\(view.presentation?.rawValue ?? "page") · \(view.layout?.rawValue ?? "host layout") · \(view.type?.rawValue ?? package.manifest.entry.transport.rawValue)"
                    )
                }
            }
        case .carousel:
            let refs = pluginPackages.flatMap { package in
                package.manifest.views.compactMap { view -> String? in
                    let presentation = view.presentation ?? .page
                    guard presentation == .widget || presentation == .pageAndWidget else { return nil }
                    let id = "\(package.manifest.id):\(view.id)"
                    let included = settings.carousel.widgetIDs.isEmpty || settings.carousel.widgetIDs.contains(id)
                    return "\(included ? "*" : "-") \(view.title) (\(package.manifest.name))"
                }
            }
            return [
                ("Enabled", settings.carousel.enabled ? "On" : "Off", "Current rotation interval is \(settings.carousel.intervalSeconds) seconds."),
                ("Selected Widgets", "\(refs.filter { $0.hasPrefix("*") }.count)", refs.joined(separator: "   "))
            ]
        case .plugins:
            return pluginPackages.map { package in
                (
                    package.manifest.name,
                    package.manifest.id,
                    "\(package.manifest.capabilities.map(\.rawValue).joined(separator: ", ")) · \(package.manifest.settings.count) settings · \(package.manifest.actions.count) actions"
                )
            }
        case .about:
            return [
                ("QuakeKit", "Native DK-QUAKE control center", "Swift/AppKit host, HID wake/keep-alive, theme packages, functional plugin packages, and native panel rendering."),
                ("Hardware", "DK-QUAKE touch display", "Display ownership, touch, knob, microphone toggle, and knob LED ring arbitration are managed by the native app."),
                ("Next Settings Work", "Editable controls", "Persist live changes from this window, reload packages without restart, and add permission review flows.")
            ]
        }
    }
}

private final class SettingsRowView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

    init(title: String, value: String, detail: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.78).cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1

        titleLabel.stringValue = title
        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.backgroundColor = .clear
        addSubview(titleLabel)

        valueLabel.stringValue = value
        valueLabel.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.backgroundColor = .clear
        valueLabel.alignment = .right
        addSubview(valueLabel)

        detailLabel.stringValue = detail
        detailLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.backgroundColor = .clear
        detailLabel.lineBreakMode = .byTruncatingTail
        addSubview(detailLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        titleLabel.frame = NSRect(x: 16, y: bounds.height - 30, width: bounds.width * 0.48, height: 20)
        valueLabel.frame = NSRect(x: bounds.width * 0.52, y: bounds.height - 30, width: bounds.width * 0.48 - 16, height: 20)
        detailLabel.frame = NSRect(x: 16, y: 14, width: bounds.width - 32, height: 20)
    }
}
