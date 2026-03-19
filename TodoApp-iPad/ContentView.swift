import SwiftUI

// MARK: - Sidebar Navigation Item

enum SidebarItem: String, CaseIterable, Identifiable {
    case aufgaben      = "Aufgaben"
    case stundenplan   = "Stundenplan"
    case klausuren     = "Klausuren"
    case module        = "Moodle"
    case webmail       = "Webmail"
    case fortschritt   = "Lernfortschritt"
    case statistik     = "Statistik"
    case noten         = "Noten"
    case einstellungen = "Einstellungen"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .aufgaben:      return "checklist"
        case .stundenplan:   return "calendar"
        case .klausuren:     return "clock.badge.exclamationmark"
        case .module:        return "book.closed.fill"
        case .webmail:       return "envelope.fill"
        case .fortschritt:   return "book.pages.fill"
        case .statistik:     return "chart.bar.fill"
        case .noten:         return "graduationcap.fill"
        case .einstellungen: return "gearshape"
        }
    }

    var section: SidebarSection {
        switch self {
        case .aufgaben, .stundenplan, .klausuren, .module, .webmail, .fortschritt:
            return .main
        case .statistik, .noten, .einstellungen:
            return .tools
        }
    }
}

enum SidebarSection: String, CaseIterable {
    case main  = "Übersicht"
    case tools = "Extras"
}

// MARK: - ContentView (iPad with NavigationSplitView)

struct ContentView: View {
    @StateObject private var viewModel         = TodoViewModel()
    @StateObject private var progressViewModel = SubjectProgressViewModel()
    @StateObject private var dualisViewModel   = DualisViewModel()
    @StateObject private var authManager       = AuthenticationManager.shared
    @State       private var icalService       = ICalService()

    @State var selectedItem: SidebarItem? = .aufgaben

    private static let sharedDefaults = UserDefaults(suiteName: PersistenceManager.appGroupID)
    @AppStorage("todoapp_appearance", store: ContentView.sharedDefaults) private var appearanceRaw = "system"

    private var preferredColorScheme: ColorScheme? {
        AppearanceMode(rawValue: appearanceRaw)?.colorScheme
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .environmentObject(viewModel)
        .environmentObject(progressViewModel)
        .environmentObject(dualisViewModel)
        .environmentObject(authManager)
        .preferredColorScheme(preferredColorScheme)
        .onOpenURL { url in
            handleDeepLink(url)
        }
    }

    private func handleDeepLink(_ url: URL) {
        // Handle Google Sign-In URLs
        if url.scheme?.starts(with: "com.googleusercontent") == true {
            return
        }
        // Handle widget deep links: todoapp://aufgaben, todoapp://aufgaben/neu, todoapp://stundenplan
        guard url.scheme == "todoapp", let host = url.host else { return }
        switch host {
        case "aufgaben":
            selectedItem = .aufgaben
            if url.path == "/neu" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(name: .openAddTodo, object: nil)
                }
            }
        case "stundenplan":   selectedItem = .stundenplan
        default: break
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedItem) {
            Section("Übersicht") {
                ForEach([SidebarItem.aufgaben, .stundenplan, .klausuren, .module, .webmail, .fortschritt]) { item in
                    Label(item.rawValue, systemImage: item.icon)
                        .tag(item)
                }
            }

            Section("Extras") {
                ForEach([SidebarItem.statistik, .noten, .einstellungen]) { item in
                    Label(item.rawValue, systemImage: item.icon)
                        .tag(item)
                }
            }

        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func sidebarRow(_ item: SidebarItem) -> some View {
        if item == .noten, let gpa = dualisViewModel.gradeData?.overallGPA {
            HStack {
                Label(item.rawValue, systemImage: item.icon)
                Spacer()
                Text(String(format: "%.2f", gpa).replacingOccurrences(of: ".", with: ","))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(.systemFill), in: Capsule())
            }
        } else {
            Label(item.rawValue, systemImage: item.icon)
        }
    }

    private var accountStatusRow: some View {
        Group {
            if authManager.isSignedIn {
                HStack(spacing: 10) {
                    if let photoURL = authManager.photoURL {
                        AsyncImage(url: photoURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .frame(width: 28, height: 28)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(authManager.displayName ?? "Angemeldet")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("Cloud Sync aktiv")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
            } else {
                Label("Nicht angemeldet", systemImage: "person.crop.circle.badge.questionmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Detail View

    @ViewBuilder
    private var detailView: some View {
        switch selectedItem {
        case .aufgaben:
            NavigationStack {
                TodoListView()
            }

        case .stundenplan:
            NavigationStack {
                WeekCalendarView(service: icalService)
            }

        case .klausuren:
            NavigationStack {
                ExamCounterView(service: icalService)
            }

        case .module:
            NavigationStack {
                MoodleView()
            }

        case .webmail:
            NavigationStack {
                WebmailView()
            }

        case .fortschritt:
            NavigationStack {
                LernfortschrittView()
                    .environmentObject(progressViewModel)
            }

        case .statistik:
            NavigationStack {
                StatsView()
            }

        case .noten:
            NavigationStack {
                GradesView()
            }

        case .einstellungen:
            NavigationStack {
                SettingsView(icalService: icalService)
                    .environmentObject(dualisViewModel)
                    .environmentObject(authManager)
            }

        case .none:
            NavigationStack {
                VStack(spacing: 16) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 64))
                        .foregroundStyle(.tertiary)
                    Text("Wähle einen Bereich")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
