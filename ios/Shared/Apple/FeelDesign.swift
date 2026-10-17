import SwiftUI
import UIKit

/// A native interpretation of Vercel's Geist visual language, not its web UI kit.
/// Fonts are official OFL-licensed Geist. Geometry: 8pt controls, 10pt data panels.
/// Colors invert with system appearance; status meaning never depends on color.
enum FeelTheme {
    private static func gray(light: CGFloat, dark: CGFloat) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(white: traits.userInterfaceStyle == .dark ? dark : light, alpha: 1)
        })
    }
    static let accent = gray(light: 0.08, dark: 0.94)
    static let onAccent = gray(light: 0.98, dark: 0.07)
    static let canvas = gray(light: 0.985, dark: 0.055)
    static let surface = gray(light: 0.985, dark: 0.055)
    static let inset = gray(light: 0.955, dark: 0.095)
    static let border = gray(light: 0.83, dark: 0.25)
    static let secondary = gray(light: 0.36, dark: 0.66)
    static let inactivePin = gray(light: 0.90, dark: 0.19)
}

enum FeelTypography {
    static let largeTitle = Font.custom("Geist-Bold", size: 34, relativeTo: .largeTitle)
    static let title2 = Font.custom("Geist-SemiBold", size: 22, relativeTo: .title2)
    static let title3 = Font.custom("Geist-SemiBold", size: 20, relativeTo: .title3)
    static let headline = Font.custom("Geist-SemiBold", size: 17, relativeTo: .headline)
    static let body = Font.custom("Geist-Regular", size: 17, relativeTo: .body)
    static let subheadline = Font.custom("Geist-Regular", size: 15, relativeTo: .subheadline)
    static let label = Font.custom("Geist-Medium", size: 15, relativeTo: .subheadline)
    static let footnote = Font.custom("Geist-Regular", size: 13, relativeTo: .footnote)
    static let caption = Font.custom("GeistMono-Regular", size: 12, relativeTo: .caption)
    static let mono = Font.custom("GeistMono-Regular", size: 15, relativeTo: .body)
}

struct FeelPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FeelTypography.headline)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 16).padding(.vertical, 4)
            .foregroundStyle(isEnabled ? FeelTheme.onAccent : FeelTheme.secondary)
            .background(isEnabled ? FeelTheme.accent : FeelTheme.inset)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct FeelSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FeelTypography.headline)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 16).padding(.vertical, 4)
            .foregroundStyle(isEnabled ? FeelTheme.accent : FeelTheme.secondary)
            .background(isEnabled ? FeelTheme.surface : FeelTheme.inset)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(FeelTheme.border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

struct FeelStopButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FeelTypography.headline)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 16).padding(.vertical, 4)
            .foregroundStyle(isEnabled ? FeelTheme.accent : FeelTheme.secondary)
            .background(FeelTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isEnabled ? FeelTheme.accent : FeelTheme.border, lineWidth: isEnabled ? 2 : 1))
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

/// Flat sections use whitespace and a single separator instead of nested cards.
struct FeelSection<Content: View>: View {
    let title: String
    var systemImage: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage).foregroundStyle(FeelTheme.secondary).accessibilityHidden(true)
                }
                Text(title).font(FeelTypography.headline).accessibilityAddTraits(.isHeader)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 20)
        .overlay(alignment: .top) { Rectangle().fill(FeelTheme.border).frame(height: 1) }
    }
}
