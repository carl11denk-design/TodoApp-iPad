import SwiftUI

struct GradesView: View {
    @EnvironmentObject var vm: DualisViewModel

    var body: some View {
        Group {
            if let data = vm.gradeData, !data.semesters.isEmpty {
                ScrollView {
                    VStack(spacing: 20) {
                        Text("Noten")
                            .font(.system(size: 28, weight: .bold))
                            .frame(maxWidth: .infinity, alignment: .center)

                        // iPad: GPA + stats side by side
                        HStack(alignment: .top, spacing: 20) {
                            gpaCard(data)
                            summaryCard(data)
                        }

                        if let error = vm.errorMessage {
                            errorBanner(error)
                        }

                        // Semesters in a 2-column grid on iPad
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16),
                        ], spacing: 16) {
                            ForEach(data.semesters) { semester in
                                semesterSection(semester)
                            }
                        }
                    }
                    .padding(24)
                }
            } else if vm.isLoading {
                ProgressView("Lade Noten…")
            } else {
                VStack(spacing: 16) {
                    if let error = vm.errorMessage {
                        errorBanner(error)
                            .padding(.horizontal)
                    }
                    ContentUnavailableView(
                        vm.hasCredentials ? "Keine Noten" : "Zugangsdaten fehlen",
                        systemImage: vm.hasCredentials ? "graduationcap" : "person.badge.key",
                        description: Text(vm.hasCredentials ? "Tippe auf ↻ zum Laden." : "In Einstellungen hinterlegen.")
                    )
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await vm.refreshGrades() }
                } label: {
                    if vm.isLoading { ProgressView() }
                    else { Image(systemName: "arrow.clockwise") }
                }
                .disabled(vm.isLoading || !vm.hasCredentials)
            }
        }
    }

    // MARK: - GPA Card

    private func gpaCard(_ data: DualisGradeData) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color(.systemFill), lineWidth: 16)
                    .frame(width: 140, height: 140)

                if let gpa = data.overallGPA {
                    Circle()
                        .trim(from: 0, to: min(1, (5.0 - gpa) / 4.0))
                        .stroke(
                            gradeGradient(gpa),
                            style: StrokeStyle(lineWidth: 16, lineCap: .round)
                        )
                        .frame(width: 140, height: 140)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.8), value: gpa)
                }

                VStack(spacing: 1) {
                    Text(data.overallGPA.map { formatGrade($0) } ?? "–")
                        .font(.title).fontWeight(.bold)
                        .contentTransition(.numericText())
                    Text("Schnitt")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func summaryCard(_ data: DualisGradeData) -> some View {
        VStack(spacing: 20) {
            statPill(icon: "graduationcap.fill", value: String(format: "%.0f", data.totalCredits), label: "ECTS", color: .green)
            statPill(icon: "book.closed.fill", value: "\(data.semesters.flatMap(\.modules).count)", label: "Module", color: .blue)
            statPill(icon: "calendar", value: "\(data.semesters.count)", label: "Semester", color: .purple)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func statPill(icon: String, value: String, label: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title2).fontWeight(.semibold)
                Text(label)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Semester

    private func semesterSection(_ semester: DualisSemester) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    vm.toggleSemester(semester.name)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: vm.isSemesterCollapsed(semester.name) ? "chevron.right" : "chevron.down")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .frame(width: 14)
                    Text(semester.name)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Spacer()
                    if let gpa = semester.gpa {
                        Text(formatGrade(gpa))
                            .font(.subheadline).fontWeight(.bold)
                            .foregroundStyle(gradeColor(gpa))
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if !vm.isSemesterCollapsed(semester.name) {
                ForEach(semester.modules) { module in
                    Divider().padding(.leading, 16)
                    moduleRow(module)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Module Row

    private func moduleRow(_ module: DualisModule) -> some View {
        DisclosureGroup {
            if !module.exams.isEmpty {
                VStack(spacing: 6) {
                    ForEach(module.exams) { exam in
                        HStack {
                            Circle()
                                .fill(examDotColor(exam.grade).opacity(0.8))
                                .frame(width: 6, height: 6)
                            Text(exam.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            if exam.grade.isEmpty || exam.grade.lowercased().contains("nicht") {
                                Text("noch nicht gesetzt")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            } else {
                                Text(exam.displayGrade)
                                    .font(.caption).fontWeight(.medium)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
                .padding(.top, 4).padding(.bottom, 2)
            }
        } label: {
            HStack(spacing: 10) {
                gradeIndicator(module)
                Text(module.name)
                    .font(.subheadline)
                    .lineLimit(2)
                Spacer()
                if let c = module.creditsValue, c > 0 {
                    Text("\(Int(c))")
                        .font(.caption2).fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(.systemFill), in: Capsule())
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
    }

    private func gradeIndicator(_ module: DualisModule) -> some View {
        let color = moduleColor(module)
        return ZStack {
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: 36, height: 36)

            if let val = module.effectiveGradeValue, val > 0 {
                Text(module.effectiveGrade)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
            } else if module.status.lowercased().contains("bestanden") && !module.status.lowercased().contains("nicht") {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(color)
            } else {
                Text("–")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func gradeGradient(_ gpa: Double) -> LinearGradient {
        let c = gradeColor(gpa)
        return LinearGradient(colors: [c, c.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func gradeColor(_ gpa: Double) -> Color {
        gpa <= 1.5 ? .green : gpa <= 2.5 ? .blue : gpa <= 3.5 ? .orange : .red
    }

    private func moduleColor(_ module: DualisModule) -> Color {
        if let val = module.effectiveGradeValue, val > 0 { return gradeColor(val) }
        let s = module.status.lowercased()
        if s.contains("bestanden") && !s.contains("nicht") { return .green }
        if s.contains("nicht") { return .red }
        return .secondary
    }

    private func examDotColor(_ grade: String) -> Color {
        guard let val = Double(grade.replacingOccurrences(of: ",", with: ".")) else { return .secondary }
        if val > 5 { return .blue }
        return gradeColor(val)
    }

    private func formatGrade(_ value: Double) -> String {
        String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",")
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(12)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
