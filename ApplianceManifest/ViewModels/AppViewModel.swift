import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published var session: UserSession?
    @Published var manifests: [Manifest] = []
    @Published var entitlement: OrganizationEntitlement?
    @Published var orgMembers: [OrganizationMember] = []
    @Published var inviteLink: EnterpriseInviteLink?
    @Published var inviteCodes: [InviteCode] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var authMode: AuthMode = .signIn
    @Published var selectedTab: Int = 0

    let backend: BackendServicing

    init(backend: BackendServicing? = nil) {
        if let backend {
            self.backend = backend
        } else {
            do {
                let environment = try AppEnvironment()
                self.backend = SupabaseBackendService(environment: environment)
            } catch {
                self.backend = PreviewBackendService(error: error.userMessage)
                self.errorMessage = error.userMessage
            }
        }
    }

    func bootstrap() async {
        isLoading = true
        defer { isLoading = false }
        guard let stored = await backend.restoreSession() else { return }

        if biometricService.isEnabled && biometricService.canUseBiometrics {
            let passed = await biometricService.authenticate()
            guard passed else { return }
        }

        session = stored
        await refreshEntitlement()
        await refreshManifests()
    }

    let biometricService = BiometricService()

    func signIn(email: String, password: String) async {
        await performAuth {
            try await backend.signIn(email: email, password: password)
        }
    }

    func signUp(email: String, password: String, inviteCode: String?) async {
        await performAuth {
            try await backend.signUp(email: email, password: password, inviteCode: inviteCode)
        }
    }

    func signInWithApple(identityToken: String, nonce: String, inviteCode: String? = nil) async {
        await performAuth {
            try await backend.signInWithApple(identityToken: identityToken, nonce: nonce, inviteCode: inviteCode)
        }
    }

    func signInWithBiometrics() async {
        guard let stored = await backend.restoreSession() else {
            errorMessage = "No saved session found. Please sign in with your email."
            return
        }
        isLoading = true
        defer { isLoading = false }
        let passed = await biometricService.authenticate()
        if passed {
            session = stored
            await refreshManifests()
        }
    }

    func signOut() async {
        await backend.signOut()
        session = nil
        manifests = []
        entitlement = nil
        orgMembers = []
        inviteLink = nil
        inviteCodes = []
    }

    func refreshEntitlement() async {
        guard session != nil else { return }
        do {
            entitlement = try await backend.fetchEntitlement()
        } catch {
            present(error)
        }
    }

    func loadOrgMembers() async {
        do {
            orgMembers = try await backend.listOrgMembers()
        } catch {
            present(error)
        }
    }

    func generateInviteLink() async {
        do {
            _ = try await backend.createEnterpriseInviteLink()
            inviteLink = nil
            await loadInviteCodes()
            await loadOrgMembers()
            await refreshEntitlement()
        } catch {
            present(error)
        }
    }

    func removeOrgMember(_ member: OrganizationMember) async {
        do {
            try await backend.removeOrgMember(member)
            orgMembers.removeAll { $0.id == member.id }
            await refreshEntitlement()
            await loadInviteCodes()
        } catch {
            present(error)
        }
    }

    func loadInviteCodes() async {
        do { inviteCodes = try await backend.fetchInviteCodes() }
        catch { /* non-fatal — codes just won't show */ }
    }

    func joinOrgWithInvite(code: String) async throws -> OrganizationEntitlement {
        let result = try await backend.joinOrgWithInvite(code: code)
        entitlement = result
        await refreshManifests()
        return result
    }

    func sendSubscriptionEmail(plan: String) async {
        await backend.sendSubscriptionEmail(plan: plan)
    }

    func sendPasswordReset(email: String) async throws {
        try await backend.sendPasswordReset(email: email)
    }

    func appendDraftItems(_ draftItems: [DraftManifestItem], to manifest: Manifest) async -> Bool {
        do {
            let updated = try await backend.appendItems(draftItems, to: manifest)
            if let index = manifests.firstIndex(where: { $0.id == updated.id }) {
                manifests[index] = updated
            }
            return true
        } catch {
            present(error)
            return false
        }
    }

    func syncSubscription(productID: String, transactionJWS: String?) async {
        do {
            entitlement = try await backend.syncAppStoreSubscription(productID: productID, transactionJWS: transactionJWS)
            await refreshManifests()
            await loadInviteCodes()
            if entitlement?.isEnterprise == true {
                await loadOrgMembers()
            }
        } catch {
            present(error)
        }
    }

    func refreshManifests() async {
        isLoading = true
        defer { isLoading = false }
        do {
            manifests = try await backend.fetchManifests()
        } catch is CancellationError {
            // Pull-to-refresh task was cancelled by SwiftUI — not a real error.
        } catch let urlError as URLError where urlError.code == .cancelled {
            // URLSession cancellation from pull-to-refresh — not a real error.
        } catch {
            present(error)
        }
    }

    func addManifest(title: String, loadReference: String, items: [DraftManifestItem], loadCost: Decimal? = nil, targetMarginPct: Decimal? = nil) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            let manifest = try await backend.createManifest(title: title, loadReference: loadReference, draftItems: items, loadCost: loadCost, targetMarginPct: targetMarginPct)
            manifests.insert(manifest, at: 0)
            await refreshEntitlement()
            return true
        } catch {
            present(error)
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
            present(error)
        }
    }

    func deleteManifest(_ manifest: Manifest) async {
        do {
            try await backend.deleteManifest(manifest)
            manifests.removeAll { $0.id == manifest.id }
        } catch {
            present(error)
        }
    }

    func deleteAllManifests() async {
        do {
            try await backend.deleteAllManifests()
            manifests = []
        } catch {
            present(error)
        }
    }

    func updateItem(_ item: ManifestItem, in manifest: Manifest) async {
        do {
            let updated = try await backend.updateItem(item, in: manifest)
            if let index = manifests.firstIndex(where: { $0.id == updated.id }) {
                manifests[index] = updated
            }
        } catch {
            present(error)
        }
    }

    func deleteItems(_ items: [ManifestItem], from manifest: Manifest) async {
        do {
            let updated = try await backend.deleteItems(items, from: manifest)
            if let index = manifests.firstIndex(where: { $0.id == updated.id }) {
                manifests[index] = updated
            }
        } catch {
            present(error)
        }
    }

    private func performAuth(_ action: () async throws -> UserSession) async {
        isLoading = true
        defer { isLoading = false }
        do {
            session = try await action()
            if biometricService.canUseBiometrics {
                biometricService.isEnabled = true
            }
            await refreshEntitlement()
            await refreshManifests()
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        guard !error.isExpectedCancellation else { return }
        errorMessage = error.userMessage
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
    func signUp(email: String, password: String, inviteCode: String?) async throws -> UserSession { throw AppError.lookupFailed(error ?? "Configure Supabase to sign up.") }
    func signInWithApple(identityToken: String, nonce: String, inviteCode: String?) async throws -> UserSession { throw AppError.lookupFailed(error ?? "Configure Supabase to sign in with Apple.") }
    func signOut() async {}
    func fetchEntitlement() async throws -> OrganizationEntitlement { throw AppError.lookupFailed("Configure subscription entitlements before launch.") }
    func createEnterpriseInviteLink() async throws -> EnterpriseInviteLink { throw AppError.lookupFailed("Configure enterprise invites before launch.") }
    func listOrgMembers() async throws -> [OrganizationMember] { [] }
    func removeOrgMember(_ member: OrganizationMember) async throws {}
    func syncAppStoreSubscription(productID: String, transactionJWS: String?) async throws -> OrganizationEntitlement { throw AppError.lookupFailed("Configure StoreKit sync before launch.") }
    func fetchManifests() async throws -> [Manifest] { [] }
    func createManifest(title: String, loadReference: String, draftItems: [DraftManifestItem], loadCost: Decimal?, targetMarginPct: Decimal?) async throws -> Manifest { throw AppError.lookupFailed("Configure Supabase before creating manifests.") }
    func appendItems(_ draftItems: [DraftManifestItem], to manifest: Manifest) async throws -> Manifest { manifest }
    func updateManifest(_ manifest: Manifest) async throws -> Manifest { manifest }
    func deleteManifest(_ manifest: Manifest) async throws {}
    func deleteAllManifests() async throws {}
    func deleteItems(_ items: [ManifestItem], from manifest: Manifest) async throws -> Manifest { manifest }
    func ingestSticker(imageData: Data) async throws -> LookupSuggestion { throw AppError.lookupFailed("Scanning requires a configured iPhone target.") }
    func extractModelNumber(from imageData: Data) async throws -> String { throw AppError.lookupFailed("Scanning requires a configured iPhone target.") }
    func lookupProduct(modelNumber: String) async throws -> LookupSuggestion { throw AppError.lookupFailed("Lookup requires the Supabase Edge Function.") }
    func confirmProduct(_ suggestion: LookupSuggestion) async throws {}
    func updateItem(_ item: ManifestItem, in manifest: Manifest) async throws -> Manifest { manifest }
    func exportManifest(_ manifest: Manifest) async throws -> ExportedManifest { try SpreadsheetExportService().export(manifest: manifest) }
    func sendSubscriptionEmail(plan: String) async {}
    func sendPasswordReset(email: String) async throws {}
    func joinOrgWithInvite(code: String) async throws -> OrganizationEntitlement { throw AppError.lookupFailed("Not available in preview.") }
    func fetchInviteCodes() async throws -> [InviteCode] { [] }
}
