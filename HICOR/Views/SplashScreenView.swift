import SwiftUI

struct SplashScreenView: View {
    var onDismiss: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 20) {
                CLEARLogo(size: 200)
                Text("CLEAR")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                Text("Christ's Love Expressed through Restored Sight")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer().frame(height: 40)
                Text("Presented by Highlands Church")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .opacity(appeared ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5)) { appeared = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                onDismiss()
            }
        }
    }
}
