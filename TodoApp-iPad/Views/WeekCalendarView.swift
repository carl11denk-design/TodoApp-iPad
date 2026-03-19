import SwiftUI
import WidgetKit

// MARK: - SubjectStats (reused from iPhone)

private struct SubjectStats {
    let totalHours: Double
    let doneHours: Double
    let remainingHours: Double
    let totalSessions: Int
    let doneSessions: Int
    let upcomingSessions: Int
    let inProgressEvent: CalendarEvent?
    let upcomingEventDates: [CalendarEvent]

    static func compute(for subject: String, in allEvents: [CalendarEvent], now: Date) -> SubjectStats {
        let matching = allEvents.filter { $0.summary == subject }

        var totalSecs  = 0.0
        var doneSecs   = 0.0
        var remainSecs = 0.0
        var totalCount = 0
        var doneCount  = 0
        var upcoming: [CalendarEvent] = []
        var inProgress: CalendarEvent? = nil

        for e in matching {
            let dur = e.endDate.timeIntervalSince(e.startDate)
            totalSecs  += dur
            totalCount += 1
            if e.endDate < now {
                doneSecs  += dur
                doneCount += 1
            } else if e.startDate > now {
                remainSecs += dur
                upcoming.append(e)
            } else {
                inProgress = e
            }
        }

        return SubjectStats(
            totalHours:        totalSecs  / 3600,
            doneHours:         doneSecs   / 3600,
            remainingHours:    remainSecs / 3600,
            totalSessions:     totalCount,
            doneSessions:      doneCount,
            upcomingSessions:  upcoming.count,
            inProgressEvent:   inProgress,
            upcomingEventDates: Array(upcoming.sorted { $0.startDate < $1.startDate }.prefix(5))
        )
    }

    func minutesRemaining(now: Date) -> Int? {
        guard let e = inProgressEvent else { return nil }
        let secs = e.endDate.timeIntervalSince(now)
        return secs > 0 ? Int(secs / 60) : 0
    }
}

// MARK: - EventDetailSheet

private struct EventDetailSheet: View {
    let event: CalendarEvent
    let allEvents: [CalendarEvent]
    let colorScheme: ColorScheme

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now    = context.date
            let stats  = SubjectStats.compute(for: event.summary, in: allEvents, now: now)
            let accent = colorForString(event.summary, colorScheme: colorScheme)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    sheetHandle
                    sheetHeader(accent: accent)
                    progressRing(stats: stats, accent: accent)
                    statCards(stats: stats)
                    if stats.inProgressEvent != nil {
                        inProgressBadge(stats: stats, now: now, accent: accent)
                    }
                    if !stats.upcomingEventDates.isEmpty {
                        upcomingList(stats: stats)
                    }
                    Spacer(minLength: 32)
                }
                .padding(24)
            }
            .background(.ultraThinMaterial)
        }
    }

    private var sheetHandle: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(Color(.systemGray4))
            .frame(width: 36, height: 5)
            .padding(.top, 8)
    }

    private func sheetHeader(accent: Color) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(accent)
                .frame(width: 14, height: 14)
                .shadow(color: accent.opacity(0.5), radius: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.summary)
                    .font(.title3.bold())
                if let loc = event.location, !loc.isEmpty {
                    Label(loc, systemImage: "mappin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func progressRing(stats: SubjectStats, accent: Color) -> some View {
        let fraction = stats.totalHours > 0
            ? min(stats.doneHours / stats.totalHours, 1.0)
            : 0.0

        return ZStack {
            Circle()
                .stroke(accent.opacity(0.15), lineWidth: 14)
                .frame(width: 130, height: 130)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .frame(width: 130, height: 130)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: fraction)
            VStack(spacing: 2) {
                Text("\(Int(fraction * 100))%")
                    .font(.title2.bold())
                Text("absolviert")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func statCards(stats: SubjectStats) -> some View {
        HStack(spacing: 12) {
            statCard(icon: "clock",            title: "Gesamt",      value: formatHours(stats.totalHours),     sub: "\(stats.totalSessions) Einh.")
            statCard(icon: "checkmark.circle", title: "Absolviert",  value: formatHours(stats.doneHours),      sub: "\(stats.doneSessions) Einh.")
            statCard(icon: "hourglass",        title: "Verbleibend", value: formatHours(stats.remainingHours), sub: "\(stats.upcomingSessions) Einh.")
        }
    }

    private func statCard(icon: String, title: String, value: String, sub: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.headline, design: .rounded).monospacedDigit())
            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            Text(sub)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.systemGray6).opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func inProgressBadge(stats: SubjectStats, now: Date, accent: Color) -> some View {
        if let remaining = stats.minutesRemaining(now: now) {
            HStack(spacing: 12) {
                PulsingDot(color: accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Läuft gerade")
                        .font(.subheadline.bold())
                        .foregroundStyle(accent)
                    Text(remaining == 0
                         ? "Endet gleich"
                         : "Noch \(remaining) Minute\(remaining == 1 ? "" : "n")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.25), lineWidth: 1))
        }
    }

    private func upcomingList(stats: SubjectStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Nächste Termine", systemImage: "calendar")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(stats.upcomingEventDates) { e in
                upcomingRow(e)
            }
        }
    }

    private func upcomingRow(_ e: CalendarEvent) -> some View {
        let dayFmt = DateFormatter()
        dayFmt.locale    = Locale(identifier: "de_DE")
        dayFmt.dateFormat = "EE, dd.MM."
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(dayFmt.string(from: e.startDate))
                    .font(.caption.weight(.semibold))
                Text("\(timeFmt.string(from: e.startDate)) – \(timeFmt.string(from: e.endDate))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let loc = e.location, !loc.isEmpty {
                Text(loc)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6).opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Pulsing dot

private struct PulsingDot: View {
    let color: Color
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 20, height: 20)
                .scaleEffect(pulsing ? 1.5 : 1.0)
                .opacity(pulsing ? 0 : 0.8)
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
    }
}

// MARK: - WeekCalendarView (iPad Week View)

struct WeekCalendarView: View {
    var service: ICalService
    private static let sharedDefaults = UserDefaults(suiteName: PersistenceManager.appGroupID)
    @AppStorage("todoapp_ical_url", store: WeekCalendarView.sharedDefaults) private var icalURL = ""
    @State private var weekOffset = 0
    @State private var selectedEvent: CalendarEvent?
    @Environment(\.colorScheme) private var colorScheme

    // Layout constants
    private let hourStart = 7
    private let hourEnd   = 21
    private let rowH: CGFloat     = 60
    private let timeColW: CGFloat = 56

    private var cal: Calendar { Calendar.current }

    private var today: Date {
        cal.startOfDay(for: Date())
    }

    private var mondayOfCurrentWeek: Date {
        let baseMonday = mondayOfWeekContaining(today)
        return cal.date(byAdding: .weekOfYear, value: weekOffset, to: baseMonday) ?? baseMonday
    }

    private var weekDays: [Date] {
        (0..<7).map { cal.date(byAdding: .day, value: $0, to: mondayOfCurrentWeek)! }
    }

    private var isCurrentWeek: Bool { weekOffset == 0 }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            compactHeader
            Divider()

            Group {
                if icalURL.isEmpty {
                    noCalendarState
                } else if service.isLoading {
                    loadingState
                } else if let err = service.errorMessage {
                    errorState(err)
                } else if service.events.isEmpty {
                    emptyWeekState
                } else {
                    weekGrid
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .toolbar { toolbarItems }
        .task {
            if !icalURL.isEmpty {
                await service.fetch(url: icalURL)
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15 * 60))
                if !icalURL.isEmpty {
                    await service.fetch(url: icalURL)
                }
            }
        }
        .sheet(item: $selectedEvent) { event in
            EventDetailSheet(
                event: event,
                allEvents: service.events,
                colorScheme: colorScheme
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
            .frame(minWidth: 400, idealWidth: 500)
        }
    }

    // MARK: - Week navigation header

    // MARK: - Compact header (nav + day headers combined)

    private var compactHeader: some View {
        let shortDays = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

        return VStack(spacing: 0) {
            // Row 0: Title
            Text("Stundenplan")
                .font(.system(size: 28, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
                .padding(.bottom, 4)

            // Row 1: Week switcher
            HStack {
                Spacer()

                Button {
                    withAnimation(.spring(duration: 0.25)) { weekOffset -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text(weekRangeString())
                    .font(.system(size: 15, weight: .semibold))
                    .frame(minWidth: 160)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.15), value: weekOffset)

                Button {
                    withAnimation(.spring(duration: 0.25)) { weekOffset += 1 }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if !isCurrentWeek {
                    Button {
                        withAnimation(.spring(duration: 0.3)) { weekOffset = 0 }
                    } label: {
                        Text("Heute")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(.vertical, 8)

            // Row 2: Day columns (aligned with grid)
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: timeColW, height: 1)

                ForEach(0..<7, id: \.self) { i in
                    let day       = weekDays[i]
                    let isToday   = cal.isDateInToday(day)
                    let hasEvents = !eventsForDay(day).isEmpty

                    VStack(spacing: 2) {
                        Text(shortDays[i])
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isToday ? .blue : .secondary)

                        ZStack {
                            Circle()
                                .fill(isToday ? Color.blue : Color.clear)
                                .frame(width: 28, height: 28)

                            Text("\(cal.component(.day, from: day))")
                                .font(.system(size: 13, weight: isToday ? .bold : .regular))
                                .foregroundStyle(isToday ? .white : .primary)
                        }

                        Circle()
                            .fill(hasEvents ? Color.blue.opacity(0.6) : Color.clear)
                            .frame(width: 4, height: 4)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 4)
        }
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Week grid

    private var weekGrid: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    // Hour grid lines
                    VStack(spacing: 0) {
                        ForEach(hourStart..<hourEnd, id: \.self) { hour in
                            hourRow(hour: hour).id(hour)
                        }
                    }

                    // Day column separators + events
                    GeometryReader { geo in
                        let dayWidth = (geo.size.width - timeColW) / 7

                        // Vertical separators
                        ForEach(0..<7, id: \.self) { i in
                            Rectangle()
                                .fill(Color(.separator).opacity(0.3))
                                .frame(width: 0.5)
                                .offset(x: timeColW + dayWidth * CGFloat(i))
                        }

                        // Events per day
                        ForEach(0..<7, id: \.self) { dayIndex in
                            let day       = weekDays[dayIndex]
                            let dayEvents = eventsForDay(day)
                            let layoutEvs = computeOverlapLayout(dayEvents)
                            let colX      = timeColW + dayWidth * CGFloat(dayIndex)

                            ForEach(layoutEvs, id: \.event.id) { le in
                                weekEventBlock(
                                    le: le,
                                    dayWidth: dayWidth,
                                    offsetX: colX
                                )
                            }
                        }

                        // Current time line (if current week)
                        if isCurrentWeek {
                            currentTimeLine(totalWidth: geo.size.width)
                        }
                    }
                    .frame(height: CGFloat(hourEnd - hourStart) * rowH)
                }
                .padding(.bottom, 44)
            }
            .onAppear { proxy.scrollTo(8, anchor: .top) }
            .onChange(of: weekOffset) { _, _ in
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(8, anchor: .top) }
            }
        }
    }

    // MARK: - Hour row

    private func hourRow(hour: Int) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(String(format: "%02d:00", hour))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color(.tertiaryLabel))
                .frame(width: timeColW, alignment: .trailing)
                .padding(.trailing, 8)
                .offset(y: -8)

            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color(.separator).opacity(0.55))
                    .frame(height: 0.5)
                Spacer()
                Rectangle()
                    .fill(Color(.separator).opacity(0.2))
                    .frame(height: 0.5)
                Spacer()
            }
        }
        .frame(height: rowH)
    }

    // MARK: - Week event block

    private func weekEventBlock(le: LayoutEvent, dayWidth: CGFloat, offsetX: CGFloat) -> some View {
        let event  = le.event
        let startH = Double(cal.component(.hour, from: event.startDate))
                   + Double(cal.component(.minute, from: event.startDate)) / 60.0
        let endH   = Double(cal.component(.hour, from: event.endDate))
                   + Double(cal.component(.minute, from: event.endDate)) / 60.0

        let cStart = max(startH, Double(hourStart))
        let cEnd   = min(endH,   Double(hourEnd))
        let top    = CGFloat(cStart - Double(hourStart)) * rowH
        let height = max(CGFloat(cEnd - cStart) * rowH - 2, 24)

        let inset: CGFloat   = 2
        let gap: CGFloat     = le.totalColumns > 1 ? 2 : 0
        let slotW = (dayWidth - inset * 2 - gap * CGFloat(le.totalColumns - 1)) / CGFloat(le.totalColumns)
        let x     = offsetX + inset + CGFloat(le.columnIndex) * (slotW + gap)
        let color = colorForString(event.summary, colorScheme: colorScheme)
        let bg    = color.opacity(colorScheme == .dark ? 0.22 : 0.10)

        return VStack(alignment: .leading, spacing: 2) {
            Text(event.summary)
                .font(.system(size: height > 44 ? 11 : 9, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(height > 50 ? 2 : 1)

            if height > 32 {
                Text(timeRange(event))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if height > 52, let loc = event.location, !loc.isEmpty {
                Text(loc)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .frame(width: slotW, height: height, alignment: .topLeading)
        .background(bg, in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: color.opacity(colorScheme == .dark ? 0.08 : 0.12), radius: 3, x: 0, y: 1)
        .offset(x: x, y: top)
        .onTapGesture { selectedEvent = event }
    }

    // MARK: - Current time line

    @ViewBuilder
    private func currentTimeLine(totalWidth: CGFloat) -> some View {
        let now  = Date()
        let nowH = Double(cal.component(.hour, from: now))
                 + Double(cal.component(.minute, from: now)) / 60.0

        if nowH >= Double(hourStart), nowH < Double(hourEnd) {
            let y = CGFloat(nowH - Double(hourStart)) * rowH

            // Find which day column today falls in
            let todayIndex = weekDays.firstIndex { cal.isDate($0, inSameDayAs: now) }

            if let idx = todayIndex {
                let dayWidth = (totalWidth - timeColW) / 7
                let lineX = timeColW + dayWidth * CGFloat(idx)
                let lineW = dayWidth

                Rectangle()
                    .fill(Color.red)
                    .frame(width: lineW, height: 2)
                    .offset(x: lineX, y: y)

                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .offset(x: lineX - 4, y: y - 3)
            }
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView().scaleEffect(1.2)
            Text("Stundenplan wird geladen…")
                .foregroundStyle(.secondary)
        }
    }

    private func errorState(_ error: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 46))
                .foregroundStyle(.orange)
            Text("Fehler beim Laden")
                .font(.title3).fontWeight(.semibold)
            Text(error)
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Erneut versuchen") {
                Task { await service.fetch(url: icalURL) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(icalURL.isEmpty)
        }
    }

    private var noCalendarState: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 52))
                .foregroundStyle(.tertiary)
            Text("Kein iCal-Link konfiguriert")
                .font(.title3).fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Text("Trage deinen Vorlesungsplan-Link\nin den Einstellungen ein.")
                .font(.subheadline).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var emptyWeekState: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar")
                .font(.system(size: 52))
                .foregroundStyle(.tertiary)
            Text("Keine Veranstaltungen")
                .font(.title3).fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Text("Es wurden keine Veranstaltungen\nim Kalender gefunden.")
                .font(.subheadline).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await service.fetch(url: icalURL) }
            } label: {
                if service.isLoading {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(icalURL.isEmpty || service.isLoading)
        }
    }

    // MARK: - Overlap layout

    private struct LayoutEvent {
        let event: CalendarEvent
        let columnIndex: Int
        let totalColumns: Int
    }

    private func computeOverlapLayout(_ events: [CalendarEvent]) -> [LayoutEvent] {
        guard !events.isEmpty else { return [] }
        let sorted = events.sorted { $0.startDate < $1.startDate }
        var result: [LayoutEvent] = []
        var groups: [[CalendarEvent]] = []
        var currentGroup: [CalendarEvent] = []
        var groupEnd: Date = .distantPast

        for event in sorted {
            if event.startDate < groupEnd {
                currentGroup.append(event)
                if event.endDate > groupEnd { groupEnd = event.endDate }
            } else {
                if !currentGroup.isEmpty { groups.append(currentGroup) }
                currentGroup = [event]; groupEnd = event.endDate
            }
        }
        if !currentGroup.isEmpty { groups.append(currentGroup) }

        for group in groups {
            for (idx, event) in group.enumerated() {
                result.append(LayoutEvent(event: event, columnIndex: idx, totalColumns: group.count))
            }
        }
        return result
    }

    // MARK: - Helpers

    private func mondayOfWeekContaining(_ date: Date) -> Date {
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        comps.weekday = 2
        return cal.date(from: comps) ?? date
    }

    private func eventsForDay(_ date: Date) -> [CalendarEvent] {
        service.events.filter { cal.isDate($0.startDate, inSameDayAs: date) }
    }

    private func weekRangeString() -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "de_DE")
        fmt.dateFormat = "d. MMM"
        let monday = weekDays.first ?? today
        let sunday = weekDays.last ?? today
        return "\(fmt.string(from: monday)) – \(fmt.string(from: sunday))"
    }

    private func yearString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy"
        return fmt.string(from: weekDays.first ?? today)
    }

    private func timeRange(_ event: CalendarEvent) -> String {
        let fmt = DateFormatter(); fmt.dateFormat = "HH:mm"
        return "\(fmt.string(from: event.startDate)) – \(fmt.string(from: event.endDate))"
    }
}
