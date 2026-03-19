import SwiftUI

// MARK: - Farbpalette für den Picker

private let colorHues: [Double] = [
    0/360,   // Rot
    20/360,  // Orange
    45/360,  // Gelb
    90/360,  // Hellgrün
    140/360, // Grün
    175/360, // Mint
    200/360, // Hellblau
    220/360, // Blau
    250/360, // Indigo
    270/360, // Lila
    300/360, // Pink
    330/360  // Rose
]

private func subjectColor(_ subject: SubjectProgress, colorScheme: ColorScheme) -> Color {
    if let hue = subject.customColorHue {
        let sat = colorScheme == .dark ? 0.60 : 0.78
        let bri = colorScheme == .dark ? 0.88 : 0.52
        return Color(hue: hue, saturation: sat, brightness: bri)
    }
    return colorForString(subject.name, colorScheme: colorScheme)
}

// MARK: - LernfortschrittView (iPad: 2-3 column grid)

struct LernfortschrittView: View {
    @EnvironmentObject private var vm: SubjectProgressViewModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var showAddSheet   = false
    @State private var editingSubject: SubjectProgress?

    var body: some View {
        VStack(spacing: 0) {
            Text("Lernfortschritt")
                .font(.system(size: 28, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
                .padding(.bottom, 4)

            Group {
                if vm.subjects.isEmpty {
                    emptyState
                } else {
                    subjectGrid
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddSubjectSheet { name in
                vm.add(SubjectProgress(name: name))
            }
            .frame(minWidth: 400)
        }
        .sheet(item: $editingSubject) { subject in
            EditSubjectSheet(subject: subject) { updated in
                vm.update(updated)
            } onDelete: {
                vm.delete(subject)
            }
            .frame(minWidth: 500, idealWidth: 600)
        }
    }

    // MARK: - Grid

    private var subjectGrid: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16),
            ], spacing: 16) {
                ForEach(vm.subjects) { subject in
                    SubjectCard(subject: subject, colorScheme: colorScheme)
                        .onTapGesture { editingSubject = subject }
                }
            }
            .padding(24)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Leerzustand

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.pages")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            Text("Noch keine Fächer")
                .font(.title2.bold())
                .foregroundStyle(.secondary)
            Text("Tippe auf + um ein Fach hinzuzufügen.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Fach-Karte

private struct SubjectCard: View {
    let subject: SubjectProgress
    let colorScheme: ColorScheme

    private var accent: Color { subjectColor(subject, colorScheme: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle()
                    .fill(accent)
                    .frame(width: 14, height: 14)
                    .shadow(color: accent.opacity(0.5), radius: 3)
                Text(subject.name)
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Divider().opacity(0.4)

            progressRow(icon: "doc.text.fill",      label: "Skript",
                        current: subject.scriptCurrentPage,     total: subject.scriptTotalPages,
                        color: accent)

            progressRow(icon: "pencil.and.outline", label: "Nacharbeit",
                        current: subject.nacharbeitCurrentPage, total: subject.nacharbeitTotalPages,
                        color: accent.opacity(0.75))
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(accent)
                .frame(width: 4)
                .padding(.vertical, 14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func progressRow(icon: String, label: String,
                             current: Int, total: Int, color: Color) -> some View {
        let fraction: Double = total > 0 ? Swift.min(Double(current) / Double(total), 1.0) : 0
        return VStack(spacing: 5) {
            HStack {
                Label(label, systemImage: icon)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(color)
                Spacer()
                if total > 0 {
                    Text("Seite \(current) / \(total)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text("Noch nicht gesetzt")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.15)).frame(height: 8)
                    RoundedRectangle(cornerRadius: 4).fill(color)
                        .frame(width: geo.size.width * fraction, height: 8)
                        .animation(.easeInOut(duration: 0.4), value: fraction)
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Fach hinzufügen

private struct AddSubjectSheet: View {
    let onAdd: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Fachname", text: $name)
                        .autocorrectionDisabled()
                } header: {
                    Text("Neues Fach")
                }
            }
            .navigationTitle("Fach hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Hinzufügen") {
                        let t = name.trimmingCharacters(in: .whitespaces)
                        guard !t.isEmpty else { return }
                        onAdd(t); dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.height(220)])
    }
}

// MARK: - Fach bearbeiten

private struct EditSubjectSheet: View {
    @State private var subject: SubjectProgress
    let onSave:   (SubjectProgress) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss)     private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showDeleteConfirm = false
    @FocusState private var isFocused: Bool

    init(subject: SubjectProgress,
         onSave: @escaping (SubjectProgress) -> Void,
         onDelete: @escaping () -> Void) {
        _subject      = State(initialValue: subject)
        self.onSave   = onSave
        self.onDelete = onDelete
    }

    private var accent: Color { subjectColor(subject, colorScheme: colorScheme) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack { Spacer(); progressRing; Spacer() }
                        .listRowBackground(Color.clear)
                        .padding(.vertical, 8)
                }

                Section {
                    colorPicker
                } header: {
                    Label("Farbe", systemImage: "paintpalette")
                }

                Section {
                    stepperRow(label: "Aktuelle Seite", value: $subject.scriptCurrentPage,
                               max: subject.scriptTotalPages > 0 ? subject.scriptTotalPages : 9999)
                    stepperRow(label: "Gesamtseiten",   value: $subject.scriptTotalPages, max: 9999)
                } header: {
                    Label("Skript", systemImage: "doc.text.fill").foregroundStyle(accent)
                }

                Section {
                    stepperRow(label: "Aktuelle Seite", value: $subject.nacharbeitCurrentPage,
                               max: subject.nacharbeitTotalPages > 0 ? subject.nacharbeitTotalPages : 9999)
                    stepperRow(label: "Gesamtseiten",   value: $subject.nacharbeitTotalPages, max: 9999)
                } header: {
                    Label("Nacharbeit", systemImage: "pencil.and.outline").foregroundStyle(accent.opacity(0.8))
                }

                Section {
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Label("Fach entfernen", systemImage: "trash")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle(subject.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sichern") {
                        if subject.scriptTotalPages > 0 {
                            subject.scriptCurrentPage = Swift.min(subject.scriptCurrentPage, subject.scriptTotalPages)
                        }
                        if subject.nacharbeitTotalPages > 0 {
                            subject.nacharbeitCurrentPage = Swift.min(subject.nacharbeitCurrentPage, subject.nacharbeitTotalPages)
                        }
                        onSave(subject); dismiss()
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") { isFocused = false }
                }
            }
            .confirmationDialog("Fach entfernen?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Entfernen", role: .destructive) { onDelete(); dismiss() }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Der Fortschritt für \"\(subject.name)\" wird gelöscht.")
            }
        }
    }

    private var progressRing: some View {
        let fraction = subject.scriptProgress
        return ZStack {
            Circle().stroke(accent.opacity(0.15), lineWidth: 14).frame(width: 120, height: 120)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .frame(width: 120, height: 120)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: fraction)
            VStack(spacing: 1) {
                Text("\(Int(fraction * 100))%").font(.title2.bold())
                Text("Skript").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var colorPicker: some View {
        let sat = colorScheme == .dark ? 0.60 : 0.78
        let bri = colorScheme == .dark ? 0.88 : 0.52

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Button {
                    subject.customColorHue = nil
                } label: {
                    ZStack {
                        Circle()
                            .fill(
                                AngularGradient(
                                    colors: [.red, .yellow, .green, .blue, .purple, .red],
                                    center: .center
                                )
                            )
                            .frame(width: 34, height: 34)
                        if subject.customColorHue == nil {
                            Circle()
                                .stroke(Color.primary, lineWidth: 3)
                                .frame(width: 34, height: 34)
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)

                ForEach(colorHues, id: \.self) { hue in
                    let color = Color(hue: hue, saturation: sat, brightness: bri)
                    let selected = subject.customColorHue.map { abs($0 - hue) < 0.001 } ?? false
                    Button {
                        subject.customColorHue = hue
                    } label: {
                        ZStack {
                            Circle().fill(color).frame(width: 34, height: 34)
                            if selected {
                                Circle().stroke(Color.primary, lineWidth: 3).frame(width: 34, height: 34)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func stepperRow(label: String, value: Binding<Int>, max limit: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Button {
                if value.wrappedValue > 0 { value.wrappedValue -= 1 }
            } label: {
                Image(systemName: "minus.circle.fill").font(.title3)
                    .foregroundStyle(value.wrappedValue > 0 ? accent : Color(.systemGray4))
            }
            .buttonStyle(.plain)

            TextField("0", text: Binding(
                get: { "\(value.wrappedValue)" },
                set: { str in
                    let digits = str.filter { $0.isNumber }
                    let n = Int(digits) ?? value.wrappedValue
                    value.wrappedValue = Swift.max(0, Swift.min(n, limit))
                }
            ))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(.body.monospacedDigit())
            .frame(minWidth: 44, maxWidth: 60)
            .focused($isFocused)

            Button {
                if value.wrappedValue < limit { value.wrappedValue += 1 }
            } label: {
                Image(systemName: "plus.circle.fill").font(.title3)
                    .foregroundStyle(value.wrappedValue < limit ? accent : Color(.systemGray4))
            }
            .buttonStyle(.plain)
        }
    }
}
