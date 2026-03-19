import Foundation
import CloudKit

final class CloudKitManager: CloudBackendProtocol {
    static let shared = CloudKitManager()

    private let container = CKContainer(identifier: "iCloud.com.todoapp.aufgaben")
    private var database: CKDatabase { container.privateCloudDatabase }
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Record type used for all app data
    private let recordType = "AppData"

    /// Polling timer for change detection
    private var pollingTimer: Timer?
    private var todosChangeHandler: (([Todo]) -> Void)?
    private var categoriesChangeHandler: (([Category]) -> Void)?

    private init() {}

    // MARK: - Save

    func saveTodos(_ todos: [Todo]) async {
        await saveData(todos, type: "todos")
    }

    func saveCategories(_ categories: [Category]) async {
        await saveData(categories, type: "categories")
    }

    func saveSubjectProgress(_ subjects: [SubjectProgress]) async {
        await saveData(subjects, type: "progress")
    }

    func saveGrades(_ grades: DualisGradeData?) async {
        guard let grades else {
            await deleteRecord(type: "grades")
            return
        }
        guard let jsonData = try? encoder.encode(grades) else { return }
        await saveRawData(jsonData, type: "grades")
    }

    func saveSettings(icalURL: String, appearance: String) async {
        let dict: [String: String] = ["icalURL": icalURL, "appearance": appearance]
        guard let jsonData = try? encoder.encode(dict) else { return }
        await saveRawData(jsonData, type: "settings")
    }

    // MARK: - Load

    func loadTodos() async -> [Todo]? {
        await loadData(type: "todos")
    }

    func loadCategories() async -> [Category]? {
        await loadData(type: "categories")
    }

    func loadSubjectProgress() async -> [SubjectProgress]? {
        await loadData(type: "progress")
    }

    func loadGrades() async -> DualisGradeData? {
        guard let data = await loadRawData(type: "grades") else { return nil }
        return try? decoder.decode(DualisGradeData.self, from: data)
    }

    func loadSettings() async -> (icalURL: String, appearance: String)? {
        guard let data = await loadRawData(type: "settings"),
              let dict = try? decoder.decode([String: String].self, from: data) else { return nil }
        return (dict["icalURL"] ?? "", dict["appearance"] ?? "system")
    }

    func hasCloudData() async -> Bool {
        let record = await fetchRecord(type: "todos")
        return record != nil
    }

    // MARK: - Delete All

    func deleteAllData() async {
        for type in ["todos", "categories", "progress", "grades", "settings"] {
            await deleteRecord(type: type)
        }
    }

    // MARK: - Listeners (Polling-based)

    /// CloudKit private DB doesn't support push subscriptions reliably,
    /// so we poll every 30 seconds for changes.
    func listenToTodos(onChange: @escaping ([Todo]) -> Void) -> Any? {
        todosChangeHandler = onChange
        startPollingIfNeeded()
        return "todos_listener" as NSString
    }

    func listenToCategories(onChange: @escaping ([Category]) -> Void) -> Any? {
        categoriesChangeHandler = onChange
        startPollingIfNeeded()
        return "categories_listener" as NSString
    }

    func removeListener(_ listener: Any) {
        guard let key = listener as? NSString else { return }
        if key == "todos_listener" { todosChangeHandler = nil }
        if key == "categories_listener" { categoriesChangeHandler = nil }

        if todosChangeHandler == nil && categoriesChangeHandler == nil {
            pollingTimer?.invalidate()
            pollingTimer = nil
        }
    }

    private func startPollingIfNeeded() {
        guard pollingTimer == nil else { return }
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.pollForChanges()
            }
        }
    }

    private func pollForChanges() async {
        if let handler = todosChangeHandler,
           let todos: [Todo] = await loadData(type: "todos") {
            handler(todos)
        }
        if let handler = categoriesChangeHandler,
           let categories: [Category] = await loadData(type: "categories") {
            handler(categories)
        }
    }

    // MARK: - Private: Generic save/load using CKRecord

    private func saveData<T: Encodable>(_ items: [T], type: String) async {
        guard let jsonData = try? encoder.encode(items) else { return }
        await saveRawData(jsonData, type: type)
    }

    private func saveRawData(_ jsonData: Data, type: String) async {
        // Try to fetch existing record to update it (avoids creating duplicates)
        let record: CKRecord
        if let existing = await fetchRecord(type: type) {
            record = existing
        } else {
            let recordID = CKRecord.ID(recordName: "appdata_\(type)")
            record = CKRecord(recordType: recordType, recordID: recordID)
            record["type"] = type as CKRecordValue
        }

        record["jsonData"] = jsonData as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue

        do {
            try await database.save(record)
        } catch {
            print("CloudKit save error (\(type)): \(error.localizedDescription)")
        }
    }

    private func loadData<T: Decodable>(type: String) async -> [T]? {
        guard let data = await loadRawData(type: type) else { return nil }
        return try? decoder.decode([T].self, from: data)
    }

    private func loadRawData(type: String) async -> Data? {
        guard let record = await fetchRecord(type: type),
              let data = record["jsonData"] as? Data else { return nil }
        return data
    }

    private func fetchRecord(type: String) async -> CKRecord? {
        let recordID = CKRecord.ID(recordName: "appdata_\(type)")
        do {
            return try await database.record(for: recordID)
        } catch {
            return nil
        }
    }

    private func deleteRecord(type: String) async {
        let recordID = CKRecord.ID(recordName: "appdata_\(type)")
        _ = try? await database.deleteRecord(withID: recordID)
    }
}
