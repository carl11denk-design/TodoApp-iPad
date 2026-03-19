import WidgetKit
import SwiftUI

struct StundenplanEntry: TimelineEntry {
    let date: Date
    let events: [CalendarEvent]
}

struct StundenplanTimelineProvider: TimelineProvider {
    typealias Entry = StundenplanEntry

    func placeholder(in context: Context) -> StundenplanEntry {
        StundenplanEntry(date: .now, events: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (StundenplanEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StundenplanEntry>) -> Void) {
        let entry = makeEntry()

        // Refresh at the start of the next event, or in 30 min
        let now = Date()
        let nextEventStart = entry.events
            .first(where: { $0.startDate > now })?
            .startDate

        let halfHour = Calendar.current.date(byAdding: .minute, value: 30, to: now)!
        let nextRefresh: Date
        if let nextStart = nextEventStart {
            nextRefresh = min(nextStart, halfHour)
        } else {
            nextRefresh = halfHour
        }

        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func makeEntry() -> StundenplanEntry {
        let allEvents = SharedDataReader.loadCalendarEvents()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let todayEvents = allEvents
            .filter { cal.isDate($0.startDate, inSameDayAs: today) }
            .sorted { $0.startDate < $1.startDate }

        return StundenplanEntry(date: .now, events: todayEvents)
    }
}

struct StundenplanWidget: Widget {
    let kind = "StundenplanWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: StundenplanTimelineProvider()
        ) { entry in
            StundenplanWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Stundenplan")
        .description("Zeigt deinen heutigen Stundenplan an.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
