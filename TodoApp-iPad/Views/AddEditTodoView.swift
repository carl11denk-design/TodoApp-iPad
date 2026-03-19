import SwiftUI

struct AddEditTodoView: View {
    @EnvironmentObject var vm: TodoViewModel
    @Environment(\.dismiss) var dismiss

    var todo: Todo? = nil

    @State private var title: String        = ""
    @State private var notes: String        = ""
    @State private var priority: Priority   = .medium
    @State private var categoryName: String = "Allgemein"
    @State private var hasDueDate: Bool     = false
    @State private var dueDate: Date        = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var hasReminder: Bool    = false
    @State private var reminderDate: Date   = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()

    private var isEditing: Bool { todo != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Aufgabe eingeben…", text: $title, axis: .vertical)
                        .font(.body)
                        .lineLimit(1...4)
                }

                Section("Notizen") {
                    TextField("Optionale Notizen…", text: $notes, axis: .vertical)
                        .lineLimit(1...6)
                }

                Section("Details") {
                    Picker("Priorität", selection: $priority) {
                        ForEach(Priority.allCases, id: \.self) { p in
                            Label(p.rawValue, systemImage: p.icon)
                                .tag(p)
                        }
                    }

                    Picker("Kategorie", selection: $categoryName) {
                        ForEach(vm.categories) { cat in
                            Label(cat.name, systemImage: cat.icon)
                                .tag(cat.name)
                        }
                    }
                }

                Section("Fälligkeitsdatum") {
                    Toggle("Fälligkeitsdatum festlegen", isOn: $hasDueDate.animation())
                    if hasDueDate {
                        DatePicker("Datum", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    }
                }

                Section("Erinnerung") {
                    Toggle("Erinnerung einrichten", isOn: $hasReminder.animation())
                    if hasReminder {
                        DatePicker("Zeitpunkt", selection: $reminderDate, displayedComponents: [.date, .hourAndMinute])
                    }
                }

                if isEditing {
                    Section {
                        Button("Aufgabe löschen", role: .destructive) {
                            if let todo { vm.delete(todo) }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Aufgabe bearbeiten" : "Neue Aufgabe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "Speichern" : "Hinzufügen") {
                        save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { populateIfEditing() }
        }
    }

    private func populateIfEditing() {
        guard let todo else { return }
        title        = todo.title
        notes        = todo.notes
        priority     = todo.priority
        categoryName = todo.categoryName
        if let due = todo.dueDate {
            hasDueDate = true
            dueDate    = due
        }
        if let reminder = todo.reminderDate {
            hasReminder  = true
            reminderDate = reminder
        }
    }

    private func save() {
        var t            = todo ?? Todo(title: "")
        t.title          = title.trimmingCharacters(in: .whitespaces)
        t.notes          = notes
        t.priority       = priority
        t.categoryName   = categoryName
        t.dueDate        = hasDueDate    ? dueDate      : nil
        t.reminderDate   = hasReminder   ? reminderDate : nil

        if isEditing {
            vm.update(t)
        } else {
            vm.add(t)
        }
    }
}
