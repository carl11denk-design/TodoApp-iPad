import SwiftUI
import AuthenticationServices

// MARK: - Appearance Mode

enum AppearanceMode: String, CaseIterable {
    case system = "system"
    case light  = "light"
    case dark   = "dark"

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Hell"
        case .dark:   return "Dunkel"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    var icalService: ICalService
    @EnvironmentObject var dualisVM: DualisViewModel
    @EnvironmentObject var authManager: AuthenticationManager

    private static let sharedDefaults = UserDefaults(suiteName: PersistenceManager.appGroupID)
    @AppStorage("todoapp_ical_url",   store: SettingsView.sharedDefaults) private var icalURL       = ""
    @AppStorage("todoapp_appearance", store: SettingsView.sharedDefaults) private var appearanceRaw = "system"

    @State private var showLoadedToast = false
    @State private var isLoadingFromSettings = false
    @State private var dualisUsername = ""
    @State private var dualisPassword = ""
    @State private var showDualisPassword = false
    @State private var dualisSaveToast = false
    @State private var showDeleteAlert = false

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .system
    }

    var body: some View {
        Form {
            // MARK: Account
            Section {
                if authManager.isSignedIn {
                    HStack(spacing: 14) {
                        if let photoURL = authManager.photoURL {
                            AsyncImage(url: photoURL) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Image(systemName: "person.circle.fill")
                                    .resizable()
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 52, height: 52)
                            .clipShape(Circle())
                        } else {
                            Image(systemName: authManager.authProvider == .apple
                                  ? "applelogo" : "person.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: authManager.authProvider == .apple ? 36 : 52,
                                       height: authManager.authProvider == .apple ? 36 : 52)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(authManager.displayName ?? "Angemeldet")
                                .font(.headline)
                            if let email = authManager.email {
                                Text(email)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Text(authManager.authProvider == .apple
                                 ? "Synchronisiert über iCloud"
                                 : "Synchronisiert über Google")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 6)

                    Button(role: .destructive) {
                        authManager.signOut()
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Abmelden")
                        }
                    }

                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Account & Daten löschen")
                        }
                    }
                } else {
                    // Apple Sign-In
                    Button {
                        authManager.signInWithApple()
                    } label: {
                        HStack {
                            Image(systemName: "applelogo")
                            Text("Mit Apple anmelden")
                            Spacer()
                            if authManager.isLoading {
                                ProgressView().scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(authManager.isLoading)

                    // Google Sign-In
                    Button {
                        Task { await authManager.signInWithGoogle() }
                    } label: {
                        HStack {
                            Image(systemName: "person.badge.plus")
                            Text("Mit Google anmelden")
                            Spacer()
                            if authManager.isLoading && authManager.authProvider != .apple {
                                ProgressView().scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(authManager.isLoading)
                }

                if let error = authManager.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Label("Account", systemImage: "person.crop.circle")
            } footer: {
                if authManager.isSignedIn {
                    Text(authManager.authProvider == .apple
                         ? "Deine Daten werden über iCloud synchronisiert."
                         : "Deine Daten werden über Google Cloud synchronisiert.")
                } else {
                    Text("Melde dich an, um deine Daten geräteübergreifend zu synchronisieren. Apple nutzt iCloud, Google nutzt Firebase.")
                }
            }

            // MARK: Appearance
            Section {
                appearancePicker
            } header: {
                Label("Erscheinungsbild", systemImage: "paintpalette")
            } footer: {
                Text("Wähle zwischen dem System-Standard, dem hellen oder dem dunklen Modus.")
            }

            // MARK: iCal / Stundenplan
            Section {
                TextField("https://rapla.dhbw.de/rapla/…", text: $icalURL)
                    .textContentType(.URL)
                    .autocapitalization(.none)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()

                Button {
                    guard !icalURL.isEmpty else { return }
                    isLoadingFromSettings = true
                    Task {
                        await icalService.fetch(url: icalURL)
                        await MainActor.run {
                            isLoadingFromSettings = false
                            showLoadedToast       = true
                        }
                        try? await Task.sleep(for: .seconds(2))
                        showLoadedToast = false
                    }
                } label: {
                    HStack {
                        if isLoadingFromSettings {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: showLoadedToast ? "checkmark.circle.fill" : "arrow.clockwise")
                                .foregroundStyle(showLoadedToast ? .green : .blue)
                        }
                        Text(showLoadedToast ? "Geladen!" : "Stundenplan jetzt laden")
                            .foregroundStyle(showLoadedToast ? .green : .blue)
                    }
                }
                .disabled(icalURL.isEmpty || isLoadingFromSettings)

            } header: {
                Label("Stundenplan (iCal)", systemImage: "calendar")
            } footer: {
                Text("Deinen DHBW Vorlesungsplan-Link einfügen. Den Link findest du im Rapla-Portal unter \"Exportieren als iCal\".")
            }

            // MARK: DUALIS
            Section {
                TextField("E-Mail", text: $dualisUsername)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()

                HStack {
                    if showDualisPassword {
                        TextField("Passwort", text: $dualisPassword)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    } else {
                        SecureField("Passwort", text: $dualisPassword)
                    }
                    Button {
                        showDualisPassword.toggle()
                    } label: {
                        Image(systemName: showDualisPassword ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    dualisVM.username = dualisUsername
                    dualisVM.password = dualisPassword
                    dualisSaveToast = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        dualisSaveToast = false
                    }
                } label: {
                    HStack {
                        Image(systemName: dualisSaveToast ? "checkmark.circle.fill" : "square.and.arrow.down")
                            .foregroundStyle(dualisSaveToast ? .green : .blue)
                        Text(dualisSaveToast ? "Gespeichert!" : "Zugangsdaten speichern")
                            .foregroundStyle(dualisSaveToast ? .green : .blue)
                    }
                }
                .disabled(dualisUsername.isEmpty || dualisPassword.isEmpty)

            } header: {
                Label("DHBW Zugangsdaten (Dualis & Moodle)", systemImage: "graduationcap")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Deine DHBW-Anmeldedaten werden für den Notenabruf über Dualis und die automatische Anmeldung bei Moodle verwendet.")
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline)
                        Text("Deine Login-Daten werden ausschließlich lokal auf deinem Gerät gespeichert.")
                            .fontWeight(.semibold)
                    }
                }
            }

            // MARK: Info
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.square.fill")
                                .foregroundStyle(.blue)
                            Text("Aufgaben & Stundenplan")
                                .font(.headline)
                        }
                        Text("iPad Version 1.0")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)

                Text("Deine Daten werden lokal gespeichert. Mit Anmeldung optional auch in der Cloud (iCloud oder Google).")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            } header: {
                Label("Info", systemImage: "info.circle")
            }
        }
        .alert("Account löschen?", isPresented: $showDeleteAlert) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) {
                Task { await authManager.deleteAccount() }
            }
        } message: {
            Text("Alle deine Cloud-Daten und lokalen Daten werden unwiderruflich gelöscht.")
        }
        .onAppear {
            dualisUsername = dualisVM.username
            dualisPassword = dualisVM.password
        }
        .onChange(of: icalURL) { _, newValue in
            SyncManager.shared.syncSettings(icalURL: newValue, appearance: appearanceRaw)
        }
        .onChange(of: appearanceRaw) { _, newValue in
            SyncManager.shared.syncSettings(icalURL: icalURL, appearance: newValue)
        }
    }

    // MARK: - Appearance picker

    private var appearancePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                    appearanceOption(mode)
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        }
        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
    }

    private func appearanceOption(_ mode: AppearanceMode) -> some View {
        let isSelected = appearance == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                appearanceRaw = mode.rawValue
            }
        } label: {
            VStack(spacing: 6) {
                appearancePreview(mode: mode, selected: isSelected)
                Text(mode.label)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background(
                isSelected ? Color(.systemBackground).opacity(0.8) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .padding(3)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }

    private func appearancePreview(mode: AppearanceMode, selected: Bool) -> some View {
        let isDark = (mode == .dark) || (mode == .system && UITraitCollection.current.userInterfaceStyle == .dark)
        let bg        = isDark ? Color(red: 0.11, green: 0.11, blue: 0.12) : Color(red: 0.95, green: 0.95, blue: 0.97)
        let cardBg    = isDark ? Color(red: 0.18, green: 0.18, blue: 0.20) : Color.white
        let textColor = isDark ? Color.white : Color(red: 0.1, green: 0.1, blue: 0.1)
        let accent    = Color.blue

        return RoundedRectangle(cornerRadius: 8)
            .fill(bg)
            .frame(width: 80, height: 60)
            .overlay {
                VStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { i in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(i == 0 ? accent : textColor.opacity(0.2))
                                .frame(width: 6, height: 6)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(textColor.opacity(i == 0 ? 0.8 : 0.25))
                                .frame(height: 4)
                        }
                        .padding(.horizontal, 6)
                    }
                }
                .padding(6)
                .background(cardBg, in: RoundedRectangle(cornerRadius: 4))
                .padding(6)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.blue : Color(.separator), lineWidth: selected ? 2 : 0.5)
            }
    }
}
