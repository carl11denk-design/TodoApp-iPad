import Foundation
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import GoogleSignInSwift
import AuthenticationServices
import CryptoKit

@MainActor
final class AuthenticationManager: NSObject, ObservableObject {
    static let shared = AuthenticationManager()

    @Published var user: User?
    @Published var isSignedIn = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var authProvider: AuthProvider = .none

    var displayName: String? {
        switch authProvider {
        case .google: return user?.displayName
        case .apple:  return appleDisplayName ?? "Apple Benutzer"
        case .none:   return nil
        }
    }

    var email: String? {
        switch authProvider {
        case .google: return user?.email
        case .apple:  return appleEmail
        case .none:   return nil
        }
    }

    var photoURL: URL? { authProvider == .google ? user?.photoURL : nil }
    var uid: String? {
        switch authProvider {
        case .google: return user?.uid
        case .apple:  return appleUserID
        case .none:   return nil
        }
    }

    // Apple Sign-In state
    private var appleUserID: String? {
        get { UserDefaults.standard.string(forKey: "apple_user_id") }
        set { UserDefaults.standard.set(newValue, forKey: "apple_user_id") }
    }
    private var appleDisplayName: String? {
        get { UserDefaults.standard.string(forKey: "apple_display_name") }
        set { UserDefaults.standard.set(newValue, forKey: "apple_display_name") }
    }
    private var appleEmail: String? {
        get { UserDefaults.standard.string(forKey: "apple_email") }
        set { UserDefaults.standard.set(newValue, forKey: "apple_email") }
    }

    private var currentNonce: String?

    private override init() {
        super.init()
        restoreSession()
    }

    // MARK: - Session Restoration

    private func restoreSession() {
        let savedProvider = UserDefaults.standard.string(forKey: "auth_provider") ?? "none"

        switch savedProvider {
        case "google":
            if let currentUser = Auth.auth().currentUser {
                self.user = currentUser
                self.isSignedIn = true
                self.authProvider = .google
            }
        case "apple":
            if let userID = appleUserID {
                // Verify Apple credential is still valid
                let provider = ASAuthorizationAppleIDProvider()
                provider.getCredentialState(forUserID: userID) { [weak self] state, _ in
                    Task { @MainActor in
                        if state == .authorized {
                            self?.isSignedIn = true
                            self?.authProvider = .apple
                        } else {
                            // Credential revoked or not found
                            self?.clearAppleSession()
                        }
                    }
                }
            }
        default:
            break
        }
    }

    private func persistProvider(_ provider: AuthProvider) {
        authProvider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: "auth_provider")
    }

    // MARK: - Google Sign-In

    func signInWithGoogle() async {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            errorMessage = "Firebase nicht konfiguriert"
            return
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            errorMessage = "Kein Fenster gefunden"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
            guard let idToken = result.user.idToken?.tokenString else {
                errorMessage = "Kein Google Token erhalten"
                isLoading = false
                return
            }

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )

            let authResult = try await Auth.auth().signIn(with: credential)
            self.user = authResult.user
            self.isSignedIn = true
            persistProvider(.google)

            await SyncManager.shared.performInitialSync()
        } catch {
            errorMessage = "Anmeldung fehlgeschlagen: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Apple Sign-In

    func signInWithApple() {
        isLoading = true
        errorMessage = nil

        let nonce = randomNonceString()
        currentNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.performRequests()
    }

    private func handleAppleSignIn(credential: ASAuthorizationAppleIDCredential) async {
        // Store user info (only provided on first sign-in)
        appleUserID = credential.user

        if let fullName = credential.fullName {
            let name = [fullName.givenName, fullName.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            if !name.isEmpty { appleDisplayName = name }
        }
        if let email = credential.email {
            appleEmail = email
        }

        self.isSignedIn = true
        persistProvider(.apple)

        await SyncManager.shared.performInitialSync()

        isLoading = false
    }

    // MARK: - Sign Out

    func signOut() {
        SyncManager.shared.stopListening()

        switch authProvider {
        case .google:
            try? Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
        case .apple:
            // Apple doesn't have a "sign out" SDK call — just clear local state
            break
        case .none:
            break
        }

        self.user = nil
        self.isSignedIn = false
        persistProvider(.none)
    }

    // MARK: - Delete Account

    func deleteAccount() async {
        SyncManager.shared.stopListening()

        // Delete cloud data
        if let backend = SyncManager.shared.activeBackend {
            await backend.deleteAllData()
        }

        // Delete local data
        PersistenceManager.shared.clearAll()

        switch authProvider {
        case .google:
            try? await Auth.auth().currentUser?.delete()
            GIDSignIn.sharedInstance.signOut()
        case .apple:
            clearAppleSession()
        case .none:
            break
        }

        self.user = nil
        self.isSignedIn = false
        persistProvider(.none)
    }

    private func clearAppleSession() {
        appleUserID = nil
        appleDisplayName = nil
        appleEmail = nil
    }

    // MARK: - Nonce helpers for Apple Sign-In

    private func randomNonceString(length: Int = 32) -> String {
        var randomBytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthenticationManager: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
        Task { @MainActor in
            await handleAppleSignIn(credential: credential)
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithError error: Error) {
        Task { @MainActor in
            // Don't show error for user cancellation
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = "Apple-Anmeldung fehlgeschlagen: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }
}
