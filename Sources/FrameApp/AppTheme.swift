import AppKit

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var appearanceName: NSAppearance.Name? {
        switch self {
        case .system: nil
        case .light: .aqua
        case .dark: .darkAqua
        }
    }

    @MainActor
    func apply(to application: NSApplication) {
        application.appearance = appearanceName.flatMap { NSAppearance(named: $0) }
    }

    func displayName(strings: AppStrings) -> String {
        switch (strings.language, self) {
        case (.zhHans, .system): "跟随系统"
        case (.zhHans, .light): "浅色"
        case (.zhHans, .dark): "深色"
        case (.en, .system): "Follow System"
        case (.en, .light): "Light"
        case (.en, .dark): "Dark"
        }
    }
}
