import SwiftUI
import WidgetKit

struct StundenplanWidgetEntryView: View {
    let entry: StundenplanEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    private var now: Date { entry.date }

    var body: some View {
        Group {
            switch family {
            case .systemSmall:  smallView
            case .systemMedium: mediumView
            case .systemLarge:  largeView
            default:            mediumView
            }
        }
        .widgetURL(URL(string: "todoapp://stundenplan"))
    }

    // MARK: - Small

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "calendar")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Text("Heute")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if entry.events.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "sun.max.fill")
                            .font(.title2)
                            .foregroundStyle(.orange)
                        Text("Frei!")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            } else if let current = currentOrNextEvent() {
                Spacer(minLength: 0)
                eventLabel(current)
                Spacer(minLength: 0)
                Text("\(entry.events.count) Veranstaltung\(entry.events.count == 1 ? "" : "en")")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Medium

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 6) {
            dayHeader
            if entry.events.isEmpty {
                emptyDay
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(entry.events.prefix(4)) { event in
                        eventRow(event)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Large

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 6) {
            dayHeader
            if entry.events.isEmpty {
                emptyDay
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(entry.events.prefix(9)) { event in
                        eventRow(event)
                    }
                    if entry.events.count > 9 {
                        Text("+ \(entry.events.count - 9) weitere")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Components

    private var dayHeader: some View {
        HStack {
            Image(systemName: "calendar")
                .font(.caption)
                .foregroundStyle(.blue)
            Text(todayString())
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(entry.events.count)")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(.blue)
        }
    }

    private var emptyDay: some View {
        HStack {
            Spacer()
            VStack(spacing: 4) {
                Image(systemName: "sun.max.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text("Heute frei!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func eventLabel(_ event: CalendarEvent) -> some View {
        let color = widgetColorForString(event.summary)
        let isNow = event.startDate <= now && event.endDate > now

        return VStack(alignment: .leading, spacing: 2) {
            if isNow {
                Text("JETZT")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(color)
            }
            Text(event.summary)
                .font(.caption.bold())
                .lineLimit(2)
            Text(timeRange(event))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func eventRow(_ event: CalendarEvent) -> some View {
        let color = widgetColorForString(event.summary)
        let isNow = event.startDate <= now && event.endDate > now
        let isPast = event.endDate <= now

        return HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 3)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.summary)
                    .font(.caption)
                    .fontWeight(isNow ? .bold : .regular)
                    .lineLimit(1)
                    .opacity(isPast ? 0.5 : 1)

                HStack(spacing: 4) {
                    Text(timeRange(event))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)

                    if isNow {
                        Text("Jetzt")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(color)
                    }
                }
            }

            Spacer(minLength: 0)

            if let loc = event.location, !loc.isEmpty {
                Text(loc)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Helpers

    private func timeRange(_ event: CalendarEvent) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return "\(fmt.string(from: event.startDate)) – \(fmt.string(from: event.endDate))"
    }

    private func todayString() -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "de_DE")
        fmt.dateFormat = "EEEE, d. MMM"
        return fmt.string(from: Date())
    }

    private func currentOrNextEvent() -> CalendarEvent? {
        // Current event
        if let current = entry.events.first(where: { $0.startDate <= now && $0.endDate > now }) {
            return current
        }
        // Next upcoming
        return entry.events.first(where: { $0.startDate > now })
    }

    /// Simplified color function for widgets (no colorScheme dependency needed inline).
    private func widgetColorForString(_ str: String) -> Color {
        var hash = 0
        for c in str.unicodeScalars { hash = Int(c.value) &+ ((hash &<< 5) &- hash) }
        let hue = Double(abs(hash) % 360) / 360.0
        let sat = colorScheme == .dark ? 0.60 : 0.78
        let bri = colorScheme == .dark ? 0.88 : 0.52
        return Color(hue: hue, saturation: sat, brightness: bri)
    }
}
