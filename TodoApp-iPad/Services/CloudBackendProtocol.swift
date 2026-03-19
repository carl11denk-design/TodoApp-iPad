import Foundation

/// Auth provider determines which cloud backend is used
enum AuthProvider: String {
    case google
    case apple
    case none
}

/// Unified interface for cloud backends (Firestore & CloudKit)
protocol CloudBackendProtocol {
    func saveTodos(_ todos: [Todo]) async
    func loadTodos() async -> [Todo]?
    func saveCategories(_ categories: [Category]) async
    func loadCategories() async -> [Category]?
    func saveSubjectProgress(_ subjects: [SubjectProgress]) async
    func loadSubjectProgress() async -> [SubjectProgress]?
    func saveGrades(_ grades: DualisGradeData?) async
    func loadGrades() async -> DualisGradeData?
    func saveSettings(icalURL: String, appearance: String) async
    func loadSettings() async -> (icalURL: String, appearance: String)?
    func hasCloudData() async -> Bool
    func deleteAllData() async

    /// Start listening for real-time changes. Returns opaque tokens to stop later.
    func listenToTodos(onChange: @escaping ([Todo]) -> Void) -> Any?
    func listenToCategories(onChange: @escaping ([Category]) -> Void) -> Any?

    /// Remove a listener returned by listenTo*
    func removeListener(_ listener: Any)
}
