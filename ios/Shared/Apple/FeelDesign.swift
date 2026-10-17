import SwiftUI
import UIKit

/// Shared native identity: blue actions, semantic system surfaces, 16pt panels,
/// 12pt controls. System colors preserve contrast in light and dark appearances.
enum FeelTheme {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.48, green: 0.69, blue: 1, alpha: 1)
            : UIColor(red: 0.12, green: 0.31, blue: 0.66, alpha: 1)
    })
    static let onAccent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.06, green: 0.10, blue: 0.18, alpha: 1)
            : UIColor(red: 0.98, green: 0.99, blue: 1, alpha: 1)
    })
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let border = Color(uiColor: .separator)
}

struct FeelPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .foregroundStyle(isEnabled ? FeelTheme.onAccent : Color.secondary)
            .background(isEnabled ? FeelTheme.accent : Color(uiColor: .tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct FeelSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .foregroundStyle(isEnabled ? FeelTheme.accent : Color.secondary)
            .background(FeelTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(FeelTheme.border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct FeelStopButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .background(FeelTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isEnabled ? Color.primary : FeelTheme.border, lineWidth: isEnabled ? 2 : 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct FeelSection<Content: View>: View {
    let title: String
    var systemImage: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage).foregroundStyle(FeelTheme.accent).accessibilityHidden(true)
                }
                Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(FeelTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}
