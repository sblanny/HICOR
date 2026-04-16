import SwiftUI

struct SessionSetupView: View {
    let sessionContext: SessionContext
    @State private var date: Date = Date()
    @State private var location: String = ""
    @State private var navigate = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            logoArea

            VStack(spacing: 4) {
                Text("HICOR")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                Text("Highlands Church Optical Refraction")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Form {
                Section {
                    DatePicker("Session date", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.compact)
                    TextField("e.g. San Quintin, Baja California", text: $location)
                }
            }
            .scrollContentBackground(.hidden)
            .frame(maxHeight: 200)

            Button {
                sessionContext.date = date
                sessionContext.location = location
                let settings = SessionSettings(lastDate: date, lastLocation: location)
                settings.save()
                navigate = true
            } label: {
                Text("Start Session")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .disabled(location.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.horizontal)

            Spacer()
        }
        .onAppear {
            let settings = SessionSettings.load()
            date = settings.lastDate
            location = settings.lastLocation
        }
        .navigationDestination(isPresented: $navigate) {
            PatientEntryView(sessionContext: sessionContext)
        }
    }

    private var logoArea: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.306, green: 0.769, blue: 0.663), // Highlands teal #4EC4A8
                            Color(red: 0.510, green: 0.788, blue: 0.494)  // Highlands sage #82C97E
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 120, height: 120)
            Image(systemName: "eye.fill")
                .font(.system(size: 48))
                .foregroundStyle(.white)
        }
    }
}
