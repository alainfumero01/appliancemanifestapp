import Foundation
import UIKit

@MainActor
protocol BackendServicing {
    func restoreSession() async -> UserSession?
    func signIn(email: String, password: String) async throws -> UserSession
    func signUp(email: String, password: String, inviteCode: String?) async throws -> UserSession
    func signInWithApple(identityToken: String, nonce: String) async throws -> UserSession
    func signOut() async
    func fetchEntitlement() async throws -> OrganizationEntitlement
    func createEnterpriseInviteLink() async throws -> EnterpriseInviteLink
    func listOrgMembers() async throws -> [OrganizationMember]
    func removeOrgMember(_ member: OrganizationMember) async throws
    func syncAppStoreSubscription(productID: String, transactionJWS: String?) async throws -> OrganizationEntitlement
    func fetchManifests() async throws -> [Manifest]
    func createManifest(title: String, loadReference: String, draftItems: [DraftManifestItem], loadCost: Decimal?, targetMarginPct: Decimal?) async throws -> Manifest
    func updateManifest(_ manifest: Manifest) async throws -> Manifest
    func deleteManifest(_ manifest: Manifest) async throws
    func deleteAllManifests() async throws
    func deleteItems(_ items: [ManifestItem], from manifest: Manifest) async throws -> Manifest
    func ingestSticker(imageData: Data) async throws -> LookupSuggestion
    func extractModelNumber(from imageData: Data) async throws -> String
    func lookupProduct(modelNumber: String) async throws -> LookupSuggestion
    func confirmProduct(_ suggestion: LookupSuggestion) async throws
    func updateItem(_ item: ManifestItem, in manifest: Manifest) async throws -> Manifest
    func exportManifest(_ manifest: Manifest) async throws -> ExportedManifest
    func sendSubscriptionEmail(plan: String) async
    func sendPasswordReset(email: String) async throws
    func joinOrgWithInvite(code: String) async throws -> OrganizationEntitlement
    func fetchInviteCodes() async throws -> [InviteCode]
}

final class SupabaseBackendService: BackendServicing {
    private let environment: AppEnvironment
    private let sessionStore: SessionStore
    private let httpClient: HTTPClient
    private let exportService = SpreadsheetExportService()
    private let ocrService = VisionOCRService()
    private var session: UserSession?

    init(environment: AppEnvironment, sessionStore: SessionStore = SessionStore(), httpClient: HTTPClient = HTTPClient()) {
        self.environment = environment
        self.sessionStore = sessionStore
        self.httpClient = httpClient
    }

    func restoreSession() async -> UserSession? {
        guard let stored = sessionStore.restore() else { return nil }
        guard let refreshToken = stored.refreshToken, !refreshToken.isEmpty else {
            sessionStore.clear()
            return nil
        }

        // Refresh the access token
        guard let tokenPair = try? await refreshAccessToken(refreshToken: refreshToken) else {
            sessionStore.clear()
            return nil
        }

        // Verify the session nonce hasn't been displaced by a login on another device
        if let storedNonce = stored.sessionNonce {
            let dbNonce = try? await fetchSessionNonce(
                token: tokenPair.accessToken,
                userID: stored.user.id
            )
            if dbNonce != storedNonce {
                sessionStore.clear()
                return nil
            }
        }

        let refreshed = UserSession(
            accessToken: tokenPair.accessToken,
            refreshToken: tokenPair.refreshToken ?? stored.refreshToken,
            user: stored.user,
            sessionNonce: stored.sessionNonce
        )
        session = refreshed
        sessionStore.save(refreshed)
        return refreshed
    }

    // Returns the raw token pair from Supabase's refresh endpoint.
    private func refreshAccessToken(refreshToken: String) async throws -> (accessToken: String, refreshToken: String?) {
        struct RequestBody: Encodable { let refresh_token: String }
        struct TokenResponse: Decodable { let access_token: String; let refresh_token: String? }

        let url = environment.supabaseURL.appending(path: "auth/v1/token")
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw AppError.invalidResponse
        }
        components.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]

        let response: TokenResponse = try await httpClient.send(
            to: try components.unwrapURL(),
            method: "POST",
            headers: anonHeaders,
            body: RequestBody(refresh_token: refreshToken)
        )
        return (response.access_token, response.refresh_token)
    }

    private func fetchSessionNonce(token: String, userID: UUID) async throws -> UUID? {
        struct ProfileNonce: Decodable { let session_nonce: UUID? }
        let url = environment.supabaseURL
            .appending(path: "rest/v1/profiles")
            .appending(queryItems: [
                URLQueryItem(name: "select", value: "session_nonce"),
                URLQueryItem(name: "id", value: "eq.\(userID.uuidString)"),
                URLQueryItem(name: "limit", value: "1")
            ])
        let records: [ProfileNonce] = try await httpClient.send(
            to: url, method: "GET",
            headers: authenticatedHeaders(token: token, prefer: nil)
        )
        return records.first?.session_nonce
    }

    func signIn(email: String, password: String) async throws -> UserSession {
        struct RequestBody: Encodable { let email: String; let password: String }

        let response: EdgeAuthResponse = try await httpClient.send(
            to: environment.functionsURL.appending(path: "sign-in"),
            method: "POST",
            headers: anonBearerHeaders,
            body: RequestBody(email: email, password: password)
        )
        let newSession = response.userSession
        session = newSession
        sessionStore.save(newSession)
        return newSession
    }

    func signUp(email: String, password: String, inviteCode: String?) async throws -> UserSession {
        // Always route through the edge function — it auto-confirms the account
        // (no email verification step) and handles both personal org creation and
        // enterprise invite joining in one call.
        struct Body: Encodable {
            let email: String
            let password: String
            let inviteCode: String?
        }
        let response: EdgeAuthResponse = try await httpClient.send(
            to: environment.functionsURL.appending(path: "sign-up-with-invite"),
            method: "POST",
            headers: anonBearerHeaders,
            body: Body(email: email, password: password, inviteCode: inviteCode)
        )
        let newSession = response.userSession
        session = newSession
        sessionStore.save(newSession)
        return newSession
    }

    func signInWithApple(identityToken: String, nonce: String) async throws -> UserSession {
        struct RequestBody: Encodable {
            let provider: String
            let id_token: String
            let nonce: String
        }

        guard var components = URLComponents(url: environment.supabaseURL.appending(path: "auth/v1/token"),
                                             resolvingAgainstBaseURL: false) else {
            throw AppError.invalidResponse
        }
        components.queryItems = [URLQueryItem(name: "grant_type", value: "id_token")]

        let response: DirectAuthResponse = try await httpClient.send(
            to: try components.unwrapURL(),
            method: "POST",
            headers: anonHeaders,
            body: RequestBody(provider: "apple", id_token: identityToken, nonce: nonce)
        )

        let newSession = try response.userSession

        // Rotate the session nonce and kick other devices, same as email sign-in.
        let finalSession = (try? await rotateNonce(for: newSession)) ?? newSession
        session = finalSession
        sessionStore.save(finalSession)
        return finalSession
    }

    func signOut() async {
        session = nil
        sessionStore.clear()
    }

    func fetchEntitlement() async throws -> OrganizationEntitlement {
        let session = try await requireSession()
        do {
            return try await httpClient.send(
                to: environment.functionsURL.appending(path: "current-entitlements"),
                method: "GET",
                headers: authenticatedHeaders(token: session.accessToken, prefer: nil)
            )
        } catch {
            // Edge function failed (network, cold start, JWT issue) — fall back to
            // counting real manifests so the limit still enforces correctly.
            let used = (try? await countManifests(session: session)) ?? 0
            return OrganizationEntitlement(
                orgID: session.user.orgID ?? session.user.id,
                organizationName: session.user.email,
                ownerID: session.user.id,
                subscriptionType: .individual,
                billingPlatform: .none,
                subscriptionStatus: .free,
                appStoreProductID: nil,
                subscriptionExpiresAt: nil,
                seatLimit: 1,
                extraSeats: 0,
                trialManifestLimit: 3,
                trialManifestsUsed: used,
                memberCount: 1,
                isOwner: true
            )
        }
    }

    func createEnterpriseInviteLink() async throws -> EnterpriseInviteLink {
        let session = try await requireSession()
        return try await httpClient.send(
            to: environment.functionsURL.appending(path: "create-enterprise-invite-link"),
            method: "POST",
            headers: authenticatedHeaders(token: session.accessToken, prefer: nil),
            body: EmptyRequest()
        )
    }

    func listOrgMembers() async throws -> [OrganizationMember] {
        let session = try await requireSession()
        return try await httpClient.send(
            to: environment.functionsURL.appending(path: "list-org-members"),
            method: "GET",
            headers: authenticatedHeaders(token: session.accessToken, prefer: nil)
        )
    }

    func removeOrgMember(_ member: OrganizationMember) async throws {
        struct RequestBody: Encodable { let memberID: UUID }
        let session = try await requireSession()
        _ = try await httpClient.send(
            to: environment.functionsURL.appending(path: "remove-org-member"),
            method: "POST",
            headers: authenticatedHeaders(token: session.accessToken, prefer: nil),
            body: RequestBody(memberID: member.id)
        ) as EmptyResponse
    }

    func syncAppStoreSubscription(productID: String, transactionJWS: String?) async throws -> OrganizationEntitlement {
        struct RequestBody: Encodable {
            let productID: String
            let transactionJWS: String?
        }

        let session = try await requireSession()
        return try await httpClient.send(
            to: environment.functionsURL.appending(path: "sync-app-store-subscription"),
            method: "POST",
            headers: authenticatedHeaders(token: session.accessToken, prefer: nil),
            body: RequestBody(productID: productID, transactionJWS: transactionJWS)
        )
    }

    func fetchManifests() async throws -> [Manifest] {
        let session = try await requireSession()
        let url = environment.supabaseURL.appending(path: "rest/v1/manifests")
        let headers = authenticatedHeaders(token: session.accessToken, prefer: nil)
        let records: [ManifestRecord] = try await httpClient.send(to: url, method: "GET", headers: headers)
        let items = try await fetchManifestItems()
        let itemsByManifest = Dictionary(grouping: items, by: \.manifestID)

        // Fetch owner emails for all unique owner IDs so each manifest shows who created it
        let ownerIDs = Array(Set(records.map { $0.owner_id }))
        let ownerEmails = (try? await fetchOwnerEmails(ownerIDs, session: session)) ?? [:]

        return records.map { record in
            record.makeManifest(
                items: itemsByManifest[record.id] ?? [],
                ownerEmail: ownerEmails[record.owner_id]
            )
        }
        .sorted(by: { $0.updatedAt > $1.updatedAt })
    }

    private func fetchOwnerEmails(_ ids: [UUID], session: UserSession) async throws -> [UUID: String] {
        guard !ids.isEmpty else { return [:] }
        let idList = ids.map { $0.uuidString }.joined(separator: ",")
        let url = environment.supabaseURL
            .appending(path: "rest/v1/profiles")
            .appending(queryItems: [
                URLQueryItem(name: "select", value: "id,email"),
                URLQueryItem(name: "id", value: "in.(\(idList))")
            ])
        struct ProfileEmail: Decodable { let id: UUID; let email: String? }
        let profiles: [ProfileEmail] = try await httpClient.send(
            to: url, method: "GET",
            headers: authenticatedHeaders(token: session.accessToken, prefer: nil)
        )
        return Dictionary(uniqueKeysWithValues: profiles.compactMap { p in
            guard let email = p.email else { return nil }
            return (p.id, email)
        })
    }

    func createManifest(title: String, loadReference: String, draftItems: [DraftManifestItem], loadCost: Decimal? = nil, targetMarginPct: Decimal? = nil) async throws -> Manifest {
        let session = try await requireSession()
        let entitlement = try await fetchEntitlement()
        guard entitlement.canCreateManifest else {
            throw AppError.paywallRequired("You've used your 3 free manifests. Upgrade to continue creating new loads.")
        }
        let manifestID = UUID()
        let now = Date()
        var uploadedPhotoPaths: [String] = []

        let manifestInsert = ManifestInsert(
            id: manifestID,
            title: title,
            load_reference: loadReference,
            status: ManifestStatus.draft.rawValue,
            org_id: session.user.orgID,
            created_at: now,
            updated_at: now,
            load_cost: loadCost,
            target_margin_pct: targetMarginPct
        )

        do {
            do {
                _ = try await httpClient.send(
                    to: environment.supabaseURL.appending(path: "rest/v1/manifests"),
                    method: "POST",
                    headers: authenticatedHeaders(token: session.accessToken, prefer: "return=representation"),
                    body: [manifestInsert]
                ) as [ManifestRecord]
            } catch {
                throw AppError.lookupFailed("Manifest insert failed: \(error.localizedDescription)")
            }

            var createdItems: [ManifestItem] = []
            for draft in draftItems {
                let normalized = ModelNumberNormalizer.normalize(draft.modelNumber)
                let suggestion = LookupSuggestion(
                    normalizedModelNumber: normalized,
                    productName: draft.productName,
                    msrp: Decimal(string: draft.msrpText) ?? 0,
                    source: draft.source.isEmpty ? "operator-confirmed" : draft.source,
                    confidence: draft.confidence,
                    status: .confirmed
                )

                // Best-effort catalog cache write — non-fatal if edge function isn't deployed.
                try? await confirmProduct(suggestion)

                let photoPath: String?
                if draft.imageData.isEmpty {
                    photoPath = nil
                } else {
                    do {
                        let path = try await uploadPhoto(data: draft.imageData, manifestID: manifestID, itemID: draft.id)
                        uploadedPhotoPaths.append(path)
                        photoPath = path
                    } catch {
                        throw AppError.lookupFailed("Photo upload failed for \(normalized): \(error.localizedDescription)")
                    }
                }

                let insert = ManifestItemInsert(
                    id: draft.id,
                    manifest_id: manifestID,
                    model_number: normalized,
                    product_name: draft.productName,
                    msrp: Decimal(string: draft.msrpText) ?? 0,
                    our_price: Decimal(string: draft.ourPriceText) ?? 0,
                    condition: draft.condition.rawValue,
                    quantity: draft.quantity,
                    photo_path: photoPath,
                    lookup_status: LookupStatus.confirmed.rawValue,
                    created_at: now
                )

                let records: [ManifestItemRecord]
                do {
                    records = try await httpClient.send(
                        to: environment.supabaseURL.appending(path: "rest/v1/manifest_items"),
                        method: "POST",
                        headers: authenticatedHeaders(token: session.accessToken, prefer: "return=representation"),
                        body: [insert]
                    )
                } catch {
                    throw AppError.lookupFailed("Manifest item insert failed for \(normalized): \(error.localizedDescription)")
                }

                if let item = records.first?.makeManifestItem() {
                    createdItems.append(item)
                }
            }

            if entitlement.subscriptionStatus != .active {
                try? await recordManifestSaveUsage()
            }

            return Manifest(
                id: manifestID,
                title: title,
                loadReference: loadReference,
                ownerID: session.user.id,
                orgID: session.user.orgID,
                createdAt: now,
                updatedAt: now,
                status: .draft,
                items: createdItems,
                loadCost: loadCost,
                targetMarginPct: targetMarginPct
            )
        } catch {
            if !uploadedPhotoPaths.isEmpty {
                try? await deletePhotos(at: uploadedPhotoPaths, token: session.accessToken)
            }
            try? await deleteManifestByID(manifestID, token: session.accessToken)
            throw error
        }
    }

    func updateManifest(_ manifest: Manifest) async throws -> Manifest {
        let session = try await requireSession()

        let update = ManifestUpdate(
            title: manifest.title,
            load_reference: manifest.loadReference,
            status: manifest.status.rawValue,
            updated_at: Date()
        )

        let url = environment.supabaseURL
            .appending(path: "rest/v1/manifests")
            .appending(queryItems: [URLQueryItem(name: "id", value: "eq.\(manifest.id.uuidString)")])

        _ = try await httpClient.send(
            to: url,
            method: "PATCH",
            headers: authenticatedHeaders(token: session.accessToken, prefer: "return=representation"),
            body: update
        ) as [ManifestRecord]

        return manifest
    }

    func deleteManifest(_ manifest: Manifest) async throws {
        let session = try await requireSession()
        let url = environment.supabaseURL
            .appending(path: "rest/v1/manifests")
            .appending(queryItems: [URLQueryItem(name: "id", value: "eq.\(manifest.id.uuidString)")])

        try await httpClient.sendWithoutResponse(
            to: url,
            method: "DELETE",
            headers: authenticatedHeaders(token: session.accessToken, prefer: nil)
        )
    }

    func deleteAllManifests() async throws {
        let session = try await requireSession()
        let url = environment.supabaseURL
            .appending(path: "rest/v1/manifests")
            .appending(queryItems: [URLQueryItem(name: "owner_id", value: "eq.\(session.user.id.uuidString)")])

        try await httpClient.sendWithoutResponse(
            to: url,
            method: "DELETE",
            headers: authenticatedHeaders(token: session.accessToken, prefer: nil)
        )
    }

    func deleteItems(_ items: [ManifestItem], from manifest: Manifest) async throws -> Manifest {
        guard !items.isEmpty else { return manifest }
        let session = try await requireSession()
        let ids = items.map(\.id.uuidString).joined(separator: ",")
        let url = environment.supabaseURL
            .appending(path: "rest/v1/manifest_items")
            .appending(queryItems: [URLQueryItem(name: "id", value: "in.(\(ids))")])

        try await httpClient.sendWithoutResponse(
            to: url,
            method: "DELETE",
            headers: authenticatedHeaders(token: session.accessToken, prefer: nil)
        )

        var copy = manifest
        copy.items.removeAll { item in items.contains(where: { $0.id == item.id }) }
        return copy
    }

    func ingestSticker(imageData: Data) async throws -> LookupSuggestion {
        struct IngestRequest: Encodable { let imageBase64: String }

        let smallData = Self.resizedJPEG(imageData, maxDimension: 768, compressionQuality: 0.55) ?? imageData
        return try await httpClient.send(
            to: environment.functionsURL.appending(path: "ingest-sticker"),
            method: "POST",
            headers: anonBearerHeaders,
            body: IngestRequest(imageBase64: smallData.base64EncodedString())
        )
    }

    func extractModelNumber(from imageData: Data) async throws -> String {
        // 1. Try fast on-device Vision OCR first
        if let raw = try? await ocrService.extractModelNumber(from: imageData) {
            let normalized = ModelNumberNormalizer.normalize(raw)
            if !normalized.isEmpty {
                return normalized
            }
        }

        // 2. Fall back to GPT-4o Vision when on-device OCR fails or produces nothing
        struct ExtractRequest: Encodable { let imageBase64: String }
        struct ExtractResponse: Decodable { let modelNumber: String }

        // Resize to max 1024px before encoding — full iPhone photos are 4–7MB
        // which causes connection timeouts. 1024px is plenty for reading sticker text.
        let smallData = Self.resizedJPEG(imageData, maxDimension: 768, compressionQuality: 0.55) ?? imageData

        _ = try await requireSession()
        let response: ExtractResponse = try await httpClient.send(
            to: environment.functionsURL.appending(path: "extract-model"),
            method: "POST",
            headers: anonBearerHeaders,
            body: ExtractRequest(imageBase64: smallData.base64EncodedString())
        )

        let normalized = ModelNumberNormalizer.normalize(response.modelNumber)
        guard !normalized.isEmpty else {
            throw AppError.ocrFailed
        }
        return normalized
    }

    func lookupProduct(modelNumber: String) async throws -> LookupSuggestion {
        struct RequestBody: Encodable {
            let modelNumber: String
        }

        let session = try await requireSession()
        let normalized = ModelNumberNormalizer.normalize(modelNumber)

        if let cached = try await fetchCatalogSuggestion(normalizedModelNumber: normalized, token: session.accessToken) {
            return cached
        }

        return try await httpClient.send(
            to: environment.functionsURL.appending(path: "lookup-product"),
            method: "POST",
            headers: anonBearerHeaders,
            body: RequestBody(modelNumber: normalized)
        )
    }

    func confirmProduct(_ suggestion: LookupSuggestion) async throws {
        struct ConfirmProductRequest: Encodable {
            let normalizedModelNumber: String
            let productName: String
            let msrp: Decimal
            let source: String
            let confidence: Double
        }

        _ = try await requireSession()
        let payload = ConfirmProductRequest(
            normalizedModelNumber: suggestion.normalizedModelNumber,
            productName: suggestion.productName,
            msrp: suggestion.msrp,
            source: suggestion.source,
            confidence: suggestion.confidence
        )

        _ = try await httpClient.send(
            to: environment.functionsURL.appending(path: "confirm-product"),
            method: "POST",
            headers: anonBearerHeaders,
            body: payload
        ) as LookupSuggestion
    }

    func updateItem(_ item: ManifestItem, in manifest: Manifest) async throws -> Manifest {
        let session = try await requireSession()

        let update = ManifestItemUpdate(
            model_number: item.modelNumber,
            product_name: item.productName,
            msrp: item.msrp,
            our_price: item.ourPrice,
            condition: item.condition.rawValue,
            quantity: item.quantity
        )

        let url = environment.supabaseURL
            .appending(path: "rest/v1/manifest_items")
            .appending(queryItems: [URLQueryItem(name: "id", value: "eq.\(item.id.uuidString)")])

        _ = try await httpClient.send(
            to: url,
            method: "PATCH",
            headers: authenticatedHeaders(token: session.accessToken, prefer: "return=representation"),
            body: update
        ) as [ManifestItemRecord]

        var updated = manifest
        if let index = updated.items.firstIndex(where: { $0.id == item.id }) {
            updated.items[index] = item
        }
        return updated
    }

    func exportManifest(_ manifest: Manifest) async throws -> ExportedManifest {
        try exportService.export(manifest: manifest)
    }

    func joinOrgWithInvite(code: String) async throws -> OrganizationEntitlement {
        struct Body: Encodable { let inviteCode: String }
        let session = try await requireSession()
        // Use anonBearerHeaders so the gateway accepts the request regardless
        // of whether the user's access token has expired. The user token is
        // passed in X-User-Token so the function can verify it via getUser().
        var headers = anonBearerHeaders
        headers["X-User-Token"] = session.accessToken
        return try await httpClient.send(
            to: environment.functionsURL.appending(path: "join-org-with-invite"),
            method: "POST",
            headers: headers,
            body: Body(inviteCode: code)
        )
    }

    func fetchInviteCodes() async throws -> [InviteCode] {
        let session = try await requireSession()
        struct Row: Decodable {
            let id: UUID
            let code: String
            let is_active: Bool
            let usage_count: Int
            let usage_limit: Int?
        }
        let url = environment.supabaseURL
            .appending(path: "rest/v1/invite_codes")
            .appending(queryItems: [
                URLQueryItem(name: "select", value: "id,code,is_active,usage_count,usage_limit"),
                URLQueryItem(name: "order",  value: "created_at.asc")
            ])
        let rows: [Row] = try await httpClient.send(
            to: url, method: "GET",
            headers: authenticatedHeaders(token: session.accessToken, prefer: nil)
        )
        return rows.map {
            InviteCode(id: $0.id, code: $0.code, isActive: $0.is_active,
                       usageCount: $0.usage_count, usageLimit: $0.usage_limit)
        }
    }

    func sendSubscriptionEmail(plan: String) async {
        guard let session = try? await requireSession() else { return }
        struct Body: Encodable { let plan: String }
        _ = try? await httpClient.send(
            to: environment.functionsURL.appending(path: "send-subscription-email"),
            method: "POST",
            headers: authenticatedHeaders(token: session.accessToken, prefer: nil),
            body: Body(plan: plan)
        ) as EmptyResponse
    }

    func sendPasswordReset(email: String) async throws {
        struct Body: Encodable { let email: String }
        _ = try await httpClient.send(
            to: environment.functionsURL.appending(path: "send-password-reset"),
            method: "POST",
            headers: anonBearerHeaders,
            body: Body(email: email)
        ) as EmptyResponse
    }

    private func uploadPhoto(data: Data, manifestID: UUID, itemID: UUID) async throws -> String {
        let session = try await requireSession()
        let objectPath = "stickers/\(manifestID.uuidString)/\(itemID.uuidString).jpg"
        let url = environment.supabaseURL.appending(path: "storage/v1/object/sticker-photos/\(objectPath)")

        try await httpClient.sendRaw(
            to: url,
            method: "POST",
            headers: authenticatedHeaders(
                token: session.accessToken,
                prefer: nil,
                contentType: "image/jpeg"
            ),
            body: data
        )

        return objectPath
    }

    private func fetchManifestItems() async throws -> [ManifestItem] {
        let session = try await requireSession()
        let url = environment.supabaseURL.appending(path: "rest/v1/manifest_items")
        let records: [ManifestItemRecord] = try await httpClient.send(
            to: url,
            method: "GET",
            headers: authenticatedHeaders(token: session.accessToken, prefer: nil)
        )

        return records.map { $0.makeManifestItem() }
    }

    private func rotateNonce(for existing: UserSession) async throws -> UserSession {
        struct RotateResponse: Decodable { let session_nonce: UUID; let org_id: UUID? }
        let response: RotateResponse = try await httpClient.send(
            to: environment.functionsURL.appending(path: "rotate-session-nonce"),
            method: "POST",
            headers: authenticatedHeaders(token: existing.accessToken, prefer: nil),
            body: EmptyRequest()
        )
        return UserSession(
            accessToken: existing.accessToken,
            refreshToken: existing.refreshToken,
            user: AppUser(id: existing.user.id, email: existing.user.email, orgID: response.org_id ?? existing.user.orgID),
            sessionNonce: response.session_nonce
        )
    }

    private func countManifests(session: UserSession) async throws -> Int {
        struct IDOnly: Decodable { let id: UUID }
        let url = environment.supabaseURL
            .appending(path: "rest/v1/manifests")
            .appending(queryItems: [URLQueryItem(name: "select", value: "id")])
        let records: [IDOnly] = try await httpClient.send(
            to: url, method: "GET",
            headers: authenticatedHeaders(token: session.accessToken, prefer: nil)
        )
        return records.count
    }

    private func requireSession() async throws -> UserSession {
        guard let current = session else { throw AppError.unauthenticated }

        guard let refreshToken = current.refreshToken, !refreshToken.isEmpty else {
            return current
        }

        guard let tokenPair = try? await refreshAccessToken(refreshToken: refreshToken) else {
            return current
        }

        let refreshed = UserSession(
            accessToken: tokenPair.accessToken,
            refreshToken: tokenPair.refreshToken ?? current.refreshToken,
            user: current.user,
            sessionNonce: current.sessionNonce
        )
        session = refreshed
        sessionStore.save(refreshed)
        return refreshed
    }

    private func fetchCatalogSuggestion(normalizedModelNumber: String, token: String) async throws -> LookupSuggestion? {
        let url = environment.supabaseURL
            .appending(path: "rest/v1/product_catalog")
            .appending(queryItems: [
                URLQueryItem(name: "select", value: "normalized_model_number,product_name,msrp,source,confidence"),
                URLQueryItem(name: "normalized_model_number", value: "eq.\(normalizedModelNumber)"),
                URLQueryItem(name: "limit", value: "1")
            ])

        let records: [CatalogProductRecord] = try await httpClient.send(
            to: url,
            method: "GET",
            headers: authenticatedHeaders(token: token, prefer: nil)
        )

        guard let record = records.first else { return nil }
        return LookupSuggestion(
            normalizedModelNumber: record.normalized_model_number,
            productName: record.product_name,
            msrp: record.msrp,
            source: "catalog-cache",
            confidence: record.confidence,
            status: .cached
        )
    }

    private func recordManifestSaveUsage() async throws {
        let session = try await requireSession()
        _ = try await httpClient.send(
            to: environment.functionsURL.appending(path: "record-manifest-save"),
            method: "POST",
            headers: authenticatedHeaders(token: session.accessToken, prefer: nil),
            body: EmptyRequest()
        ) as OrganizationEntitlement
    }

    private func deleteManifestByID(_ manifestID: UUID, token: String) async throws {
        let url = environment.supabaseURL
            .appending(path: "rest/v1/manifests")
            .appending(queryItems: [URLQueryItem(name: "id", value: "eq.\(manifestID.uuidString)")])

        try await httpClient.sendWithoutResponse(
            to: url,
            method: "DELETE",
            headers: authenticatedHeaders(token: token, prefer: nil)
        )
    }

    private func deletePhotos(at paths: [String], token: String) async throws {
        for path in paths {
            let url = environment.supabaseURL.appending(path: "storage/v1/object/sticker-photos/\(path)")
            try? await httpClient.sendWithoutResponse(
                to: url,
                method: "DELETE",
                headers: authenticatedHeaders(token: token, prefer: nil)
            )
        }
    }

    private static func resizedJPEG(_ data: Data, maxDimension: CGFloat, compressionQuality: CGFloat) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1.0)
        let newSize = CGSize(width: max((size.width * scale).rounded(), 1), height: max((size.height * scale).rounded(), 1))
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        return resized.jpegData(compressionQuality: compressionQuality)
    }

    private var anonHeaders: [String: String] {
        [
            "Content-Type": "application/json",
            "apikey": environment.supabaseAnonKey
        ]
    }

    // Use the anon key as the Bearer token for edge functions.
    // The anon key is a long-lived valid JWT (expires 2033) that the platform
    // always accepts, unlike user access tokens which expire after 1 hour.
    private var anonBearerHeaders: [String: String] {
        [
            "Content-Type": "application/json",
            "apikey": environment.supabaseAnonKey,
            "Authorization": "Bearer \(environment.supabaseAnonKey)"
        ]
    }

    private func authenticatedHeaders(token: String, prefer: String?, contentType: String = "application/json") -> [String: String] {
        var headers = anonHeaders
        headers["Authorization"] = "Bearer \(token)"
        headers["Content-Type"] = contentType
        if let prefer {
            headers["Prefer"] = prefer
        }
        return headers
    }
}

private struct EmptyRequest: Encodable {}

/// Response from Supabase's built-in auth endpoints (/auth/v1/token, /auth/v1/signup).
private struct DirectAuthResponse: Decodable {
    let access_token: String?
    let refresh_token: String?
    let user: DirectUser?

    struct DirectUser: Decodable {
        let id: UUID
        let email: String?
    }

    var userSession: UserSession {
        get throws {
            guard let token = access_token, let user else {
                // sign-up with email confirmation enabled returns no session yet
                throw AppError.lookupFailed("Account created — check your email to confirm your address before signing in.")
            }
            return UserSession(
                accessToken: token,
                refreshToken: refresh_token,
                user: AppUser(id: user.id, email: user.email ?? "", orgID: nil),
                sessionNonce: nil
            )
        }
    }
}

/// Response from the custom sign-in / sign-up edge functions.
/// Includes the session nonce and org_id that the standard Supabase
/// auth endpoint does not return.
private struct EdgeAuthResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let session_nonce: UUID?
    let user: EdgeUser

    struct EdgeUser: Decodable {
        let id: UUID
        let email: String
        let org_id: UUID?
    }

    var userSession: UserSession {
        UserSession(
            accessToken: access_token,
            refreshToken: refresh_token,
            user: AppUser(id: user.id, email: user.email, orgID: user.org_id),
            sessionNonce: session_nonce
        )
    }
}

private struct ManifestRecord: Decodable {
    let id: UUID
    let title: String
    let load_reference: String
    let owner_id: UUID
    let org_id: UUID?
    let created_at: Date
    let updated_at: Date
    let status: String
    // These columns may not exist if the migration hasn't been run yet — decode safely.
    let load_cost: Decimal?
    let target_margin_pct: Decimal?

    enum CodingKeys: String, CodingKey {
        case id, title, load_reference, owner_id, org_id
        case created_at, updated_at, status
        case load_cost, target_margin_pct
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = try c.decode(UUID.self,   forKey: .id)
        title            = try c.decode(String.self, forKey: .title)
        load_reference   = try c.decode(String.self, forKey: .load_reference)
        owner_id         = try c.decode(UUID.self,   forKey: .owner_id)
        org_id           = try c.decodeIfPresent(UUID.self,   forKey: .org_id)
        created_at       = try c.decode(Date.self,   forKey: .created_at)
        updated_at       = try c.decode(Date.self,   forKey: .updated_at)
        status           = try c.decode(String.self, forKey: .status)
        load_cost         = try c.decodeIfPresent(Decimal.self, forKey: .load_cost)
        target_margin_pct = try c.decodeIfPresent(Decimal.self, forKey: .target_margin_pct)
    }

    func makeManifest(items: [ManifestItem], ownerEmail: String? = nil) -> Manifest {
        Manifest(
            id: id,
            title: title,
            loadReference: load_reference,
            ownerID: owner_id,
            ownerEmail: ownerEmail,
            orgID: org_id,
            createdAt: created_at,
            updatedAt: updated_at,
            status: ManifestStatus(rawValue: status) ?? .draft,
            items: items.sorted(by: { $0.createdAt < $1.createdAt }),
            loadCost: load_cost,
            targetMarginPct: target_margin_pct
        )
    }
}

private struct ManifestItemRecord: Decodable {
    let id: UUID
    let manifest_id: UUID
    let model_number: String
    let product_name: String
    let msrp: Decimal
    let our_price: Decimal?
    let condition: String?
    let quantity: Int
    let photo_path: String?
    let lookup_status: String
    let created_at: Date

    func makeManifestItem() -> ManifestItem {
        ManifestItem(
            id: id,
            manifestID: manifest_id,
            modelNumber: model_number,
            productName: product_name,
            msrp: msrp,
            ourPrice: our_price ?? 0,
            condition: ItemCondition(rawValue: condition ?? "") ?? .used,
            quantity: quantity,
            photoPath: photo_path,
            lookupStatus: LookupStatus(rawValue: lookup_status) ?? .pending,
            createdAt: created_at
        )
    }
}

private struct CatalogProductRecord: Decodable {
    let normalized_model_number: String
    let product_name: String
    let msrp: Decimal
    let confidence: Double
}

private struct ManifestInsert: Encodable {
    let id: UUID
    let title: String
    let load_reference: String
    let status: String
    let org_id: UUID?
    let created_at: Date
    let updated_at: Date
    let load_cost: Decimal?
    let target_margin_pct: Decimal?

    enum CodingKeys: String, CodingKey {
        case id, title, load_reference, status, org_id
        case created_at, updated_at
        case load_cost, target_margin_pct
    }

    // Skip nil optional fields so missing DB columns don't cause a 400 error.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,             forKey: .id)
        try c.encode(title,          forKey: .title)
        try c.encode(load_reference, forKey: .load_reference)
        try c.encode(status,         forKey: .status)
        try c.encode(created_at,     forKey: .created_at)
        try c.encode(updated_at,     forKey: .updated_at)
        try c.encodeIfPresent(org_id,            forKey: .org_id)
        try c.encodeIfPresent(load_cost,          forKey: .load_cost)
        try c.encodeIfPresent(target_margin_pct,  forKey: .target_margin_pct)
    }
}

private struct ManifestUpdate: Encodable {
    let title: String
    let load_reference: String
    let status: String
    let updated_at: Date
}

private struct ManifestItemUpdate: Encodable {
    let model_number: String
    let product_name: String
    let msrp: Decimal
    let our_price: Decimal
    let condition: String
    let quantity: Int
}

private struct ManifestItemInsert: Encodable {
    let id: UUID
    let manifest_id: UUID
    let model_number: String
    let product_name: String
    let msrp: Decimal
    let our_price: Decimal
    let condition: String
    let quantity: Int
    let photo_path: String?
    let lookup_status: String
    let created_at: Date
}

private extension URLComponents {
    func unwrapURL() throws -> URL {
        guard let url else { throw AppError.invalidResponse }
        return url
    }
}
