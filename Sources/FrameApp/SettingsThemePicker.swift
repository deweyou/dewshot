import SwiftUI

struct SettingsThemePicker: View {
    let strings: AppStrings
    @Binding var selection: AppTheme

    var body: some View {
        HStack(spacing: 10) {
            ForEach(AppTheme.allCases) { theme in
                SettingsThemeOption(
                    theme: theme,
                    title: theme.displayName(strings: strings),
                    isSelected: theme == selection,
                    select: { selection = theme }
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(strings.settingsAppearance)
    }
}

private struct SettingsThemeOption: View {
    let theme: AppTheme
    let title: String
    let isSelected: Bool
    let select: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 8) {
                preview
                    .frame(height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityHidden(true)

                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.6))
                        .accessibilityHidden(true)
                }
            }
            .padding(7)
            .frame(maxWidth: .infinity)
            .background(
                isSelected ? Color.accentColor.opacity(0.07) : Color.primary.opacity(isHovering ? 0.055 : 0.025),
                in: RoundedRectangle(cornerRadius: 9)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.72) : Color.primary.opacity(0.09),
                        lineWidth: isSelected ? 1.5 : 1
                    )
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.appearance.\(theme.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var preview: some View {
        switch theme {
        case .system:
            ThemeThumbnail(isDark: false)
                .overlay {
                    ThemeThumbnail(isDark: true)
                        .mask {
                            HStack(spacing: 0) {
                                Rectangle().fill(.clear)
                                Rectangle().fill(.black)
                            }
                        }
                }
        case .light:
            ThemeThumbnail(isDark: false)
        case .dark:
            ThemeThumbnail(isDark: true)
        }
    }
}

private struct ThemeThumbnail: View {
    let isDark: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 3) {
                    ForEach(0..<3) { _ in
                        Circle().fill(ink.opacity(0.32)).frame(width: 3, height: 3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 7)
                .frame(height: 12)
                .background(Color(white: isDark ? 0.23 : 0.92))

                VStack(alignment: .leading, spacing: 4) {
                    Capsule().fill(ink.opacity(0.30)).frame(width: 29, height: 3)
                    Capsule().fill(ink.opacity(0.14)).frame(width: 45, height: 2)
                }
                .padding(.leading, 8)
                .padding(.top, 7)

                Spacer(minLength: 0)
            }
            .background(Color(white: isDark ? 0.14 : 0.98))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(ink.opacity(0.12), lineWidth: 0.5)
            }
            .padding(.horizontal, 16)
            .padding(.top, 7)
            .padding(.bottom, 9)

            HStack(spacing: 5) {
                Image(systemName: "crop")
                Image(systemName: "record.circle")
            }
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(ink)
            .padding(.horizontal, 6)
            .frame(height: 14)
            .background(Color(white: isDark ? 0.33 : 0.94), in: Capsule())
            .padding(.bottom, 5)
        }
        .background(Color(white: isDark ? 0.10 : 0.85))
    }

    private var ink: Color {
        Color(white: isDark ? 0.88 : 0.24)
    }
}
