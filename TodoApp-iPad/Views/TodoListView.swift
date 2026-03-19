import SwiftUI

struct TodoListView: View {
    @EnvironmentObject var vm: TodoViewModel
    @State private var showAddTodo    = false
    @State private var editingTodo: Todo? = nil
    @State private var showFilterSheet = false

    var body: some View {
        VStack(spacing: 0) {
            Text("Aufgaben")
                .font(.system(size: 28, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
                .padding(.bottom, 4)

            // Search + filter bar
            HStack(spacing: 12) {
                searchBar
                filterButton
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 4)

            categoryChips

            if vm.filteredTodos.isEmpty {
                emptyState
            } else {
                todoGrid
            }
        }
        .background(Color(.systemGroupedBackground))
        .toolbar { toolbarContent }
        .sheet(isPresented: $showAddTodo) {
            AddEditTodoView()
                .environmentObject(vm)
                .frame(minWidth: 500, idealWidth: 600)
        }
        .sheet(item: $editingTodo) { todo in
            AddEditTodoView(todo: todo)
                .environmentObject(vm)
                .frame(minWidth: 500, idealWidth: 600)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAddTodo)) { _ in
            showAddTodo = true
        }
        .sheet(isPresented: $showFilterSheet) {
            FilterSheetView()
                .environmentObject(vm)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Suchen…", text: $vm.searchText)
                .autocorrectionDisabled()
            if !vm.searchText.isEmpty {
                Button {
                    vm.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var filterButton: some View {
        Button {
            showFilterSheet = true
        } label: {
            Image(systemName: vm.hasActiveFilters
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
            .font(.title2)
            .foregroundStyle(vm.hasActiveFilters ? .blue : .primary)
        }
    }

    // MARK: - Category chips

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                chip(name: "Alle", icon: "tray.fill", colorHex: "#6B7280", isSelected: vm.selectedCategory == nil) {
                    vm.selectedCategory = nil
                }
                ForEach(vm.categories) { cat in
                    chip(name: cat.name, icon: cat.icon, colorHex: cat.colorHex, isSelected: vm.selectedCategory == cat.name) {
                        vm.selectedCategory = (vm.selectedCategory == cat.name) ? nil : cat.name
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
    }

    private func chip(name: String, icon: String, colorHex: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        let color = Color(hex: colorHex)
        return Button(action: action) {
            Label(name, systemImage: icon)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(isSelected ? .white : color)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? color : color.opacity(0.12), in: Capsule())
        }
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }

    // MARK: - Todo grid (iPad: 2-3 columns)

    private var todoGrid: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16),
            ], spacing: 14) {
                ForEach(vm.filteredTodos) { todo in
                    TodoCardView(todo: todo)
                        .onTapGesture { editingTodo = todo }
                        .contextMenu {
                            Button {
                                withAnimation(.spring(duration: 0.3)) { vm.toggle(todo) }
                            } label: {
                                Label(
                                    todo.isCompleted ? "Rückgängig" : "Erledigt",
                                    systemImage: todo.isCompleted ? "arrow.uturn.backward" : "checkmark"
                                )
                            }
                            Button(role: .destructive) {
                                withAnimation { vm.delete(todo) }
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .animation(.default, value: vm.filteredTodos.map { $0.id })
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: vm.searchText.isEmpty && !vm.hasActiveFilters ? "checklist" : "magnifyingglass")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            Text(vm.searchText.isEmpty && !vm.hasActiveFilters ? "Keine Aufgaben" : "Keine Ergebnisse")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Text(vm.searchText.isEmpty && !vm.hasActiveFilters
                    ? "Tippe auf + um eine neue Aufgabe zu erstellen."
                    : "Versuche andere Filter oder einen anderen Suchbegriff.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showAddTodo = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
            }
        }
    }
}

// MARK: - Todo Card (iPad optimized)

struct TodoCardView: View {
    let todo: Todo
    @EnvironmentObject var vm: TodoViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Checkbox
            Button {
                withAnimation(.spring(duration: 0.3)) {
                    vm.toggle(todo)
                }
            } label: {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title)
                    .foregroundStyle(todo.isCompleted ? .green : Color(.tertiaryLabel))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(todo.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .strikethrough(todo.isCompleted, color: .secondary)
                        .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                    Spacer()
                    Image(systemName: todo.priority.icon)
                        .foregroundStyle(todo.priority.color)
                        .font(.subheadline)
                }

                if !todo.notes.isEmpty {
                    Text(todo.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    if let cat = vm.category(named: todo.categoryName) {
                        categoryChip(cat)
                    }
                    if let due = todo.dueDate {
                        dueDateChip(due)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func categoryChip(_ cat: Category) -> some View {
        Label(cat.name, systemImage: cat.icon)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(cat.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(cat.color.opacity(0.12), in: Capsule())
    }

    private func dueDateChip(_ date: Date) -> some View {
        let overdue = todo.isOverdue
        return Label(dueDateText(date), systemImage: "calendar")
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(overdue ? .red : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((overdue ? Color.red : Color.secondary).opacity(0.1), in: Capsule())
    }

    private func dueDateText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date)     { return "Heute" }
        if Calendar.current.isDateInTomorrow(date)  { return "Morgen" }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM."
        return formatter.string(from: date)
    }
}

// MARK: - Filter Sheet

struct FilterSheetView: View {
    @EnvironmentObject var vm: TodoViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Sortierung") {
                    Picker("Sortieren nach", selection: $vm.sortOrder) {
                        ForEach(SortOrder.allCases, id: \.self) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Priorität") {
                    Picker("Priorität", selection: $vm.selectedPriority) {
                        Text("Alle").tag(Priority?.none)
                        ForEach(Priority.allCases, id: \.self) { p in
                            Label(p.rawValue, systemImage: p.icon)
                                .tag(Priority?.some(p))
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Anzeige") {
                    Toggle("Erledigte anzeigen", isOn: $vm.showCompleted)
                }

                Section {
                    Button("Filter zurücksetzen", role: .destructive) {
                        vm.resetFilters()
                    }
                }
            }
            .navigationTitle("Filter & Sortierung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
