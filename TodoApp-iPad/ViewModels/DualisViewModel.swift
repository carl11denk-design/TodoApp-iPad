import Foundation
import SwiftUI

@MainActor
final class DualisViewModel: ObservableObject {
    @Published var gradeData: DualisGradeData?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var collapsedSemesters: Set<String> = []

    private let service = DualisService.shared
    private let persistence = PersistenceManager.shared

    init() {
        migrateCredentialsIfNeeded()

        // Filter cached data: drop semesters before WiSe 2025/26
        if let cached = persistence.loadGrades() {
            let filtered = cached.semesters.filter { Self.isSemesterRelevant($0.name) }
            if filtered.count != cached.semesters.count {
                let cleaned = DualisGradeData(semesters: filtered, fetchedAt: cached.fetchedAt)
                persistence.saveGrades(cleaned)
                gradeData = cleaned
            } else {
                gradeData = cached
            }
        }
    }

    private static func isSemesterRelevant(_ name: String) -> Bool {
        let lower = name.lowercased()
        let yearPattern = try! NSRegularExpression(pattern: "(\\d{4})", options: [])
        let nsName = name as NSString
        let matches = yearPattern.matches(in: name, range: NSRange(location: 0, length: nsName.length))
        guard let firstYear = matches.compactMap({ Int(nsName.substring(with: $0.range(at: 1))) }).first else { return false }
        let isWinter = lower.contains("wi") || lower.contains("winter") || lower.contains("ws")
        if firstYear >= 2026 { return true }
        if firstYear == 2025 && isWinter { return true }
        return false
    }

    // MARK: - Credentials (stored in Keychain)

    var username: String {
        get { KeychainHelper.load(for: "dualis_username") ?? "" }
        set { KeychainHelper.save(newValue, for: "dualis_username") }
    }

    var password: String {
        get { KeychainHelper.load(for: "dualis_password") ?? "" }
        set { KeychainHelper.save(newValue, for: "dualis_password") }
    }

    /// Migrate credentials from UserDefaults to Keychain (one-time)
    private func migrateCredentialsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "dualis_keychain_migrated") else { return }

        if let oldUser = UserDefaults.standard.string(forKey: "dualis_username"), !oldUser.isEmpty {
            KeychainHelper.save(oldUser, for: "dualis_username")
            UserDefaults.standard.removeObject(forKey: "dualis_username")
        }
        if let oldData = UserDefaults.standard.data(forKey: "dualis_password"),
           let oldPw = String(data: oldData, encoding: .utf8), !oldPw.isEmpty {
            KeychainHelper.save(oldPw, for: "dualis_password")
            UserDefaults.standard.removeObject(forKey: "dualis_password")
        }

        UserDefaults.standard.set(true, forKey: "dualis_keychain_migrated")
    }

    var hasCredentials: Bool {
        !username.isEmpty && !password.isEmpty
    }

    // MARK: - Actions

    func refreshGrades() async {
        guard hasCredentials else {
            errorMessage = "Bitte hinterlege deine DUALIS Zugangsdaten in den Einstellungen."
            return
        }

        isLoading = true
        errorMessage = nil
        // Clear cached data so we always show fresh results
        gradeData = nil

        do {
            try await service.login(username: username, password: password)
            let data = try await service.fetchGrades()
            gradeData = data
            persistence.saveGrades(data)
            SyncManager.shared.syncGrades(data)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func toggleSemester(_ name: String) {
        if collapsedSemesters.contains(name) {
            collapsedSemesters.remove(name)
        } else {
            collapsedSemesters.insert(name)
        }
    }

    func isSemesterCollapsed(_ name: String) -> Bool {
        collapsedSemesters.contains(name)
    }

    func clearGrades() {
        gradeData = nil
        persistence.saveGrades(nil)
    }
}
