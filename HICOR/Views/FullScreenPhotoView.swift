import SwiftUI

struct FullScreenPhotoView: View {
    let imageData: Data
    let index: Int
    let total: Int
    var onDismiss: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var accumulatedScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let ui = UIImage(data: imageData) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = min(max(accumulatedScale * value, 1.0), 5.0)
                            }
                            .onEnded { _ in
                                accumulatedScale = scale
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation {
                            scale = 1.0
                            accumulatedScale = 1.0
                        }
                    }
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white, .black.opacity(0.5))
                    }
                    .padding()
                }
                Spacer()
                Text("\(index + 1) of \(total)")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.bottom, 24)
            }
        }
    }
}
