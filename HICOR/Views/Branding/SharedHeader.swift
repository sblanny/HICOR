import SwiftUI

struct SharedHeader: View {
    var onBack: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44, alignment: .leading)
                }
                .accessibilityLabel("Back")
            }
            CLEARLogo(size: 28)
            Text("CLEAR")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            Spacer()
            Button {
                // Phase 7: History, Change Location/Date, About
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44, alignment: .center)
            }
            .accessibilityLabel("Menu")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.background)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.5)
        }
    }
}
