import Foundation
import WidgetKit

final class PersistenceManager {
    static let shared = PersistenceManager()
    static let appGroupID = "group.com.todoapp.aufgaben.ipad"

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let defaults: UserDefaults

    private let todosKey           = "todoapp_todos_v1"
    private let categoriesKey      = "todoapp_categories_v1"
    private let subjectProgressKey = "todoapp_subject_progress_v1"
    private let gradesKey          = "todoapp_grades_v1"

    private init() {
        defaults = UserDefaults(suiteName: Self.appGroupID) ?? .standard
    }

    // MARK: - Migration

    func migrateToAppGroupIfNeeded() {
        let migrationKey = "todoapp_migrated_to_app_group"
        guard !defaults.bool(forKey: migrationKey) else { return }

        let standard = UserDefaults.standard
        let keys = [todosKey, categoriesKey, subjectProgressKey, gradesKey,
                    "todoapp_ical_url", "todoapp_appearance",
                    "todoapp_calendar_events_v2"]

        for key in keys {
            if let value = standard.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }

        defaults.set(true, forKey: migrationKey)
        defaults.synchronize()
    }

    // MARK: - Todos

    func saveTodos(_ todos: [Todo]) {
        guard let data = try? encoder.encode(todos) else { return }
        defaults.set(data, forKey: todosKey)
        reloadWidgets()
    }

    func loadTodos() -> [Todo] {
        guard
            let data  = defaults.data(forKey: todosKey),
            let todos = try? decoder.decode([Todo].self, from: data)
        else { return [] }
        return todos
    }

    // MARK: - Categories

    func saveCategories(_ categories: [Category]) {
        guard let data = try? encoder.encode(categories) else { return }
        defaults.set(data, forKey: categoriesKey)
        reloadWidgets()
    }

    func loadCategories() -> [Category] {
        guard
            let data       = defaults.data(forKey: categoriesKey),
            let categories = try? decoder.decode([Category].self, from: data)
        else { return [] }
        return categories
    }

    // MARK: - SubjectProgress

    func saveSubjectProgress(_ subjects: [SubjectProgress]) {
        guard let data = try? encoder.encode(subjects) else { return }
        defaults.set(data, forKey: subjectProgressKey)
    }

    func loadSubjectProgress() -> [SubjectProgress] {
        guard
            let data     = defaults.data(forKey: subjectProgressKey),
            let subjects = try? decoder.decode([SubjectProgress].self, from: data)
        else { return [] }
        return subjects
    }

    // MARK: - Grades

    func saveGrades(_ grades: DualisGradeData?) {
        guard let grades = grades,
              let data = try? encoder.encode(grades) else {
            defaults.removeObject(forKey: gradesKey)
            return
        }
        defaults.set(data, forKey: gradesKey)
    }

    func loadGrades() -> DualisGradeData? {
        guard
            let data   = defaults.data(forKey: gradesKey),
            let grades = try? decoder.decode(DualisGradeData.self, from: data)
        else { return nil }
        return grades
    }

    // MARK: - Clear All

    func clearAll() {
        defaults.removeObject(forKey: todosKey)
        defaults.removeObject(forKey: categoriesKey)
        defaults.removeObject(forKey: subjectProgressKey)
        defaults.removeObject(forKey: gradesKey)
        reloadWidgets()
    }

    // MARK: - Widget Reload

    private func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
