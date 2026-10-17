import SwiftUI
import UIKit

/// Minimalist neobrutalism: paper and ink, 3-point borders, hard offset shadows, one loud
/// accent. Paper and ink invert with system appearance; the accent does not. Status
/// meaning never depends on color. Fonts are the official OFL-licensed Geist.
enum FeelTheme {
    private static func dynamic(light: CGFloat, dark: CGFloat) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(white: traits.userInterfaceStyle == .dark ? dark : light, alpha: 1)
        })
    }
    static let paper = dynamic(light: 1.0, dark: 0.0)
    static let ink = dynamic(light: 0.0, dark: 1.0)
    /// The puck's target color, also the one accent: primary actions and live state.
    static let pin = Color(red: 1.0, green: 0.353, blue: 0.122)
    /// Simulation notices only.
    static let notice = Color(red: 1.0, green: 0.84, blue: 0.04)

    static let accent = ink
    static let onAccent = paper
    static let canvas = paper
    static let surface = paper
    static let inset = dynamic(light: 0.94, dark: 0.13)
    static let border = ink
    static let secondary = dynamic(light: 0.38, dark: 0.70)
    static let inactivePin = paper

    static let borderWidth: CGFloat = 3
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

/// A bordered block with a hard offset shadow: the one structural device of this design.
struct FeelBlock<S: InsettableShape>: ViewModifier {
    let shape: S
    var fill: Color = FeelTheme.paper
    var shadow: CGFloat = 6
    var lineWidth: CGFloat = FeelTheme.borderWidth
    func body(content: Content) -> some View {
        content
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(FeelTheme.ink, lineWidth: lineWidth))
            .background(shape.fill(FeelTheme.ink).offset(x: shadow, y: shadow))
            .padding(.trailing, shadow).padding(.bottom, shadow)
    }
}

extension View {
    func feelBlock<S: InsettableShape>(_ shape: S, fill: Color = FeelTheme.paper, shadow: CGFloat = 6) -> some View {
        modifier(FeelBlock(shape: shape, fill: fill, shadow: shadow))
    }
    func feelBlock(fill: Color = FeelTheme.paper, shadow: CGFloat = 6) -> some View {
        modifier(FeelBlock(shape: Rectangle(), fill: fill, shadow: shadow))
    }
}

/// Text fields are square, bordered boxes; no rounded system chrome.
struct FeelFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(FeelTypography.body)
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(FeelTheme.paper)
            .overlay(Rectangle().strokeBorder(FeelTheme.ink, lineWidth: 2))
    }
}

extension View {
    func feelField() -> some View { textFieldStyle(.plain).modifier(FeelFieldStyle()) }
}

/// Buttons press into their own shadow instead of fading.
private struct FeelButtonBody: View {
    let label: AnyView
    let fill: Color
    let foreground: Color
    let enabled: Bool
    let pressed: Bool
    var body: some View {
        let shadow: CGFloat = enabled && !pressed ? 5 : 0
        label
            .font(FeelTypography.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, 16).padding(.vertical, 4)
            .foregroundStyle(enabled ? foreground : FeelTheme.secondary)
            .background(enabled ? fill : FeelTheme.inset)
            .overlay(Rectangle().strokeBorder(enabled ? FeelTheme.ink : FeelTheme.secondary, lineWidth: FeelTheme.borderWidth))
            .background(Rectangle().fill(FeelTheme.ink).offset(x: shadow, y: shadow))
            .offset(x: pressed && enabled ? 5 : 0, y: pressed && enabled ? 5 : 0)
            .padding(.trailing, 5).padding(.bottom, 5)
    }
}

struct FeelPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        FeelButtonBody(label: AnyView(configuration.label), fill: FeelTheme.pin, foreground: .black, enabled: isEnabled, pressed: configuration.isPressed)
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
        FeelButtonBody(label: AnyView(configuration.label), fill: FeelTheme.ink, foreground: FeelTheme.paper, enabled: isEnabled, pressed: configuration.isPressed)
    }
}

/// Sections are separated by one thick rule; the title is the only heavy element.
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
        .overlay(alignment: .top) { Rectangle().fill(FeelTheme.ink).frame(height: FeelTheme.borderWidth) }
    }
}
