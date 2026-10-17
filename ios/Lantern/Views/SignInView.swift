import SwiftUI
import UIKit

/// Email and password sign-in or account creation built for VoiceOver: labelled fields,
/// Password AutoFill (a saved login fills with Face ID; a new account can take a suggested
/// strong password), Return moves to the next step, no time limit or CAPTCHA, and every
/// result is spoken.
struct SignInView: View {
    @ObservedObject var auth: AuthModel
    @State private var mode = Mode.signIn
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @FocusState private var focusedField: Field?
    @AccessibilityFocusState private var messageFocused: Bool

    private enum Field { case email, password }
    private enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign in", createAccount = "Create account"
        var id: String { rawValue }
    }

    var body: some View {
        // The phone is held in landscape, so two columns keep the button on screen without scrolling.
        // The scroll view only matters for very large text sizes.
        ScrollView {
            HStack(alignment: .top, spacing: 32) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(mode == .signIn ? "Sign in to FEEL" : "Create a FEEL account")
                        .font(FeelTypography.title2)
                        .accessibilityAddTraits(.isHeader)
                    Picker("Account", selection: Binding(get: { mode }, set: { mode = $0; auth.clearMessages() })) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(auth.state == .signingIn)
                    .accessibilityIdentifier("authMode")
                    Text(mode == .signIn ? "Use the email and password for your FEEL account."
                                         : "Choose an email and a password of at least 6 characters.")
                        .foregroundStyle(FeelTheme.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 12) {
                    field("Email") {
                        TextField("Email", text: $email)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .focused($focusedField, equals: .email)
                            .onSubmit { focusedField = .password }
                            .accessibilityIdentifier("signInEmail")
                    }
                    field("Password") {
                        HStack {
                            Group {
                                if showPassword { TextField("Password", text: $password) }
                                else { SecureField("Password", text: $password) }
                            }
                            .textContentType(mode == .signIn ? .password : .newPassword)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .focused($focusedField, equals: .password)
                            .onSubmit(submit)
                            .accessibilityIdentifier("signInPassword")
                            Button { showPassword.toggle() } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                            .accessibilityIdentifier("showPassword")
                        }
                    }

                    if let message = auth.errorMessage {
                        banner(message, systemImage: "exclamationmark.triangle.fill").accessibilityIdentifier("signInError")
                    } else if let notice = auth.notice {
                        banner(notice, systemImage: "envelope.fill").accessibilityIdentifier("signInNotice")
                    }

                    Button(action: submit) {
                        HStack(spacing: 10) {
                            if auth.state == .signingIn { ProgressView().accessibilityHidden(true) }
                            Text(buttonTitle)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(FeelPrimaryButtonStyle())
                    .disabled(!canSubmit)
                    .accessibilityIdentifier("signInButton")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: 820)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(FeelTheme.ink)
        .background(FeelTheme.canvas.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .font(FeelTypography.body)
        .tint(FeelTheme.accent)
        .onChange(of: auth.errorMessage) { speak($0) }
        .onChange(of: auth.notice) { speak($0) }
    }

    private var buttonTitle: String {
        switch (mode, auth.state == .signingIn) {
        case (.signIn, false): return "Sign in"
        case (.signIn, true): return "Signing in…"
        case (.createAccount, false): return "Create account"
        case (.createAccount, true): return "Creating account…"
        }
    }

    private var canSubmit: Bool {
        auth.state == .signedOut && !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        focusedField = nil
        if mode == .signIn {
            UIAccessibility.post(notification: .announcement, argument: "Signing in.")
            auth.signIn(email: email, password: password)
        } else {
            UIAccessibility.post(notification: .announcement, argument: "Creating account.")
            // Confirmation is done from the email; the next step here is signing in.
            auth.signUp(email: email, password: password) { mode = .signIn }
        }
    }

    private func speak(_ message: String?) {
        guard let message else { return }
        UIAccessibility.post(notification: .announcement, argument: message)
        messageFocused = true
    }

    private func banner(_ message: String, systemImage: String) -> some View {
        Label(message, systemImage: systemImage)
            .foregroundStyle(FeelTheme.ink)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FeelTheme.inset, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityFocused($messageFocused)
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(FeelTypography.label).accessibilityHidden(true)
            content()
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .background(FeelTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(FeelTheme.border, lineWidth: 1))
        }
    }
}
