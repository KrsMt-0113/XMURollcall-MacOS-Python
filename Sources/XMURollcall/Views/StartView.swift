import SwiftUI

/// The initial launch screen with a large red circular "start" button.
struct StartView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @State private var isVisible = true

    var body: some View {
        GlassEffectContainer {
            VStack {
                Spacer()

                if isVisible {
                    Button {
                        withAnimation(.spring(duration: 0.6)) {
                            isVisible = false
                        }
                        // Navigate after a short delay to let the fade finish
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            appViewModel.navigate(to: .accountSelection)
                        }
                    } label: {
                        Text("start")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 140, height: 140)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(.red).interactive(), in: .circle)
                    .transition(.opacity.combined(with: .scale))
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
