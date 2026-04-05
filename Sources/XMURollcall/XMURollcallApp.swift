import SwiftUI

/// Main application entry point.
@main
struct XMURollcallApp: App {
    @State private var appViewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appViewModel)
                .frame(minWidth: 400, minHeight: 500)
                .onAppear {
                    appViewModel.loadAccounts()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 420, height: 540)
    }
}

/// Root content view that switches between screens based on navigation state.
struct ContentView: View {
    @Environment(AppViewModel.self) private var appViewModel

    var body: some View {
        ZStack {
            switch appViewModel.currentScreen {
            case .start:
                StartView()
                    .transition(.opacity)

            case .accountSelection:
                AccountSelectionView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

            case .addAccount:
                AddAccountView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

            case .monitor(let account):
                MonitorView(account: account)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .animation(.spring(duration: 0.5), value: appViewModel.currentScreen)
    }
}
