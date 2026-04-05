import SwiftUI

/// Shake effect modifier for failed verification animation.
struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 10
    var shakesPerUnit = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(
                translationX: amount * sin(animatableData * .pi * CGFloat(shakesPerUnit)),
                y: 0
            )
        )
    }
}

/// View for adding a new account with color picker, text fields, and verify/save flow.
struct AddAccountView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @State private var viewModel = AccountViewModel()
    @Namespace private var animationNamespace

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 20) {
                // Header
                Text("新增账号")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .padding(.top, 24)

                // Color picker
                colorPickerSection

                // Text fields
                textFieldsSection

                Spacer()

                // Verify / Save button
                actionButton
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Color Picker

    private var colorPickerSection: some View {
        HStack(spacing: 12) {
            ForEach(Account.presetColors, id: \.hex) { preset in
                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        viewModel.selectedColorHex = preset.hex
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(hex: preset.hex))
                            .frame(width: 32, height: 32)

                        if viewModel.selectedColorHex == preset.hex {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Text Fields

    private var textFieldsSection: some View {
        VStack(spacing: 14) {
            GlassTextField(
                placeholder: "昵称 (Nickname)",
                text: $viewModel.nickname,
                icon: "person.fill"
            )

            GlassTextField(
                placeholder: "账号 (Student ID)",
                text: $viewModel.username,
                icon: "number"
            )

            GlassSecureField(
                placeholder: "密码 (Password)",
                text: $viewModel.password,
                icon: "lock.fill"
            )
        }
    }

    // MARK: - Action Button

    private var actionButton: some View {
        Button {
            handleButtonTap()
        } label: {
            HStack(spacing: 8) {
                if viewModel.verifyState == .verifying {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Text(viewModel.buttonText)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(viewModel.buttonColor).interactive(), in: .capsule)
        .modifier(ShakeEffect(animatableData: CGFloat(viewModel.shakeAttempts)))
        .disabled(viewModel.verifyState == .verifying || (!viewModel.canVerify && viewModel.verifyState == .idle))
        .opacity((!viewModel.canVerify && viewModel.verifyState == .idle) ? 0.5 : 1.0)
    }

    // MARK: - Actions

    private func handleButtonTap() {
        switch viewModel.verifyState {
        case .idle, .failed:
            viewModel.verify()
        case .success:
            Task {
                if let account = await viewModel.save() {
                    appViewModel.addAccount(account)
                    viewModel.reset()
                    appViewModel.navigate(to: .accountSelection)
                }
            }
        case .verifying:
            break
        }
    }
}

// MARK: - Glass Text Field

struct GlassTextField: View {
    let placeholder: String
    @Binding var text: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        }
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Glass Secure Field

struct GlassSecureField: View {
    let placeholder: String
    @Binding var text: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            SecureField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        }
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 12))
    }
}
