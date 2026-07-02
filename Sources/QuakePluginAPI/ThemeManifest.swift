import Foundation

public struct ThemeManifest: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var version: String
    public var apiVersion: String
    public var kind: ThemeKind
    public var author: String?
    public var description: String?
    public var palette: ThemePalette
    public var typography: ThemeTypography?
    public var metrics: ThemeMetrics?
    public var components: ThemeComponents?
    public var hardware: ThemeHardware?
    public var assets: [ThemeAsset]
    public var options: [ThemeOption]

    public init(
        id: String,
        name: String,
        version: String,
        apiVersion: String = ThemeManifestValidator.currentAPIVersion,
        kind: ThemeKind = .theme,
        author: String? = nil,
        description: String? = nil,
        palette: ThemePalette,
        typography: ThemeTypography? = nil,
        metrics: ThemeMetrics? = nil,
        components: ThemeComponents? = nil,
        hardware: ThemeHardware? = nil,
        assets: [ThemeAsset] = [],
        options: [ThemeOption] = []
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.apiVersion = apiVersion
        self.kind = kind
        self.author = author
        self.description = description
        self.palette = palette
        self.typography = typography
        self.metrics = metrics
        self.components = components
        self.hardware = hardware
        self.assets = assets
        self.options = options
    }
}

public enum ThemeKind: String, Codable, Equatable, Sendable {
    case theme
}

public struct ThemePalette: Codable, Equatable, Sendable {
    public var mode: ThemeColorMode
    public var colors: [String: ThemeColor]
    public var semanticColors: ThemeSemanticColors?

    public init(mode: ThemeColorMode = .dark, colors: [String: ThemeColor], semanticColors: ThemeSemanticColors? = nil) {
        self.mode = mode
        self.colors = colors
        self.semanticColors = semanticColors
    }
}

public enum ThemeColorMode: String, Codable, Equatable, Sendable {
    case dark
    case light
    case adaptive
}

public struct ThemeColor: Codable, Equatable, Sendable {
    public var value: String
    public var role: String?
    public var configurable: Bool

    public init(value: String, role: String? = nil, configurable: Bool = false) {
        self.value = value
        self.role = role
        self.configurable = configurable
    }
}

public struct ThemeSemanticColors: Codable, Equatable, Sendable {
    public var background: String
    public var surface: String
    public var surfaceRaised: String
    public var border: String
    public var textPrimary: String
    public var textSecondary: String
    public var accent: String
    public var success: String
    public var warning: String
    public var danger: String

    public init(
        background: String,
        surface: String,
        surfaceRaised: String,
        border: String,
        textPrimary: String,
        textSecondary: String,
        accent: String,
        success: String,
        warning: String,
        danger: String
    ) {
        self.background = background
        self.surface = surface
        self.surfaceRaised = surfaceRaised
        self.border = border
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.accent = accent
        self.success = success
        self.warning = warning
        self.danger = danger
    }
}

public struct ThemeTypography: Codable, Equatable, Sendable {
    public var displayFont: String?
    public var bodyFont: String?
    public var monoFont: String?
    public var scale: [String: Double]

    public init(displayFont: String? = nil, bodyFont: String? = nil, monoFont: String? = nil, scale: [String: Double] = [:]) {
        self.displayFont = displayFont
        self.bodyFont = bodyFont
        self.monoFont = monoFont
        self.scale = scale
    }
}

public struct ThemeMetrics: Codable, Equatable, Sendable {
    public var cornerRadius: Double?
    public var borderWidth: Double?
    public var spacing: Double?
    public var density: ThemeDensity?

    public init(cornerRadius: Double? = nil, borderWidth: Double? = nil, spacing: Double? = nil, density: ThemeDensity? = nil) {
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        self.spacing = spacing
        self.density = density
    }
}

public enum ThemeDensity: String, Codable, Equatable, Sendable {
    case compact
    case standard
    case comfortable
}

public struct ThemeComponents: Codable, Equatable, Sendable {
    public var tile: ThemeComponentStyle?
    public var tab: ThemeComponentStyle?
    public var statusRow: ThemeComponentStyle?
    public var gauge: ThemeComponentStyle?
    public var chart: ThemeComponentStyle?

    public init(
        tile: ThemeComponentStyle? = nil,
        tab: ThemeComponentStyle? = nil,
        statusRow: ThemeComponentStyle? = nil,
        gauge: ThemeComponentStyle? = nil,
        chart: ThemeComponentStyle? = nil
    ) {
        self.tile = tile
        self.tab = tab
        self.statusRow = statusRow
        self.gauge = gauge
        self.chart = chart
    }
}

public struct ThemeComponentStyle: Codable, Equatable, Sendable {
    public var background: String?
    public var foreground: String?
    public var border: String?
    public var accent: String?
    public var selectedBackground: String?
    public var selectedBorder: String?

    public init(
        background: String? = nil,
        foreground: String? = nil,
        border: String? = nil,
        accent: String? = nil,
        selectedBackground: String? = nil,
        selectedBorder: String? = nil
    ) {
        self.background = background
        self.foreground = foreground
        self.border = border
        self.accent = accent
        self.selectedBackground = selectedBackground
        self.selectedBorder = selectedBorder
    }
}

public struct ThemeHardware: Codable, Equatable, Sendable {
    public var knobRing: ThemeKnobRing?

    public init(knobRing: ThemeKnobRing? = nil) {
        self.knobRing = knobRing
    }
}

public struct ThemeKnobRing: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var idle: ThemeKnobRingState?
    public var focus: ThemeKnobRingState?
    public var success: ThemeKnobRingState?
    public var warning: ThemeKnobRingState?
    public var danger: ThemeKnobRingState?
    public var progress: ThemeKnobRingState?

    public init(
        enabled: Bool = true,
        idle: ThemeKnobRingState? = nil,
        focus: ThemeKnobRingState? = nil,
        success: ThemeKnobRingState? = nil,
        warning: ThemeKnobRingState? = nil,
        danger: ThemeKnobRingState? = nil,
        progress: ThemeKnobRingState? = nil
    ) {
        self.enabled = enabled
        self.idle = idle
        self.focus = focus
        self.success = success
        self.warning = warning
        self.danger = danger
        self.progress = progress
    }
}

public struct ThemeKnobRingState: Codable, Equatable, Sendable {
    public var color: String
    public var intensity: Double
    public var animation: ThemeKnobRingAnimation

    public init(color: String, intensity: Double = 1, animation: ThemeKnobRingAnimation = .solid) {
        self.color = color
        self.intensity = intensity
        self.animation = animation
    }
}

public enum ThemeKnobRingAnimation: String, Codable, Equatable, Sendable {
    case solid
    case pulse
    case flash
    case strobe
    case progress
    case off
}

public struct ThemeAsset: Codable, Equatable, Identifiable, Sendable {
    public enum AssetKind: String, Codable, Sendable {
        case image
        case font
        case sound
        case css
        case script
    }

    public var id: String
    public var kind: AssetKind
    public var path: String
    public var scale: Double?

    public init(id: String, kind: AssetKind, path: String, scale: Double? = nil) {
        self.id = id
        self.kind = kind
        self.path = path
        self.scale = scale
    }
}

public struct ThemeOption: Codable, Equatable, Identifiable, Sendable {
    public enum OptionType: String, Codable, Sendable {
        case color
        case number
        case boolean
        case choice
    }

    public var id: String
    public var title: String
    public var type: OptionType
    public var target: String
    public var defaultValue: JSONValue
    public var choices: [JSONValue]
    public var minimum: Double?
    public var maximum: Double?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case type
        case target
        case defaultValue
        case choices
        case minimum
        case maximum
    }

    public init(
        id: String,
        title: String,
        type: OptionType,
        target: String,
        defaultValue: JSONValue,
        choices: [JSONValue] = [],
        minimum: Double? = nil,
        maximum: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.target = target
        self.defaultValue = defaultValue
        self.choices = choices
        self.minimum = minimum
        self.maximum = maximum
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.type = try container.decode(OptionType.self, forKey: .type)
        self.target = try container.decode(String.self, forKey: .target)
        self.defaultValue = try container.decode(JSONValue.self, forKey: .defaultValue)
        self.choices = try container.decodeIfPresent([JSONValue].self, forKey: .choices) ?? []
        self.minimum = try container.decodeIfPresent(Double.self, forKey: .minimum)
        self.maximum = try container.decodeIfPresent(Double.self, forKey: .maximum)
    }
}

public struct ThemeValidationResult: Equatable, Sendable {
    public var isValid: Bool { errors.isEmpty }
    public var errors: [String]
    public var warnings: [String]

    public init(errors: [String] = [], warnings: [String] = []) {
        self.errors = errors
        self.warnings = warnings
    }
}

public enum ThemeManifestValidator {
    public static let currentAPIVersion = "0.1"
    public static let idPattern = #"^[a-z0-9][a-z0-9_-]*$"#
    public static let colorPattern = #"^#(?:[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$"#
    public static let colorReferencePattern = #"^[a-zA-Z][a-zA-Z0-9_.-]*$"#

    public static func validate(_ manifest: ThemeManifest) -> ThemeValidationResult {
        var errors: [String] = []
        var warnings: [String] = []

        if manifest.id.range(of: idPattern, options: .regularExpression) == nil {
            errors.append("Theme id must match \(idPattern).")
        }
        if manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Theme name is required.")
        }
        if manifest.apiVersion != currentAPIVersion {
            warnings.append("Theme API version \(manifest.apiVersion) differs from host API \(currentAPIVersion).")
        }
        if manifest.palette.colors.isEmpty {
            errors.append("Theme palette must define at least one color.")
        }

        for (id, color) in manifest.palette.colors {
            if !isColorValue(color.value) {
                errors.append("Color \(id) must be a #RRGGBB or #RRGGBBAA value.")
            }
        }

        if let semanticColors = manifest.palette.semanticColors {
            let references = [
                semanticColors.background,
                semanticColors.surface,
                semanticColors.surfaceRaised,
                semanticColors.border,
                semanticColors.textPrimary,
                semanticColors.textSecondary,
                semanticColors.accent,
                semanticColors.success,
                semanticColors.warning,
                semanticColors.danger
            ]
            for reference in references where !isColorReference(reference, colors: manifest.palette.colors) {
                errors.append("Semantic color reference \(reference) must be a palette key or literal color.")
            }
        }

        if let knobRing = manifest.hardware?.knobRing {
            let states = [
                knobRing.idle,
                knobRing.focus,
                knobRing.success,
                knobRing.warning,
                knobRing.danger,
                knobRing.progress
            ].compactMap { $0 }

            for state in states {
                if !(0...1).contains(state.intensity) {
                    errors.append("Knob ring intensity must be between 0 and 1.")
                }
                if !isColorReference(state.color, colors: manifest.palette.colors) {
                    errors.append("Knob ring color reference \(state.color) must be a palette key or literal color.")
                }
            }
        }

        let assetIDs = manifest.assets.map(\.id)
        if Set(assetIDs).count != assetIDs.count {
            errors.append("Theme asset ids must be unique.")
        }

        let optionIDs = manifest.options.map(\.id)
        if Set(optionIDs).count != optionIDs.count {
            errors.append("Theme option ids must be unique.")
        }

        for option in manifest.options where option.type == .choice && option.choices.isEmpty {
            errors.append("Choice option \(option.id) must define choices.")
        }

        return ThemeValidationResult(errors: errors, warnings: warnings)
    }

    private static func isColorValue(_ value: String) -> Bool {
        value.range(of: colorPattern, options: .regularExpression) != nil
    }

    private static func isColorReference(_ reference: String, colors: [String: ThemeColor]) -> Bool {
        isColorValue(reference) || colors[reference] != nil || reference.range(of: colorReferencePattern, options: .regularExpression) != nil
    }
}
