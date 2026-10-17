import SwiftUI
import UIKit

/// Quiet neutral surfaces keep the camera dominant. Controls retain clear outlines,
/// scalable Geist labels and an orange accent for tactile/connection state.
enum FeelTheme {
    private static func dynamic(light: CGFloat, dark: CGFloat) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(white: traits.userInterfaceStyle == .dark ? dark : light, alpha: 1)
        })
    }
    static let paper = dynamic(light: 1.0, dark: 0.065)
    static let ink = dynamic(light: 0.06, dark: 0.94)
    /// The puck's target color, also the one accent: primary actions and live state.
    static let pin = Color(red: 1.0, green: 0.353, blue: 0.122)
    /// Simulation notices only.
    static let notice = Color(red: 1.0, green: 0.84, blue: 0.04)

    static let accent = ink
    static let onAccent = paper
    static let canvas = dynamic(light: 0.97, dark: 0.025)
    static let surface = paper
    static let inset = dynamic(light: 0.94, dark: 0.13)
    static let border = dynamic(light: 0.44, dark: 0.45)
    static let divider = dynamic(light: 0.84, dark: 0.22)
    static let secondary = dynamic(light: 0.38, dark: 0.70)
    static let inactivePin = inset

    static let borderWidth: CGFloat = 1
}

enum FeelTypography {
    static let largeTitle = Font.custom("Geist-Bold", size: 34, relativeTo: .largeTitle)
    static let title2 = Font.custom("Geist-Bold", size: 24, relativeTo: .title2)
    static let title3 = Font.custom("Geist-Bold", size: 20, relativeTo: .title3)
    static let headline = Font.custom("Geist-Bold", size: 17, relativeTo: .headline)
    static let body = Font.custom("Geist-Regular", size: 17, relativeTo: .body)
    static let subheadline = Font.custom("Geist-Regular", size: 15, relativeTo: .subheadline)
    static let label = Font.custom("Geist-SemiBold", size: 15, relativeTo: .subheadline)
    static let footnote = Font.custom("Geist-Regular", size: 13, relativeTo: .footnote)
    static let caption = Font.custom("Geist-Medium", size: 12, relativeTo: .caption)
    static let mono = Font.custom("GeistMono-Regular", size: 15, relativeTo: .body)
}

/// Solid surfaces remain legible over a bright camera feed without transparency.
struct FeelBlock<S: InsettableShape>: ViewModifier {
    let shape: S
    var fill: Color = FeelTheme.paper
    var shadow: CGFloat = 6
    var lineWidth: CGFloat = FeelTheme.borderWidth
    func body(content: Content) -> some View {
        content
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(FeelTheme.border, lineWidth: lineWidth))
    }
}

extension View {
    func feelBlock<S: InsettableShape>(_ shape: S, fill: Color = FeelTheme.paper, shadow: CGFloat = 6) -> some View {
        modifier(FeelBlock(shape: shape, fill: fill, shadow: shadow))
    }
    func feelBlock(fill: Color = FeelTheme.paper, shadow: CGFloat = 6) -> some View {
        modifier(FeelBlock(shape: RoundedRectangle(cornerRadius: 12, style: .continuous), fill: fill, shadow: shadow))
    }
}

/// Inputs use the same quiet surface and visible outline as other controls.
struct FeelFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(FeelTypography.body)
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(FeelTheme.inset, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(FeelTheme.border, lineWidth: 1))
    }
}

extension View {
    func feelField() -> some View { textFieldStyle(.plain).modifier(FeelFieldStyle()) }
}

/// Press feedback dims the control without moving its touch target.
private struct FeelButtonBody: View {
    let label: AnyView
    let fill: Color
    let foreground: Color
    let enabled: Bool
    let pressed: Bool
    var body: some View {
        label
            .font(FeelTypography.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, 16).padding(.vertical, 4)
            .foregroundStyle(enabled ? foreground : FeelTheme.secondary)
            .background(pressed && enabled ? FeelTheme.inset : fill, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(FeelTheme.border, lineWidth: 1))
            .opacity(enabled ? (pressed ? 0.78 : 1) : 0.6)
    }
}

struct FeelPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        FeelButtonBody(label: AnyView(configuration.label), fill: FeelTheme.inset, foreground: FeelTheme.ink, enabled: isEnabled, pressed: configuration.isPressed)
    }
}

struct FeelSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        FeelButtonBody(label: AnyView(configuration.label), fill: FeelTheme.paper, foreground: FeelTheme.ink, enabled: isEnabled, pressed: configuration.isPressed)
    }
}

struct FeelStopButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        FeelButtonBody(label: AnyView(configuration.label), fill: FeelTheme.inset, foreground: FeelTheme.ink, enabled: isEnabled, pressed: configuration.isPressed)
    }
}

/// Sections use a fine divider and a readable heading.
struct FeelSection<Content: View>: View {
    let title: String
    var systemImage: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(FeelTypography.title3).accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 20)
        .overlay(alignment: .top) { Rectangle().fill(FeelTheme.divider).frame(height: 1) }
    }
}
