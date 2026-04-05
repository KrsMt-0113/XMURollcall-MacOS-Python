import SwiftUI
import Foundation

/// State for the verify/save button in the Add Account view.
enum VerifyState: Equatable {
    case idle
    case verifying
    case success(cookiesJSON: String, displayName: String)
    case failed
}

/// View model for the Add Account flow.
@MainActor
@Observable
final class AccountViewModel {
    // Form fields
    var nickname: String = ""
    var username: String = ""
    var password: String = ""
    var selectedColorHex: String = Account.presetColors[0].hex

    // Verify state
    var verifyState: VerifyState = .idle

    // Shake animation trigger
    var shakeAttempts: Int = 0

    private let bridge = PythonBridge.shared

    /// Reset form to initial state.
    func reset() {
        nickname = ""
        username = ""
        password = ""
        selectedColorHex = Account.presetColors[0].hex
        verifyState = .idle
        shakeAttempts = 0
    }

    /// Whether the form has enough data to attempt verification.
    var canVerify: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The text shown on the action button.
    var buttonText: String {
        switch verifyState {
        case .idle:       return "verify"
        case .verifying:  return ""  // shows spinner
        case .success:    return "save"
        case .failed:     return "retry"
        }
    }

    /// The tint color for the action button.
    var buttonColor: Color {
        switch verifyState {
        case .idle:       return .blue
        case .verifying:  return .blue
        case .success:    return .green
        case .failed:     return .red
        }
    }

    /// Verify credentials by logging in via Python bridge.
    func verify() {
        guard canVerify else { return }
        verifyState = .verifying

        Task {
            do {
                let result = try await bridge.login(username: username, password: password)
                if result.success {
                    verifyState = .success(
                        cookiesJSON: result.cookies,
                        displayName: result.name
                    )
                } else {
                    verifyState = .failed
                    triggerShake()
                }
            } catch {
                verifyState = .failed
                triggerShake()
            }
        }
    }

    /// Save the verified account to config and return the Account model.
    func save() async -> Account? {
        guard case .success(let cookiesJSON, let displayName) = verifyState else { return nil }

        let finalNickname = nickname.isEmpty ? (displayName.isEmpty ? username : displayName) : nickname

        do {
            let accountID = try await bridge.saveAccount(
                nickname: finalNickname,
                username: username,
                password: password,
                colorHex: selectedColorHex
            )

            // Also cache cookies
            await bridge.saveCookies(accountID: accountID, cookiesJSON: cookiesJSON)

            return Account(
                id: accountID,
                nickname: finalNickname,
                username: username,
                password: password,
                colorHex: selectedColorHex,
                cookiesJSON: cookiesJSON,
                displayName: displayName
            )
        } catch {
            return nil
        }
    }

    /// Trigger shake animation on failure.
    private func triggerShake() {
        withAnimation(.default) {
            shakeAttempts += 1
        }
    }
}
