import SwiftUI

struct HamburgerMenu: View {
    @Binding var isPresented: Bool
    @Binding var pendingAction: (() -> Void)?
    var onShowHistory: (() -> Void)?
    var onChangeLocation: (() -> Void)?
    var onShowAbout: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            row(icon: "clock.arrow.circlepath", title: "History", action: onShowHistory)
            Divider().padding(.leading, 56)
            row(icon: "mappin.and.ellipse", title: "Change Location / Date", action: onChangeLocation)
            Divider().padding(.leading, 56)
            row(icon: "info.circle", title: "About", action: onShowAbout)
            Spacer()
        }
        .padding(.top, 8)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func row(icon: String, title: String, action: (() -> Void)?) -> some View {
        Button {
            pendingAction = action
            isPresented = false
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 40, alignment: .center)
                    .foregroundStyle(.primary)
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    struct PreviewHost: View {
        @State private var presented = true
        @State private var pending: (() -> Void)? = nil
        var body: some View {
            Color.clear.sheet(isPresented: $presented) {
                HamburgerMenu(
                    isPresented: $presented,
                    pendingAction: $pending,
                    onShowHistory: { print("history") },
                    onChangeLocation: { print("change") },
                    onShowAbout: { print("about") }
                )
            }
        }
    }
    return PreviewHost()
}
