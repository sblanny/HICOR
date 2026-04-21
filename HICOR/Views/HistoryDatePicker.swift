import SwiftUI

struct HistoryDatePicker: View {
    let location: String
    let currentDate: Date
    let availableDates: [Date]
    let patientCounts: [Date: Int]
    let onSelect: (Date) -> Void

    @Environment(\.dismiss) private var dismiss

    private var calendar: Calendar { Calendar.current }

    private var selectedDay: Date {
        calendar.startOfDay(for: currentDate)
    }

    var body: some View {
        NavigationStack {
            List(availableDates, id: \.self) { date in
                Button {
                    onSelect(date)
                    dismiss()
                } label: {
                    row(for: date)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            }
            .listStyle(.plain)
            .navigationTitle("Select Date")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func row(for date: Date) -> some View {
        let isToday = calendar.isDateInToday(date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDay)
        let count = patientCounts[date] ?? 0

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if isToday {
                        Text("Today")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                    Text(date, format: .dateTime.month().day().year())
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                }
                Text(date, format: .dateTime.weekday(.wide))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(countLabel(count))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
    }

    private func countLabel(_ count: Int) -> String {
        count == 1 ? "1 patient" : "\(count) patients"
    }
}

#Preview {
    struct PreviewHost: View {
        @State private var presented = true
        @State private var current = Date()
        var body: some View {
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
            let lastMonth = cal.date(byAdding: .day, value: -30, to: today)!
            return Color.clear.sheet(isPresented: $presented) {
                HistoryDatePicker(
                    location: "San Luis",
                    currentDate: current,
                    availableDates: [today, yesterday, lastMonth],
                    patientCounts: [today: 0, yesterday: 12, lastMonth: 9],
                    onSelect: { current = $0 }
                )
            }
        }
    }
    return PreviewHost()
}
