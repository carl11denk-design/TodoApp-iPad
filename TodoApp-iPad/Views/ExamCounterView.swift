import SwiftUI

struct ExamCounterView: View {
    var service: ICalService

    private static let sharedDefaults = UserDefaults(suiteName: PersistenceManager.appGroupID)
    @AppStorage("todoapp_ical_url", store: ExamCounterView.sharedDefaults) private var icalURL = ""

    @Environment(\.colorScheme) private var colorScheme
    @State private var showPastExams = false

    // MARK: - Klausur-Keywords

    private let examKeywords = [
        "klausur", "prüfung", "pruefung", "exam",
        "test", "klassenarbeit", "leistungsnachweis"
    ]

    /// Begriffe die NICHT als Klausur zählen
    private let excludeKeywords = [
        "prüfungsphase", "pruefungsphase", "prüfungsphasen",
        "prüfungszeitraum", "prüfungszeit", "prüfungsvorbereitung",
        "prüfungsanmeldung", "prüfungstermine"
    ]

    // MARK: - Gefilterte Klausuren

    private var allExamEvents: [CalendarEvent] {
        service.events.filter { event in
            let lower = event.summary.lowercased()
            let matchesExam = examKeywords.contains(where: { lower.contains($0) })
            let isExcluded = excludeKeywords.contains(where: { lower.contains($0) })
            return matchesExam && !isExcluded
        }
        .sorted { $0.startDate < $1.startDate }
    }

    private var upcomingExams: [CalendarEvent] {
        let now = Calendar.current.startOfDay(for: Date())
        return allExamEvents.filter { $0.startDate >= now }
    }

    private var pastExams: [CalendarEvent] {
        let now = Calendar.current.startOfDay(for: Date())
        return allExamEvents.filter { $0.startDate < now }.reversed()
    }

    private var displayedExams: [CalendarEvent] {
        showPastExams ? Array(pastExams) : upcomingExams
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text("Klausuren")
                .font(.system(size: 28, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 12)
                .padding(.bottom, 2)

            // Toggle + Info
            HStack {
                Picker("", selection: $showPastExams) {
                    Text("Anstehend (\(upcomingExams.count))").tag(false)
                    Text("Vergangen (\(pastExams.count))").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)

                Spacer()

                if service.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 8)

            if icalURL.isEmpty {
                noURLState
            } else if displayedExams.isEmpty {
                emptyState
            } else {
                examList
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .toolbar { toolbarContent }
        .task {
            if !icalURL.isEmpty && service.events.isEmpty {
                await service.fetch(url: icalURL)
            }
        }
    }

    // MARK: - Klausur-Liste

    private var examList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(displayedExams) { exam in
                    ExamCard(event: exam, colorScheme: colorScheme, isPast: showPastExams)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Empty States

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: showPastExams ? "clock.arrow.circlepath" : "party.popper.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text(showPastExams ? "Keine vergangenen Klausuren" : "Keine anstehenden Klausuren")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Text(showPastExams
                 ? "Es wurden keine vergangenen Klausuren im Stundenplan gefunden."
                 : "Aktuell stehen keine Klausuren an — viel Spaß mit der freien Zeit! 🎉")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            Spacer()
        }
        .padding()
    }

    private var noURLState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("Kein Stundenplan verknüpft")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Text("Füge eine iCal-URL in den Einstellungen hinzu, um Klausuren zu erkennen.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            Spacer()
        }
        .padding()
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Button {
                Task {
                    await service.fetch(url: icalURL)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.title2)
            }
            .disabled(icalURL.isEmpty)
        }
    }
}

// MARK: - Exam Card

private struct ExamCard: View {
    let event: CalendarEvent
    let colorScheme: ColorScheme
    let isPast: Bool

    private var daysRemaining: Int {
        let today = Calendar.current.startOfDay(for: Date())
        let examDay = Calendar.current.startOfDay(for: event.startDate)
        return Calendar.current.dateComponents([.day], from: today, to: examDay).day ?? 0
    }

    private var subjectColor: Color {
        colorForString(event.summary, colorScheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Farbiger Seitenbalken
            RoundedRectangle(cornerRadius: 2)
                .fill(subjectColor)
                .frame(width: 5)
                .padding(.vertical, 4)

            HStack(spacing: 16) {
                // Countdown-Badge
                countdownBadge
                    .frame(width: 80)

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.summary)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(2)

                    HStack(spacing: 12) {
                        // Datum
                        Label(formattedDate, systemImage: "calendar")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)

                        // Uhrzeit
                        Label(formattedTime, systemImage: "clock")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    if let loc = event.location, !loc.isEmpty {
                        Label(loc, systemImage: "mappin.and.ellipse")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Dauer
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formattedDuration)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Dauer")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .opacity(isPast ? 0.6 : 1.0)
    }

    // MARK: - Countdown Badge

    @ViewBuilder
    private var countdownBadge: some View {
        if isPast {
            VStack(spacing: 2) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.green)
                Text("Vorbei")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        } else if daysRemaining == 0 {
            VStack(spacing: 2) {
                Text("HEUTE")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.red)
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .modifier(PulseModifier())
            }
        } else if daysRemaining == 1 {
            VStack(spacing: 2) {
                Text("1")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                Text("Morgen")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
            }
        } else {
            VStack(spacing: 2) {
                Text("\(daysRemaining)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(countdownColor)
                Text(daysRemaining == 1 ? "Tag" : "Tage")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(countdownColor.opacity(0.8))
            }
        }
    }

    private var countdownColor: Color {
        if daysRemaining <= 3 { return .red }
        if daysRemaining <= 7 { return .orange }
        if daysRemaining <= 14 { return .yellow }
        return .secondary
    }

    // MARK: - Formatierung

    private var formattedDate: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EE, dd. MMMM yyyy"
        return f.string(from: event.startDate)
    }

    private var formattedTime: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let start = f.string(from: event.startDate)
        let end = f.string(from: event.endDate)
        return "\(start) – \(end)"
    }

    private var formattedDuration: String {
        let minutes = Int(event.endDate.timeIntervalSince(event.startDate) / 60)
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)min" }
        if h > 0 { return "\(h)h" }
        return "\(m)min"
    }
}

// MARK: - Pulsing Animation

private struct PulseModifier: ViewModifier {
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pulsing ? 1.5 : 1.0)
            .opacity(pulsing ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
    }
}
