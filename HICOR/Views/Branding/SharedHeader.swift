import SwiftUI

struct SharedHeader: View {
    var onBack: (() -> Void)? = nil
    var onShowHistory: (() -> Void)? = nil
    var onChangeLocation: (() -> Void)? = nil
    var onShowAbout: (() -> Void)? = nil

    @State private var showMenu = false
    @State private var pendingAction: (() -> Void)? = nil

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
                showMenu = true
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
        .sheet(isPresented: $showMenu, onDismiss: {
            let action = pendingAction
            pendingAction = nil
            action?()
        }) {
            HamburgerMenu(
                isPresented: $showMenu,
                pendingAction: $pendingAction,
                onShowHistory: onShowHistory,
                onChangeLocation: onChangeLocation,
                onShowAbout: onShowAbout
            )
        }
    }
}
