import Foundation
import FirebaseAuth
import FirebaseFirestore

final class FirestoreManager: CloudBackendProtocol {
    static let shared = FirestoreManager()

    private let db = Firestore.firestore()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    /// Current user's base document path: users/{uid}/data
    private func dataCollection() -> CollectionReference? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        return db.collection("users").document(uid).collection("data")
    }

    // MARK: - Save

    func saveTodos(_ todos: [Todo]) async {
        guard let col = dataCollection() else { return }
        let dict = encodeToArray(todos)
        try? await col.document("todos").setData(["items": dict, "updatedAt": FieldValue.serverTimestamp()])
    }

    func saveCategories(_ categories: [Category]) async {
        guard let col = dataCollection() else { return }
        let dict = encodeToArray(categories)
        try? await col.document("categories").setData(["items": dict, "updatedAt": FieldValue.serverTimestamp()])
    }

    func saveSubjectProgress(_ subjects: [SubjectProgress]) async {
        guard let col = dataCollection() else { return }
        let dict = encodeToArray(subjects)
        try? await col.document("progress").setData(["items": dict, "updatedAt": FieldValue.serverTimestamp()])
    }

    func saveGrades(_ grades: DualisGradeData?) async {
        guard let col = dataCollection() else { return }
        guard let grades = grades, let data = try? encoder.encode(grades),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            try? await col.document("grades").delete()
            return
        }
        try? await col.document("grades").setData(dict)
    }

    func saveSettings(icalURL: String, appearance: String) async {
        guard let col = dataCollection() else { return }
        try? await col.document("settings").setData([
            "icalURL": icalURL,
            "appearance": appearance,
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }

    // MARK: - Load

    func loadTodos() async -> [Todo]? {
        guard let col = dataCollection() else { return nil }
        return await loadArray(from: col.document("todos"))
    }

    func loadCategories() async -> [Category]? {
        guard let col = dataCollection() else { return nil }
        return await loadArray(from: col.document("categories"))
    }

    func loadSubjectProgress() async -> [SubjectProgress]? {
        guard let col = dataCollection() else { return nil }
        return await loadArray(from: col.document("progress"))
    }

    func loadGrades() async -> DualisGradeData? {
        guard let col = dataCollection() else { return nil }
        guard let snapshot = try? await col.document("grades").getDocument(),
              snapshot.exists,
              let data = snapshot.data() else { return nil }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data) else { return nil }
        return try? decoder.decode(DualisGradeData.self, from: jsonData)
    }

    func loadSettings() async -> (icalURL: String, appearance: String)? {
        guard let col = dataCollection() else { return nil }
        guard let snapshot = try? await col.document("settings").getDocument(),
              snapshot.exists,
              let data = snapshot.data() else { return nil }
        let icalURL = data["icalURL"] as? String ?? ""
        let appearance = data["appearance"] as? String ?? "system"
        return (icalURL, appearance)
    }

    /// Check if cloud has any data for this user
    func hasCloudData() async -> Bool {
        guard let col = dataCollection() else { return false }
        guard let snapshot = try? await col.document("todos").getDocument() else { return false }
        return snapshot.exists
    }

    // MARK: - Real-time Listeners

    func listenToTodos(onChange: @escaping ([Todo]) -> Void) -> Any? {
        guard let col = dataCollection() else { return nil }
        return col.document("todos").addSnapshotListener { snapshot, _ in
            guard let snapshot = snapshot, snapshot.exists,
                  let data = snapshot.data(),
                  let items = data["items"],
                  let jsonData = try? JSONSerialization.data(withJSONObject: items),
                  let todos = try? JSONDecoder().decode([Todo].self, from: jsonData)
            else { return }
            onChange(todos)
        }
    }

    func listenToCategories(onChange: @escaping ([Category]) -> Void) -> Any? {
        guard let col = dataCollection() else { return nil }
        return col.document("categories").addSnapshotListener { snapshot, _ in
            guard let snapshot = snapshot, snapshot.exists,
                  let data = snapshot.data(),
                  let items = data["items"],
                  let jsonData = try? JSONSerialization.data(withJSONObject: items),
                  let categories = try? JSONDecoder().decode([Category].self, from: jsonData)
            else { return }
            onChange(categories)
        }
    }

    func removeListener(_ listener: Any) {
        (listener as? ListenerRegistration)?.remove()
    }

    // MARK: - Delete All Data

    func deleteAllData() async {
        guard let col = dataCollection() else { return }
        for doc in ["todos", "categories", "progress", "grades", "settings"] {
            try? await col.document(doc).delete()
        }
    }

    // MARK: - Private helpers

    private func encodeToArray<T: Encodable>(_ items: [T]) -> [[String: Any]] {
        guard let data = try? encoder.encode(items),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return array
    }

    private func loadArray<T: Decodable>(from docRef: DocumentReference) async -> [T]? {
        guard let snapshot = try? await docRef.getDocument(),
              snapshot.exists,
              let data = snapshot.data(),
              let items = data["items"] else { return nil }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: items) else { return nil }
        return try? decoder.decode([T].self, from: jsonData)
    }
}
