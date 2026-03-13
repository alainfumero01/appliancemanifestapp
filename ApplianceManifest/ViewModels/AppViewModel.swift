import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published var session: UserSession?
    @Published var manifests: [Manifest] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var authMode: AuthMode = .signIn

    let backend: BackendServicing

    init(backend: BackendServicing? = nil) {
        if let backend {
            self.backend = backend
        } else {
            do {
                let environment = try AppEnvironment()
                self.backend = SupabaseBackendService(environment: environment)
            } catch {
                self.backend = PreviewBackendService(error: error.localizedDescription)
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func bootstrap() async {
        isLoading = true
        defer { isLoading = false }
        session = await backend.restoreSession()
        if session != nil {
            await refreshManifests()
        }
    }

    func signIn(email: String, password: String) async {
        await performAuth {
            try await backend.signIn(email: email, password: password)
        }
    }

    func signUp(email: String, password: String, inviteCode: String) async {
        await performAuth {
            try await backend.signUp(email: email, password: password, inviteCode: inviteCode)
        }
    }

    func signOut() async {
        await backend.signOut()
        session = nil
        manifests = []
    }

    func refreshManifests() async {
        isLoading = true
        defer { isLoading = false }
        do {
            manifests = try await backend.fetchManifests()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addManifest(title: String, loadReference: String, items: [DraftManifestItem]) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            let manifest = try await backend.createManifest(title: title, loadReference: loadReference, draftItems: items)
            manifests.insert(manifest, at: 0)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func saveManifest(_ manifest: Manifest) async {
        do {
            let updated = try await backend.updateManifest(manifest)
            if let index = manifests.firstIndex(where: { $0.id == updated.id }) {
                manifests[index] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteItems(_ items: [ManifestItem], from manifest: Manifest) async {
        do {
            let updated = try await backend.deleteItems(items, from: manifest)
            if let index = manifests.firstIndex(where: { $0.id == updated.id }) {
                manifests[index] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performAuth(_ action: () async throws -> UserSession) async {
        isLoading = true
        defer { isLoading = false }
        do {
            session = try await action()
            await refreshManifests()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum AuthMode: String, CaseIterable, Identifiable {
    case signIn
    case signUp

    var id: String { rawValue }
}

@MainActor
final class PreviewBackendService: BackendServicing {
    private let error: String?

    init(error: String? = nil) {
        self.error = error
    }

    func restoreSession() async -> UserSession? { nil }
    func signIn(email: String, password: String) async throws -> UserSession { throw AppError.lookupFailed(error ?? "Configure Supabase to sign in.") }
    func signUp(email: String, password: String, inviteCode: String) async throws -> UserSession { throw AppError.lookupFailed(error ?? "Configure Supabase to sign up.") }
    func signOut() async {}
    func fetchManifests() async throws -> [Manifest] { [] }
    func createManifest(title: String, loadReference: String, draftItems: [DraftManifestItem]) async throws -> Manifest { throw AppError.lookupFailed("Configure Supabase before creating manifests.") }
    func updateManifest(_ manifest: Manifest) async throws -> Manifest { manifest }
    func deleteItems(_ items: [ManifestItem], from manifest: Manifest) async throws -> Manifest { manifest }
    func extractModelNumber(from imageData: Data) async throws -> String { throw AppError.lookupFailed("Scanning requires a configured iPhone target.") }
    func lookupProduct(modelNumber: String) async throws -> LookupSuggestion { throw AppError.lookupFailed("Lookup requires the Supabase Edge Function.") }
    func confirmProduct(_ suggestion: LookupSuggestion) async throws {}
    func exportManifest(_ manifest: Manifest) async throws -> ExportedManifest { try SpreadsheetExportService().export(manifest: manifest) }
}
