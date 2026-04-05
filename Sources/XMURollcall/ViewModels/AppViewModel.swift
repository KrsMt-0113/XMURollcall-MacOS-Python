import SwiftUI
import Foundation

/// Navigation destinations for the app.
enum AppScreen: Equatable {
    case start
    case accountSelection
    case addAccount
    case monitor(Account)

    static func == (lhs: AppScreen, rhs: AppScreen) -> Bool {
        switch (lhs, rhs) {
        case (.start, .start): return true
        case (.accountSelection, .accountSelection): return true
        case (.addAccount, .addAccount): return true
        case (.monitor(let a), .monitor(let b)): return a.id == b.id
        default: return false
        }
    }
}

/// Root view model managing navigation and shared app state.
@MainActor
@Observable
final class AppViewModel {
    var currentScreen: AppScreen = .start
    var accounts: [Account] = []

    private let bridge = PythonBridge.shared

    init() {}

    /// Load accounts from persistent config on launch.
    func loadAccounts() {
        Task {
            let loaded = await bridge.loadAccounts()
            self.accounts = loaded
        }
    }

    /// Navigate to a screen with animation.
    func navigate(to screen: AppScreen) {
        withAnimation(.spring(duration: 0.6)) {
            currentScreen = screen
        }
    }

    /// Called when a new account is saved and verified.
    func addAccount(_ account: Account) {
        accounts.append(account)
    }

    /// Delete an account.
    func deleteAccount(_ account: Account) {
        Task {
            try? await bridge.deleteAccount(accountID: account.id)
            accounts.removeAll { $0.id == account.id }
        }
    }

    /// Select an account and begin monitoring.
    func selectAccount(_ account: Account) {
        navigate(to: .monitor(account))
    }
}
