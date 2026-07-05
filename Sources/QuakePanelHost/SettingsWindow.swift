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
    private var settings: QuakeSettingsConfiguration
    private var themeConfiguration: ThemeUserConfiguration
    private let onConfigurationChanged: () -> Void
    private let titleLabel = NSTextField(labelWithString: "QuakeKit Settings")
    private let sectionControl = NSSegmentedControl(labels: Section.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
    private let scrollView = NSScrollView()
    private let documentView = NSView()
    private let installPluginButton = NSButton(title: "Install Plugin...", target: nil, action: nil)
    private let installThemeButton = NSButton(title: "Install Theme...", target: nil, action: nil)
    private let openPackagesButton = NSButton(title: "Open Packages", target: nil, action: nil)
    private var rowViews: [SettingsRowView] = []
    private var activeSection: Section = .global

    init(
        frame frameRect: NSRect,
        pluginPackages: [PluginPackage],
        themePackages: [ThemePackage],
        settings: QuakeSettingsConfiguration,
        themeConfiguration: ThemeUserConfiguration,
        onConfigurationChanged: @escaping () -> Void
    ) {
        self.pluginPackages = pluginPackages
        self.themePackages = themePackages
        self.settings = settings
        self.themeConfiguration = themeConfiguration
        self.onConfigurationChanged = onConfigurationChanged
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

        openPackagesButton.target = self
        openPackagesButton.action = #selector(openPackageFolder)
        addSubview(openPackagesButton)

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
        let compactHeader = bounds.width < 780
        let buttonY = compactHeader ? bounds.height - 104 : bounds.height - 62
        openPackagesButton.frame = NSRect(x: bounds.width - inset - 128, y: buttonY, width: 128, height: 30)
        installThemeButton.frame = NSRect(x: openPackagesButton.frame.minX - 146, y: buttonY, width: 134, height: 30)
        installPluginButton.frame = NSRect(x: installThemeButton.frame.minX - 146, y: buttonY, width: 134, height: 30)
        let sectionY = compactHeader ? bounds.height - 142 : bounds.height - 104
        sectionControl.frame = NSRect(x: inset, y: sectionY, width: min(720, bounds.width - inset * 2), height: 28)
        scrollView.frame = NSRect(x: inset, y: inset, width: bounds.width - inset * 2, height: bounds.height - (compactHeader ? 186 : 148))
        layoutRows()
    }

    func reload(settings: QuakeSettingsConfiguration, themeConfiguration: ThemeUserConfiguration) {
        self.settings = settings
        self.themeConfiguration = themeConfiguration
        rebuildRows()
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

    @objc private func openPackageFolder() {
        guard let directory = try? QuakePackageLocations.applicationSupportDirectory() else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    private func installPackage(title: String) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = "Choose a .quakekitplugin, .quakekittheme, .tar, .tar.gz, or .tgz package."
        panel.prompt = "Install"
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
        for row in rowSpecs() {
            let view = SettingsRowView(title: row.title, value: row.value, detail: row.detail, control: row.control)
            documentView.addSubview(view)
            rowViews.append(view)
        }
        needsLayout = true
    }

    private func layoutRows() {
        let width = max(520, scrollView.bounds.width - 18)
        let rowHeight: CGFloat = 78
        let gap: CGFloat = 10
        let totalHeight = CGFloat(rowViews.count) * rowHeight + CGFloat(max(0, rowViews.count - 1)) * gap + 8
        documentView.frame = NSRect(x: 0, y: 0, width: width, height: max(scrollView.bounds.height, totalHeight))
        for (index, row) in rowViews.enumerated() {
            let y = documentView.bounds.height - CGFloat(index + 1) * rowHeight - CGFloat(index) * gap
            row.frame = NSRect(x: 0, y: y, width: width, height: rowHeight)
        }
    }

    private func saveSettings(rebuild: Bool = true) {
        QuakeSettingsStore.save(settings)
        onConfigurationChanged()
        if rebuild { rebuildRows() }
    }

    private func saveThemeConfiguration(rebuild: Bool = true) {
        ThemeConfigurationStore.save(themeConfiguration)
        onConfigurationChanged()
        if rebuild { rebuildRows() }
    }

    private struct RowSpec {
        var title: String
        var value: String
        var detail: String
        var control: NSView?
    }

    private func rowSpecs() -> [RowSpec] {
        switch activeSection {
        case .global:
            return globalRows()
        case .themes:
            return themeRows()
        case .widgets:
            return widgetRows()
        case .carousel:
            return carouselRows()
        case .plugins:
            return pluginRows()
        case .about:
            return aboutRows()
        }
    }

    private func globalRows() -> [RowSpec] {
        [
            RowSpec(
                title: "Default Panel Page",
                value: pageTitle(settings.defaultPageIndex),
                detail: "Panel opens to this page after launch.",
                control: popup(
                    values: Array(0..<7).map { "\($0)" },
                    titles: Array(0..<7).map { pageTitle($0) },
                    selectedValue: "\(settings.defaultPageIndex)"
                ) { [weak self] value in
                    guard let self, let page = Int(value) else { return }
                    self.settings.defaultPageIndex = page
                    self.saveSettings()
                }
            ),
            RowSpec(title: "Launch Mode", value: "Menu Bar Accessory", detail: "Release-style launch hides Dock and app menu unless --foreground is used.", control: nil),
            RowSpec(title: "Display Ownership", value: "Enabled", detail: "Panel window runs above the menu bar and pointer guard keeps the cursor off the device.", control: nil),
            RowSpec(title: "Package Directory", value: "~/Library/Application Support/QuakeKit", detail: "Installed plugin and theme packages are copied here.", control: button("Open") { [weak self] in self?.openPackageFolder() }),
            RowSpec(title: "Settings File", value: "settings.json", detail: "Global, carousel, and plugin setting overrides are persisted in Application Support.", control: nil),
            RowSpec(title: "Release Check", value: "./scripts/validate-release.sh", detail: "Builds Swift targets, validates packages, checks adapters, and assembles the app bundle.", control: nil)
        ]
    }

    private func themeRows() -> [RowSpec] {
        var rows: [RowSpec] = [
            RowSpec(
                title: "Active Theme",
                value: activeThemeName(),
                detail: "Changes apply immediately to the panel shell.",
                control: popup(
                    values: themePackages.map(\.manifest.id),
                    titles: themePackages.map(\.manifest.name),
                    selectedValue: themeConfiguration.activeThemeID ?? themePackages.first?.manifest.id ?? ""
                ) { [weak self] id in
                    self?.themeConfiguration.activeThemeID = id
                    self?.themeConfiguration.overrides.removeAll()
                    self?.saveThemeConfiguration()
                }
            )
        ]

        if let active = activeThemeManifest() {
            rows.append(contentsOf: active.options.map { option in
                RowSpec(
                    title: option.title,
                    value: displayJSON(themeConfiguration.overrides[option.target] ?? option.defaultValue),
                    detail: option.target,
                    control: control(for: option)
                )
            })
            rows.append(RowSpec(
                title: "Reset Theme Overrides",
                value: "\(themeConfiguration.overrides.count) overrides",
                detail: "Restore the selected theme's packaged defaults.",
                control: button("Reset") { [weak self] in
                    self?.themeConfiguration.overrides.removeAll()
                    self?.saveThemeConfiguration()
                }
            ))
        }
        rows.append(contentsOf: themePackages.map { package in
            RowSpec(
                title: package.manifest.name,
                value: installedPackageLabel(package.baseURL, suffix: "quakekittheme"),
                detail: package.baseURL.path,
                control: isInstalledPackage(package.baseURL, suffix: "quakekittheme") ? button("Remove") { [weak self] in
                    self?.removeInstalledPackage(kind: .theme, id: package.manifest.id, name: package.manifest.name)
                } : nil
            )
        })
        return rows
    }

    private func widgetRows() -> [RowSpec] {
        let viewCount = pluginPackages.reduce(0) { $0 + $1.manifest.views.count }
        let summary = RowSpec(
            title: "View Inventory",
            value: "\(viewCount) views",
            detail: "Widgets and apps are generated from plugin manifests; layout hints are shown per view.",
            control: nil
        )
        return [summary] + pluginPackages.sorted { $0.manifest.name < $1.manifest.name }.flatMap { package in
            package.manifest.views.map { view in
                RowSpec(
                    title: view.title,
                    value: package.manifest.name,
                    detail: "\(view.presentation?.rawValue ?? "page") · \(view.layout?.rawValue ?? "host layout") · \(view.type?.rawValue ?? package.manifest.entry.transport.rawValue)",
                    control: button("Open App Settings") { [weak self] in
                        self?.activeSection = .plugins
                        self?.sectionControl.selectedSegment = Section.plugins.rawValue
                        self?.rebuildRows()
                    }
                )
            }
        }
    }

    private func carouselRows() -> [RowSpec] {
        var rows = [
            RowSpec(
                title: "Enabled",
                value: settings.carousel.enabled ? "On" : "Off",
                detail: "Automatically rotates selected page/widget views on the panel.",
                control: checkbox(isOn: settings.carousel.enabled) { [weak self] enabled in
                    self?.settings.carousel.enabled = enabled
                    self?.saveSettings()
                }
            ),
            RowSpec(
                title: "Duration",
                value: "\(settings.carousel.intervalSeconds)s",
                detail: "How long each carousel view stays on-screen.",
                control: popup(
                    values: ["5", "10", "15", "30", "60"],
                    titles: ["5 seconds", "10 seconds", "15 seconds", "30 seconds", "60 seconds"],
                    selectedValue: "\(settings.carousel.intervalSeconds)"
                ) { [weak self] value in
                    self?.settings.carousel.intervalSeconds = Int(value) ?? 15
                    self?.saveSettings()
                }
            )
        ]

        rows.append(RowSpec(
            title: "Widget Set",
            value: "\(carouselIncludedWidgetIDs().count) of \(carouselRefs().count)",
            detail: settings.carousel.widgetIDs.isEmpty ? "All eligible widgets are included by default." : "Using explicit include list.",
            control: buttonRow([
                ("All", { [weak self] in self?.includeAllCarouselWidgets() }),
                ("None", { [weak self] in self?.clearCarouselWidgets() })
            ])
        ))

        rows.append(contentsOf: carouselRefs().map { ref in
            RowSpec(
                title: ref.title,
                value: ref.pluginName,
                detail: ref.id,
                control: checkbox(isOn: carouselIncluded(id: ref.id)) { [weak self] enabled in
                    self?.setCarousel(id: ref.id, included: enabled)
                }
            )
        })
        return rows
    }

    private func pluginRows() -> [RowSpec] {
        pluginPackages.sorted { $0.manifest.name < $1.manifest.name }.flatMap { package -> [RowSpec] in
            let executable = executableStatus(for: package.manifest.entry.transport)
            let permissionSummary = package.manifest.permissions.isEmpty ? "no explicit permissions" : "\(package.manifest.permissions.count) permission declarations"
            var rows: [RowSpec] = [
                RowSpec(
                    title: package.manifest.name,
                    value: "\(package.manifest.entry.transport.rawValue) · \(executable)",
                    detail: "\(package.manifest.id) · \(package.manifest.capabilities.map(\.rawValue).joined(separator: ", ")) · \(permissionSummary) · \(package.manifest.settings.count) settings",
                    control: package.manifest.settings.isEmpty ? nil : button("Reset Settings") { [weak self] in
                        self?.settings.pluginSettings[package.manifest.id] = nil
                        self?.saveSettings()
                    }
                )
            ]
            if isInstalledPackage(package.baseURL, suffix: "quakekitplugin") {
                rows.append(RowSpec(
                    title: "\(package.manifest.name): Installed Package",
                    value: "Installed",
                    detail: package.baseURL.path,
                    control: button("Remove") { [weak self] in
                        self?.removeInstalledPackage(kind: .plugin, id: package.manifest.id, name: package.manifest.name)
                    }
                ))
            }
            rows.append(contentsOf: package.manifest.settings.sorted { ($0.order ?? 0, $0.title) < ($1.order ?? 0, $1.title) }.map { setting in
                RowSpec(
                    title: "\(package.manifest.name): \(setting.title)",
                    value: displayJSON(settingValue(setting, pluginID: package.manifest.id)),
                    detail: setting.help ?? setting.environment ?? setting.id,
                    control: control(for: setting, pluginID: package.manifest.id)
                )
            })
            return rows
        }
    }

    private func executableStatus(for transport: PluginEntry.Transport) -> String {
        switch transport {
        case .shell, .stdioJSONRPC:
            return "local"
        case .php:
            return "optional PHP"
        case .webView:
            return "web view"
        case .nativeSwift:
            return "preview"
        case .websocket:
            return "bridge"
        }
    }

    private func removeInstalledPackage(kind: QuakePackageKind, id: String, name: String) {
        do {
            try QuakePackageInstaller.removeInstalledPackage(kind: kind, id: id)
            showAlert(title: "Removed \(kind.rawValue)", message: "\(name) was removed. Restart QuakeKit to refresh loaded packages.")
            onConfigurationChanged()
            rebuildRows()
        } catch {
            showAlert(title: "Remove Failed", message: String(describing: error))
        }
    }

    private func isInstalledPackage(_ url: URL, suffix: String) -> Bool {
        guard url.pathExtension == suffix else { return false }
        let installedRoot: URL?
        if suffix == "quakekitplugin" {
            installedRoot = try? QuakePackageLocations.installedPluginDirectory()
        } else {
            installedRoot = try? QuakePackageLocations.installedThemeDirectory()
        }
        guard let installedRoot else { return false }
        return url.standardizedFileURL.path.hasPrefix(installedRoot.standardizedFileURL.path + "/")
    }

    private func installedPackageLabel(_ url: URL, suffix: String) -> String {
        isInstalledPackage(url, suffix: suffix) ? "Installed" : "Bundled"
    }

    private func aboutRows() -> [RowSpec] {
        [
            RowSpec(title: "QuakeKit", value: "Native DK-QUAKE control center", detail: "Swift/AppKit host with HID wake, keep-alive, panel ownership, themes, plugins, and settings.", control: nil),
            RowSpec(title: "Loaded Plugins", value: "\(pluginPackages.count)", detail: pluginPackages.map(\.manifest.name).joined(separator: ", "), control: nil),
            RowSpec(title: "Loaded Themes", value: "\(themePackages.count)", detail: themePackages.map(\.manifest.name).joined(separator: ", "), control: nil),
            RowSpec(title: "Reload Note", value: "Live settings", detail: "Most preference changes apply immediately; package install/remove still requires restart.", control: nil)
        ]
    }

    private func control(for option: ThemeOption) -> NSView? {
        let current = themeConfiguration.overrides[option.target] ?? option.defaultValue
        switch option.type {
        case .boolean:
            return checkbox(isOn: current.boolValue ?? false) { [weak self] enabled in
                self?.themeConfiguration.overrides[option.target] = .bool(enabled)
                self?.saveThemeConfiguration()
            }
        case .choice:
            return popup(values: option.choices.map { displayJSON($0) }, titles: option.choices.map { displayJSON($0) }, selectedValue: displayJSON(current)) { [weak self] value in
                guard let self, let choice = option.choices.first(where: { self.displayJSON($0) == value }) else { return }
                self.themeConfiguration.overrides[option.target] = choice
                self.saveThemeConfiguration()
            }
        case .color:
            return popup(values: colorSwatches(for: option), titles: colorSwatches(for: option), selectedValue: current.stringValue ?? "") { [weak self] value in
                self?.themeConfiguration.overrides[option.target] = .string(value)
                self?.saveThemeConfiguration()
            }
        case .number:
            return stepper(value: current.doubleValue ?? option.defaultValue.doubleValue ?? 0, minimum: option.minimum ?? 0, maximum: option.maximum ?? 100, increment: 1) { [weak self] value in
                self?.themeConfiguration.overrides[option.target] = .double(value)
                self?.saveThemeConfiguration()
            }
        }
    }

    private func control(for setting: PluginSetting, pluginID: String) -> NSView? {
        let current = settingValue(setting, pluginID: pluginID)
        switch setting.type {
        case .boolean:
            return checkbox(isOn: current.boolValue ?? false) { [weak self] enabled in
                self?.setPluginSetting(pluginID: pluginID, setting: setting, value: .bool(enabled))
            }
        case .choice:
            return popup(values: setting.choices.map { displayJSON($0) }, titles: setting.choices.map { displayJSON($0) }, selectedValue: displayJSON(current)) { [weak self] value in
                guard let self, let choice = setting.choices.first(where: { self.displayJSON($0) == value }) else { return }
                self.setPluginSetting(pluginID: pluginID, setting: setting, value: choice)
            }
        case .integer:
            return stepper(value: Double(current.integerValue ?? 0), minimum: setting.minimum ?? 0, maximum: setting.maximum ?? 100, increment: 1) { [weak self] value in
                self?.setPluginSetting(pluginID: pluginID, setting: setting, value: .integer(Int(value.rounded())))
            }
        case .number:
            return stepper(value: current.doubleValue ?? 0, minimum: setting.minimum ?? 0, maximum: setting.maximum ?? 100, increment: 1) { [weak self] value in
                self?.setPluginSetting(pluginID: pluginID, setting: setting, value: .double(value))
            }
        case .string:
            return textField(value: current.stringValue ?? "") { [weak self] value in
                self?.setPluginSetting(pluginID: pluginID, setting: setting, value: .string(value))
            }
        case .secret:
            return secureField(value: current.stringValue ?? "") { [weak self] value in
                self?.setPluginSetting(pluginID: pluginID, setting: setting, value: .string(value))
            }
        }
    }

    private func setPluginSetting(pluginID: String, setting: PluginSetting, value: JSONValue) {
        settings.pluginSettings[pluginID, default: [:]][setting.id] = value
        saveSettings()
    }

    private func setCarousel(id: String, included: Bool) {
        if settings.carousel.widgetIDs.isEmpty {
            settings.carousel.widgetIDs = carouselRefs().map(\.id)
        }
        if included {
            if !settings.carousel.widgetIDs.contains(id) {
                settings.carousel.widgetIDs.append(id)
            }
        } else {
            settings.carousel.widgetIDs.removeAll { $0 == id }
        }
        saveSettings()
    }

    private func includeAllCarouselWidgets() {
        settings.carousel.widgetIDs = carouselRefs().map(\.id)
        saveSettings()
    }

    private func clearCarouselWidgets() {
        settings.carousel.widgetIDs = []
        saveSettings()
    }

    private func carouselIncluded(id: String) -> Bool {
        settings.carousel.widgetIDs.isEmpty || settings.carousel.widgetIDs.contains(id)
    }

    private func carouselIncludedWidgetIDs() -> [String] {
        settings.carousel.widgetIDs.isEmpty ? carouselRefs().map(\.id) : settings.carousel.widgetIDs
    }

    private func carouselRefs() -> [CarouselWidgetRef] {
        pluginPackages.flatMap { package in
            package.manifest.views.compactMap { view in
                let presentation = view.presentation ?? .page
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

    private func settingValue(_ setting: PluginSetting, pluginID: String) -> JSONValue {
        settings.pluginSettings[pluginID]?[setting.id] ?? setting.defaultValue
    }

    private func activeThemeManifest() -> ThemeManifest? {
        if let id = themeConfiguration.activeThemeID {
            return themePackages.first { $0.manifest.id == id }?.manifest
        }
        return themePackages.first?.manifest
    }

    private func activeThemeName() -> String {
        activeThemeManifest()?.name ?? "Fallback"
    }

    private func pageTitle(_ index: Int) -> String {
        switch index {
        case 0: return "1 Home"
        case 1: return "2 Widgets"
        case 2: return "3 Apps"
        case 3: return "4 Themes"
        case 4: return "5 Settings"
        case 5: return "6 Runtime"
        case 6: return "7 Plugin APIs"
        default: return "Page \(index + 1)"
        }
    }

    private func colorSwatches(for option: ThemeOption) -> [String] {
        let defaultColor = option.defaultValue.stringValue ?? "#7CFFD1"
        return [defaultColor, "#39F5FF", "#FF5CDB", "#A7FF57", "#FFE66D", "#FF6B5C", "#FFFFFF"]
    }

    private func displayJSON(_ value: JSONValue) -> String {
        switch value {
        case .string(let value):
            return value
        case .integer(let value):
            return "\(value)"
        case .double(let value):
            return value.rounded() == value ? String(format: "%.0f", value) : String(format: "%.2f", value)
        case .bool(let value):
            return value ? "on" : "off"
        case .null:
            return "-"
        case .array(let values):
            return "\(values.count) values"
        case .object(let object):
            return "\(object.count) fields"
        }
    }

    private func popup(values: [String], titles: [String], selectedValue: String, onChange: @escaping (String) -> Void) -> NSView {
        let popup = ClosurePopUpButton()
        for (index, value) in values.enumerated() {
            popup.addItem(withTitle: titles.indices.contains(index) ? titles[index] : value)
            popup.item(at: index)?.representedObject = value
        }
        if let index = values.firstIndex(of: selectedValue) {
            popup.selectItem(at: index)
        }
        popup.onChange = {
            guard let value = popup.selectedItem?.representedObject as? String else { return }
            onChange(value)
        }
        return popup
    }

    private func checkbox(isOn: Bool, onChange: @escaping (Bool) -> Void) -> NSView {
        let box = ClosureCheckbox(title: "")
        box.state = isOn ? .on : .off
        box.onChange = { onChange(box.state == .on) }
        return box
    }

    private func button(_ title: String, action: @escaping () -> Void) -> NSView {
        let button = ClosureButton(title: title)
        button.onPress = action
        return button
    }

    private func buttonRow(_ specs: [(String, () -> Void)]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.distribution = .fillEqually
        for (title, action) in specs {
            stack.addArrangedSubview(button(title, action: action))
        }
        return stack
    }

    private func stepper(value: Double, minimum: Double, maximum: Double, increment: Double, onChange: @escaping (Double) -> Void) -> NSView {
        let container = NSView()
        let field = NSTextField(labelWithString: String(format: "%.0f", value))
        let stepper = ClosureStepper()
        stepper.minValue = minimum
        stepper.maxValue = maximum
        stepper.increment = increment
        stepper.doubleValue = min(max(value, minimum), maximum)
        field.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        field.alignment = .right
        field.backgroundColor = .clear
        stepper.onChange = {
            field.stringValue = String(format: "%.0f", stepper.doubleValue)
            onChange(stepper.doubleValue)
        }
        container.addSubview(field)
        container.addSubview(stepper)
        container.wantsLayer = true
        container.frame = NSRect(x: 0, y: 0, width: 128, height: 28)
        field.frame = NSRect(x: 0, y: 4, width: 72, height: 20)
        stepper.frame = NSRect(x: 80, y: 0, width: 28, height: 28)
        return container
    }

    private func textField(value: String, onCommit: @escaping (String) -> Void) -> NSView {
        let field = ClosureTextField(string: value)
        field.onCommit = { onCommit(field.stringValue) }
        return field
    }

    private func secureField(value: String, onCommit: @escaping (String) -> Void) -> NSView {
        let field = ClosureSecureTextField(string: value)
        field.placeholderString = "Secret value"
        field.onCommit = { onCommit(field.stringValue) }
        return field
    }
}

private final class SettingsRowView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let control: NSView?

    init(title: String, value: String, detail: String, control: NSView?) {
        self.control = control
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

        if let control {
            addSubview(control)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let controlWidth: CGFloat = control == nil ? 0 : 190
        let titleWidth = max(160, min(bounds.width * 0.42, bounds.width - controlWidth - 64))
        let valueX = titleWidth + 28
        let valueWidth = max(0, bounds.width - valueX - controlWidth - 28)
        titleLabel.frame = NSRect(x: 16, y: bounds.height - 30, width: titleWidth, height: 20)
        valueLabel.frame = NSRect(x: valueX, y: bounds.height - 30, width: valueWidth, height: 20)
        detailLabel.frame = NSRect(x: 16, y: 14, width: max(0, bounds.width - controlWidth - 44), height: 20)
        control?.frame = NSRect(x: bounds.width - controlWidth - 16, y: 22, width: controlWidth, height: 30)
    }
}

private final class ClosureButton: NSButton {
    var onPress: (() -> Void)?

    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        bezelStyle = .rounded
        target = self
        action = #selector(pressed)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func pressed() {
        onPress?()
    }
}

private final class ClosureCheckbox: NSButton {
    var onChange: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setButtonType(.switch)
        target = self
        action = #selector(changed)
    }

    convenience init(title: String) {
        self.init(frame: .zero)
        self.title = title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func changed() {
        onChange?()
    }
}

private final class ClosurePopUpButton: NSPopUpButton {
    var onChange: (() -> Void)?

    init() {
        super.init(frame: .zero, pullsDown: false)
        target = self
        action = #selector(changed)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func changed() {
        onChange?()
    }
}

private final class ClosureStepper: NSStepper {
    var onChange: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        target = self
        action = #selector(changed)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func changed() {
        onChange?()
    }
}

private final class ClosureTextField: NSTextField, NSTextFieldDelegate {
    var onCommit: (() -> Void)?

    init(string: String) {
        super.init(frame: .zero)
        stringValue = string
        isBezeled = true
        isEditable = true
        delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        onCommit?()
    }
}

private final class ClosureSecureTextField: NSSecureTextField, NSTextFieldDelegate {
    var onCommit: (() -> Void)?

    init(string: String) {
        super.init(frame: .zero)
        stringValue = string
        isBezeled = true
        isEditable = true
        delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        onCommit?()
    }
}
