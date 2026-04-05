import SwiftUI

/// Grid view showing saved accounts as colored circles, plus an add button.
struct AccountSelectionView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @Namespace private var animationNamespace

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
    ]

    var body: some View {
        GlassEffectContainer {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    Text("选择账号")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .padding(.top, 24)

                    // Account grid
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(appViewModel.accounts) { account in
                            AccountCircleButton(
                                account: account,
                                namespace: animationNamespace
                            ) {
                                appViewModel.selectAccount(account)
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    appViewModel.deleteAccount(account)
                                } label: {
                                    Label("删除账号", systemImage: "trash")
                                }
                            }
                        }

                        // Add account button
                        AddAccountCircleButton(namespace: animationNamespace) {
                            appViewModel.navigate(to: .addAccount)
                        }
                    }
                    .padding(.horizontal, 24)

                    Spacer(minLength: 24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Account Circle Button

struct AccountCircleButton: View {
    let account: Account
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: action) {
                Text(String(account.nickname.prefix(1)).uppercased())
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(account.color).interactive(), in: .circle)
            .matchedGeometryEffect(id: account.id, in: namespace)

            Text(account.nickname)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Add Account Circle Button

struct AddAccountCircleButton: View {
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: action) {
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(.gray).interactive(), in: .circle)
            .matchedGeometryEffect(id: "add_account_button", in: namespace)

            Text("新增账号")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
