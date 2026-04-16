import SwiftUI

struct ResultPlaceholderView: View {
    let patientNumber: String
    let photoCount: Int

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Analysis coming in Phase 4")
                .font(.title2.bold())
            VStack(spacing: 6) {
                Text("Patient #\(patientNumber)")
                Text("\(photoCount) photo\(photoCount == 1 ? "" : "s") captured")
                    .foregroundStyle(.secondary)
            }
            .font(.body)

            Spacer()

            Button {
                NotificationCenter.default.post(name: .hicorReturnToRoot, object: nil)
            } label: {
                Text("Save & Return")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
        }
        .padding()
        .navigationBarBackButtonHidden(true)
    }
}

extension Notification.Name {
    static let hicorReturnToRoot = Notification.Name("hicor.returnToRoot")
}
