import SwiftUI
import Charts

struct StatsView: View {
    @EnvironmentObject var vm: TodoViewModel

    private var stats: TodoStats { vm.stats }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Statistik")
                    .font(.system(size: 28, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .center)

                // Top row: ring + quick stats side by side on iPad
                HStack(alignment: .top, spacing: 24) {
                    completionRing
                    quickStatsGrid
                }

                categoryBreakdown
                recentlyCompletedSection
            }
            .padding(24)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Completion ring

    private var completionRing: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color(.systemFill), lineWidth: 20)
                    .frame(width: 180, height: 180)

                Circle()
                    .trim(from: 0, to: stats.completionRate)
                    .stroke(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .frame(width: 180, height: 180)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 1.0), value: stats.completionRate)

                VStack(spacing: 2) {
                    Text("\(Int(stats.completionRate * 100))%")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .contentTransition(.numericText())
                    Text("Erledigt")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text("\(stats.completed) von \(stats.total) Aufgaben erledigt")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Quick stats grid

    private var quickStatsGrid: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                StatCard(title: "Gesamt",       value: stats.total,    icon: "checklist",                color: .blue)
                StatCard(title: "Offen",        value: stats.pending,  icon: "circle",                   color: .orange)
            }
            HStack(spacing: 14) {
                StatCard(title: "Heute fällig", value: stats.dueToday, icon: "calendar",                 color: .purple)
                StatCard(title: "Überfällig",   value: stats.overdue,  icon: "exclamationmark.triangle",  color: .red)
            }
        }
    }

    // MARK: - Category breakdown

    private var categoryBreakdown: some View {
        let data = vm.categoryStats()
        return Group {
            if !data.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Offene Aufgaben nach Kategorie")
                        .font(.headline)

                    Chart(data, id: \.category.id) { item in
                        BarMark(
                            x: .value("Anzahl", item.count),
                            y: .value("Kategorie", item.category.name)
                        )
                        .foregroundStyle(item.category.color)
                        .annotation(position: .trailing) {
                            Text("\(item.count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel()
                        }
                    }
                    .frame(height: CGFloat(max(data.count, 1)) * 50)
                }
                .padding(20)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    // MARK: - Recently completed

    @ViewBuilder
    private var recentlyCompletedSection: some View {
        if !vm.recentlyCompleted.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Zuletzt erledigt")
                    .font(.headline)

                ForEach(vm.recentlyCompleted) { todo in
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(todo.title)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .strikethrough()
                            .lineLimit(1)
                        Spacer()
                        if let date = todo.completedAt {
                            Text(relativeDate(date))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .padding(20)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Stat card component

struct StatCard: View {
    let title: String
    let value: Int
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text("\(value)")
                .font(.title)
                .fontWeight(.bold)
                .contentTransition(.numericText())
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
