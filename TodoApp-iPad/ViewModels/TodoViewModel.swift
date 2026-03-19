import Foundation
import SwiftUI

enum SortOrder: String, CaseIterable {
    case createdAt = "Erstellt"
    case dueDate   = "Fälligkeitsdatum"
    case priority  = "Priorität"
    case title     = "Titel"
}

@MainActor
class TodoViewModel: ObservableObject {

    // MARK: - Published state

    @Published var todos: [Todo] = []
    @Published var categories: [Category] = []

    @Published var searchText: String = ""
    @Published var selectedCategory: String? = nil
    @Published var selectedPriority: Priority? = nil
    @Published var showCompleted: Bool = false
    @Published var sortOrder: SortOrder = .createdAt

    // MARK: - Dependencies

    private let persistence = PersistenceManager.shared
    private let notifications = NotificationManager.shared
    private var syncObserver: NSObjectProtocol?

    init() {
        load()
        syncObserver = NotificationCenter.default.addObserver(
            forName: .syncDidComplete, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reload()
            }
        }
    }

    deinit {
        if let observer = syncObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Derived: filtered + sorted list

    var filteredTodos: [Todo] {
        var result = todos.filter { todo in
            let matchSearch    = searchText.isEmpty
                || todo.title.localizedCaseInsensitiveContains(searchText)
                || todo.notes.localizedCaseInsensitiveContains(searchText)
            let matchCategory  = selectedCategory == nil || todo.categoryName == selectedCategory
            let matchPriority  = selectedPriority == nil || todo.priority == selectedPriority
            let matchCompleted = showCompleted || !todo.isCompleted
            return matchSearch && matchCategory && matchPriority && matchCompleted
        }
        sort(&result)
        return result
    }

    // MARK: - Derived: statistics

    var stats: TodoStats {
        TodoStats(
            total:     todos.count,
            completed: todos.filter { $0.isCompleted }.count,
            overdue:   todos.filter { $0.isOverdue }.count,
            dueToday:  todos.filter { $0.isDueToday }.count
        )
    }

    var recentlyCompleted: [Todo] {
        todos
            .filter { $0.isCompleted }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            .prefix(5)
            .map { $0 }
    }

    var hasActiveFilters: Bool {
        selectedPriority != nil || showCompleted || sortOrder != .createdAt || selectedCategory != nil
    }

    // MARK: - CRUD

    func add(_ todo: Todo) {
        todos.append(todo)
        scheduleIfNeeded(todo)
        save()
    }

    func update(_ todo: Todo) {
        guard let i = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        notifications.cancel(id: todo.id)
        todos[i] = todo
        scheduleIfNeeded(todo)
        save()
    }

    func toggle(_ todo: Todo) {
        guard let i = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        todos[i].isCompleted.toggle()
        todos[i].completedAt = todos[i].isCompleted ? Date() : nil
        save()
    }

    func delete(_ todo: Todo) {
        notifications.cancel(id: todo.id)
        todos.removeAll { $0.id == todo.id }
        save()
    }

    // MARK: - Helpers

    func category(named name: String) -> Category? {
        categories.first { $0.name == name }
    }

    func categoryStats() -> [(category: Category, count: Int)] {
        categories.compactMap { cat in
            let count = todos.filter { !$0.isCompleted && $0.categoryName == cat.name }.count
            return count > 0 ? (cat, count) : nil
        }.sorted { $0.count > $1.count }
    }

    func resetFilters() {
        selectedPriority = nil
        selectedCategory = nil
        showCompleted    = false
        sortOrder        = .createdAt
    }

    // MARK: - Private

    private func sort(_ list: inout [Todo]) {
        switch sortOrder {
        case .createdAt:
            list.sort { $0.createdAt > $1.createdAt }
        case .dueDate:
            list.sort { a, b in
                guard let aDate = a.dueDate else { return false }
                guard let bDate = b.dueDate else { return true }
                return aDate < bDate
            }
        case .priority:
            list.sort { $0.priority.sortOrder < $1.priority.sortOrder }
        case .title:
            list.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        }
    }

    private func scheduleIfNeeded(_ todo: Todo) {
        if let reminder = todo.reminderDate {
            notifications.schedule(for: todo, at: reminder)
        }
    }

    private func save() {
        persistence.saveTodos(todos)
        persistence.saveCategories(categories)
        // Only push to cloud if this isn't a remote change being applied
        if !SyncManager.shared.isApplyingRemoteChange {
            let currentTodos = todos
            let currentCategories = categories
            Task { @MainActor in
                SyncManager.shared.syncTodos(currentTodos)
                SyncManager.shared.syncCategories(currentCategories)
            }
        }
    }

    func reload() {
        todos      = persistence.loadTodos()
        categories = persistence.loadCategories()
        if categories.isEmpty {
            categories = Category.defaults
            persistence.saveCategories(categories)
        }
    }

    private func load() {
        reload()
    }
}

// MARK: - Stats model

struct TodoStats {
    let total: Int
    let completed: Int
    let overdue: Int
    let dueToday: Int

    var pending: Int { total - completed }

    var completionRate: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
}
