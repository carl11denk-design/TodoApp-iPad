import Foundation

@MainActor
final class SyncManager {
    static let shared = SyncManager()

    private let local = PersistenceManager.shared

    /// The active cloud backend — set based on auth provider
    private(set) var activeBackend: CloudBackendProtocol?

    private var isSyncing = false

    /// Flag to prevent listener from re-pushing data we just saved locally
    private(set) var isApplyingRemoteChange = false

    private var todosListener: Any?
    private var categoriesListener: Any?

    private init() {}

    // MARK: - Backend Selection

    func setBackend(for provider: AuthProvider) {
        stopListening()
        switch provider {
        case .google: activeBackend = FirestoreManager.shared
        case .apple:  activeBackend = CloudKitManager.shared
        case .none:   activeBackend = nil
        }
    }

    // MARK: - Initial Sync (called after sign-in)

    func performInitialSync() async {
        guard !isSyncing else { return }

        // Ensure backend is set based on current auth provider
        let provider = AuthenticationManager.shared.authProvider
        if activeBackend == nil { setBackend(for: provider) }

        guard let cloud = activeBackend else { return }

        isSyncing = true

        let hasCloud = await cloud.hasCloudData()

        if hasCloud {
            await pullFromCloud(cloud)
        } else {
            await pushToCloud(cloud)
        }

        isSyncing = false

        NotificationCenter.default.post(name: .syncDidComplete, object: nil)

        // Start listening for real-time changes from other devices
        startListening()
    }

    // MARK: - Real-time Listeners

    func startListening() {
        stopListening()

        guard AuthenticationManager.shared.isSignedIn,
              let cloud = activeBackend else { return }

        todosListener = cloud.listenToTodos { [weak self] remoteTodos in
            Task { @MainActor in
                self?.handleRemoteTodos(remoteTodos)
            }
        }

        categoriesListener = cloud.listenToCategories { [weak self] remoteCategories in
            Task { @MainActor in
                self?.handleRemoteCategories(remoteCategories)
            }
        }
    }

    func stopListening() {
        if let listener = todosListener {
            activeBackend?.removeListener(listener)
            todosListener = nil
        }
        if let listener = categoriesListener {
            activeBackend?.removeListener(listener)
            categoriesListener = nil
        }
    }

    private func handleRemoteTodos(_ remoteTodos: [Todo]) {
        guard !isApplyingRemoteChange else { return }

        let localTodos = local.loadTodos()

        // Skip if data is identical (our own write echoing back)
        if todosAreEqual(localTodos, remoteTodos) { return }

        isApplyingRemoteChange = true
        local.saveTodos(remoteTodos)
        isApplyingRemoteChange = false

        NotificationCenter.default.post(name: .syncDidComplete, object: nil)
    }

    private func handleRemoteCategories(_ remoteCategories: [Category]) {
        guard !isApplyingRemoteChange else { return }

        let localCategories = local.loadCategories()

        if categoriesAreEqual(localCategories, remoteCategories) { return }

        isApplyingRemoteChange = true
        local.saveCategories(remoteCategories)
        isApplyingRemoteChange = false

        NotificationCenter.default.post(name: .syncDidComplete, object: nil)
    }

    // MARK: - Comparison helpers

    private func todosAreEqual(_ a: [Todo], _ b: [Todo]) -> Bool {
        guard a.count == b.count else { return false }
        let aIDs = Set(a.map { "\($0.id)_\($0.isCompleted)_\($0.title)" })
        let bIDs = Set(b.map { "\($0.id)_\($0.isCompleted)_\($0.title)" })
        return aIDs == bIDs
    }

    private func categoriesAreEqual(_ a: [Category], _ b: [Category]) -> Bool {
        guard a.count == b.count else { return false }
        let aNames = Set(a.map { $0.name })
        let bNames = Set(b.map { $0.name })
        return aNames == bNames
    }

    // MARK: - Sync individual data types (called after every local save)

    func syncTodos(_ todos: [Todo]) {
        guard AuthenticationManager.shared.isSignedIn,
              !isApplyingRemoteChange,
              let cloud = activeBackend else { return }
        Task { await cloud.saveTodos(todos) }
    }

    func syncCategories(_ categories: [Category]) {
        guard AuthenticationManager.shared.isSignedIn,
              !isApplyingRemoteChange,
              let cloud = activeBackend else { return }
        Task { await cloud.saveCategories(categories) }
    }

    func syncSubjectProgress(_ subjects: [SubjectProgress]) {
        guard AuthenticationManager.shared.isSignedIn,
              let cloud = activeBackend else { return }
        Task { await cloud.saveSubjectProgress(subjects) }
    }

    func syncGrades(_ grades: DualisGradeData?) {
        guard AuthenticationManager.shared.isSignedIn,
              let cloud = activeBackend else { return }
        Task { await cloud.saveGrades(grades) }
    }

    func syncSettings(icalURL: String, appearance: String) {
        guard AuthenticationManager.shared.isSignedIn,
              let cloud = activeBackend else { return }
        Task { await cloud.saveSettings(icalURL: icalURL, appearance: appearance) }
    }

    // MARK: - Private: Pull all from cloud → local

    private func pullFromCloud(_ cloud: CloudBackendProtocol) async {
        if let todos = await cloud.loadTodos() {
            local.saveTodos(todos)
        }
        if let categories = await cloud.loadCategories() {
            local.saveCategories(categories)
        }
        if let subjects = await cloud.loadSubjectProgress() {
            local.saveSubjectProgress(subjects)
        }
        if let grades = await cloud.loadGrades() {
            local.saveGrades(grades)
        }
        if let settings = await cloud.loadSettings() {
            let defaults = UserDefaults(suiteName: PersistenceManager.appGroupID) ?? .standard
            defaults.set(settings.icalURL, forKey: "todoapp_ical_url")
            defaults.set(settings.appearance, forKey: "todoapp_appearance")
        }
    }

    // MARK: - Private: Push all local → cloud

    private func pushToCloud(_ cloud: CloudBackendProtocol) async {
        await cloud.saveTodos(local.loadTodos())
        await cloud.saveCategories(local.loadCategories())
        await cloud.saveSubjectProgress(local.loadSubjectProgress())
        await cloud.saveGrades(local.loadGrades())

        let defaults = UserDefaults(suiteName: PersistenceManager.appGroupID) ?? .standard
        let icalURL = defaults.string(forKey: "todoapp_ical_url") ?? ""
        let appearance = defaults.string(forKey: "todoapp_appearance") ?? "system"
        await cloud.saveSettings(icalURL: icalURL, appearance: appearance)
    }
}

// MARK: - Notification

extension Notification.Name {
    static let syncDidComplete = Notification.Name("syncDidComplete")
    static let openAddTodo = Notification.Name("openAddTodo")
}
