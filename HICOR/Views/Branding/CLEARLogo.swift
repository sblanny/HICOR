import SwiftUI

struct CLEARLogo: View {
    var size: CGFloat = 120
    var fillCanvas: Bool = false

    private var gradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.306, green: 0.769, blue: 0.663), // Highlands teal #4EC4A8
                Color(red: 0.510, green: 0.788, blue: 0.494)  // Highlands sage #82C97E
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            if fillCanvas {
                Rectangle().fill(gradient)
            } else {
                Circle().fill(gradient)
            }
            Image(systemName: "eye.fill")
                .font(.system(size: size * 0.4))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}
