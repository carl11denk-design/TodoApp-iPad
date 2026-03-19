import Foundation
import SwiftUI

class SubjectProgressViewModel: ObservableObject {
    @Published var subjects: [SubjectProgress] = []

    private let persistence = PersistenceManager.shared
    private var syncObserver: NSObjectProtocol?

    init() {
        load()
        syncObserver = NotificationCenter.default.addObserver(
            forName: .syncDidComplete, object: nil, queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
    }

    deinit {
        if let observer = syncObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - CRUD

    func add(_ subject: SubjectProgress) {
        subjects.append(subject)
        save()
    }

    func update(_ subject: SubjectProgress) {
        guard let i = subjects.firstIndex(where: { $0.id == subject.id }) else { return }
        subjects[i] = subject
        save()
    }

    func delete(_ subject: SubjectProgress) {
        subjects.removeAll { $0.id == subject.id }
        save()
    }

    // MARK: - Persistence

    private func save() {
        persistence.saveSubjectProgress(subjects)
        let currentSubjects = subjects
        Task { @MainActor in
            SyncManager.shared.syncSubjectProgress(currentSubjects)
        }
    }

    func reload() {
        subjects = persistence.loadSubjectProgress()
    }

    private func load() { reload() }
}
