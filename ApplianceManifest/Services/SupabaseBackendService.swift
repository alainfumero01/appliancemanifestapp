import Foundation
import UIKit

@MainActor
protocol BackendServicing {
    func restoreSession() async -> UserSession?
    func signIn(email: String, password: String) async throws -> UserSession
    func signUp(email: String, password: String, inviteCode: String?) async throws -> UserSession
    func signInWithApple(identityToken: String, nonce: String, inviteCode: String?) async throws -> UserSession
    func signOut() async
    func fetchEntitlement() async throws -> OrganizationEntitlement
    func createEnterpriseInviteLink() async throws -> EnterpriseInviteLink
    func listOrgMembers() async throws -> [OrganizationMember]
    func removeOrgMember(_ member: OrganizationMember) async throws
    func syncAppStoreSubscription(productID: String, transactionJWS: String?) async throws -> OrganizationEntitlement
    func fetchManifests() async throws -> [Manifest]
    func fetchInventory() async throws -> [InventoryUnit]
    func createManifest(title: String, loadReference: String, draftItems: [DraftManifestItem], loadCost: Decimal?, targetMarginPct: Decimal?) async throws -> Manifest
    func appendItems(_ draftItems: [DraftManifestItem], to manifest: Manifest) async throws -> Manifest
    func updateManifest(_ manifest: Manifest) async throws -> Manifest
    func deleteManifest(_ manifest: Manifest) async throws
    func deleteAllManifests() async throws
    func deleteItems(_ items: [ManifestItem], from manifest: Manifest) async throws -> Manifest
    func ingestSticker(imageData: Data) async throws -> LookupSuggestion
    func extractModelNumber(from imageData: Data) async throws -> String
    func lookupProduct(modelNumber: String) async throws -> LookupSuggestion
    func confirmProduct(_ suggestion: LookupSuggestion, aliasModelNumbers: [String]) async throws
    func updateItem(_ item: ManifestItem, in manifest: Manifest) async throws -> Manifest
    func exportManifest(_ manifest: Manifest) async throws -> ExportedManifest
    func sendSubscriptionEmail(plan: String) async
    func sendPasswordReset(email: String) async throws
    func joinOrgWithInvite(code: String) async throws -> OrganizationEntitlement
    func fetchInviteCodes() async throws -> [InviteCode]
    func createInventoryUnits(from draft: DraftManifestItem, quantity: Int, askingPrice: Decimal, costBasis: Decimal?, status: InventoryStatus) async throws -> [InventoryUnit]
    func updateInventoryUnit(_ unit: InventoryUnit) async throws -> InventoryUnit
    func createQuickLoad(title: String, loadReference: String, inventoryUnitIDs: [UUID]) async throws -> Manifest
    func syncManifestInventory(manifestID: UUID?) async throws
    func syncLinkedInventoryStatus(manifestID: UUID) async throws
}

final class SupabaseBackendService: BackendServicing {
    private let environment: AppEnvironment
    private let sessionStore: SessionStore
    private let httpClient: HTTPClient
    private let exportService = SpreadsheetExportService()
    private let ocrService = VisionOCRService()
    private var session: UserSession?
    private var lookupSuggestionCache: [String: LookupSuggestion] = [:]

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
        lookupSuggestionCache.removeAll()
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
        lookupSuggestionCache.removeAll()
        session = newSession
        sessionStore.save(newSession)
        return newSession
    }

    func signInWithApple(identityToken: String, nonce: String, inviteCode: String?) async throws -> UserSession {
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
        var finalSession = (try? await rotateNonce(for: newSession)) ?? newSession
        if finalSession.user.orgID == nil {
            finalSession = try await bootstrapAppleAccount(for: finalSession, inviteCode: inviteCode)
        }
        lookupSuggestionCache.removeAll()
        session = finalSession
        sessionStore.save(finalSession)
        return finalSession
    }

    func signOut() async {
        lookupSuggestionCache.removeAll()
        session = nil
        sessionStore.clear()
    }

    func fetchEntitlement() async throws -> OrganizationEntitlement {
        let session = try await requireSession()
        do {
            var headers = anonBearerHeaders
            headers["X-User-Token"] = session.accessToken
            let entitlement: OrganizationEntitlement = try await httpClient.send(
                to: environment.functionsURL.appending(path: "current-entitlements"),
                method: "GET",
                headers: headers
            )
            syncCachedSessionOrgID(entitlement.orgID)
            return entitlement
        } catch {
            if error.isOrganizationAccessIssue {
                syncCachedSessionOrgID(nil)
            }
            // Edge function failed (network, cold start, JWT issue) — fall back to
            // counting real manifests so the limit still enforces correctly.
            let used = (try? await countManifests(session: session)) ?? 0
            return OrganizationEntitlement(
                orgID: self.session?.user.orgID ?? session.user.id,
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
        var headers = anonBearerHeaders
        headers["X-User-Token"] = session.accessToken
        return try await httpClient.send(
            to: environment.functionsURL.appending(path: "enterprise-invite-link"),
            method: "POST",
            headers: headers,
            body: EmptyRequest()
        )
    }

    func listOrgMembers() async throws -> [OrganizationMember] {
        let session = try await requireSession()
        var headers = anonBearerHeaders
        headers["X-User-Token"] = session.accessToken
        return try await httpClient.send(
            to: environment.functionsURL.appending(path: "list-org-members"),
            method: "GET",
            headers: headers
        )
    }

    func removeOrgMember(_ member: OrganizationMember) async throws {
        struct RequestBody: Encodable { let memberID: UUID }
        let session = try await requireSession()
        var headers = anonBearerHeaders
        headers["X-User-Token"] = session.accessToken
        _ = try await httpClient.send(
            to: environment.functionsURL.appending(path: "remove-org-member"),
            method: "POST",
            headers: headers,
            body: RequestBody(memberID: member.id)
        ) as EmptyResponse
    }

    func syncAppStoreSubscription(productID: String, transactionJWS: String?) async throws -> OrganizationEntitlement {
        struct RequestBody: Encodable {
            let productID: String
            let transactionJWS: String?
        }

        let session = try await requireSession()
        var headers = anonBearerHeaders
        headers["X-User-Token"] = session.accessToken
        return try await httpClient.send(
            to: environment.functionsURL.appending(path: "sync-app-store-subscription"),
            method: "POST",
            headers: headers,
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

    func fetchInventory() async throws -> [InventoryUnit] {
        let session = try await requireSession()
        let url = environment.supabaseURL
            .appending(path: "rest/v1/inventory_units")
            .appending(queryItems: [
                URLQueryItem(name: "select", value: InventoryUnitRecord.selectColumns),
                URLQueryItem(name: "order", value: "updated_at.desc")
            ])

        let records: [InventoryUnitRecord] = try await httpClient.send(
            to: url,
            method: "GET",
            headers: authenticatedHeaders(token: session.accessToken, prefer: nil)
        )
        return records.map { $0.makeInventoryUnit() }
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
                throw AppError.lookupFailed("We couldn't save this load right now. Please try again.")
            }

            let createdItems = try await insertManifestItems(
                draftItems,
                into: manifestID,
                createdAt: now,
                token: session.accessToken
            )

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
            if let recovery = try? await recoverManifestCreation(
                manifestID: manifestID,
                expectedDraftItems: draftItems,
                token: session.accessToken,
                ownerEmail: session.user.email
            ) {
                switch recovery {
                case .complete(let manifest):
                    return manifest
                case .partial(let manifest):
                    let cleaned = await cleanupPartialManifest(manifest, token: session.accessToken)
                    if cleaned {
                        throw AppError.lookupFailed("We hit a save issue and cleaned up the partial load. Please try again.")
                    }
                    throw AppError.lookupFailed("This load may have partially saved. Check My Loads before trying again.")
                case .missing:
                    break
                }
            }

            try? await deleteManifestByID(manifestID, token: session.accessToken)
            throw AppError.lookupFailed("We couldn't save this load right now. Please try again.")
        }
    }

    func appendItems(_ draftItems: [DraftManifestItem], to manifest: Manifest) async throws -> Manifest {
        guard !draftItems.isEmpty else { return manifest }

        let session = try await requireSession()
        let now = Date()
        let createdItems = try await insertManifestItems(
            draftItems,
            into: manifest.id,
            createdAt: now,
            token: session.accessToken
        )

        let update = ManifestUpdate(
            title: manifest.title,
            load_reference: manifest.loadReference,
            status: manifest.status.rawValue,
            updated_at: now
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

        var copy = manifest
        copy.updatedAt = now
        copy.items.append(contentsOf: createdItems)
        copy.items.sort(by: { $0.createdAt < $1.createdAt })
        return copy
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

    func createInventoryUnits(
        from draft: DraftManifestItem,
        quantity: Int,
        askingPrice: Decimal,
        costBasis: Decimal?,
        status: InventoryStatus
    ) async throws -> [InventoryUnit] {
        guard quantity > 0 else { return [] }

        let session = try await requireSession()
        let normalizedModel = ModelNumberNormalizer.normalize(draft.modelNumber)
        let trimmedName = draft.productName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedModel.isEmpty, !trimmedName.isEmpty else {
            throw AppError.lookupFailed("Confirm the model number and product name before saving inventory.")
        }

        if draft.lookupStatus == .confirmed || draft.lookupStatus == .cached {
            let suggestion = LookupSuggestion(
                normalizedModelNumber: normalizedModel,
                productName: trimmedName,
                brand: draft.brand,
                applianceCategory: draft.applianceCategory,
                msrp: Decimal(string: draft.msrpText) ?? 0,
                source: draft.source.isEmpty ? "operator-confirmed" : draft.source,
                confidence: draft.confidence,
                status: .confirmed
            )
            try? await confirmProduct(suggestion, aliasModelNumbers: aliasModelNumbers(for: draft))
        }

        let now = Date()
        let photoPath: String?
        if draft.imageData.isEmpty {
            photoPath = nil
        } else {
            photoPath = try await uploadInventoryPhoto(data: draft.imageData, sharedID: UUID())
        }

        do {
        let inserts = (0..<quantity).map { _ in
            InventoryUnitInsert(
                id: UUID(),
                org_id: session.user.orgID,
                source_manifest_id: nil,
                source_manifest_item_id: nil,
                source_manifest_item_index: nil,
                model_number: normalizedModel,
                product_name: trimmedName,
                brand: draft.brand?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
                appliance_category: draft.applianceCategory?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
                msrp: Decimal(string: draft.msrpText) ?? 0,
                asking_price: askingPrice,
                cost_basis: costBasis,
                sold_price: nil,
                condition: draft.condition.rawValue,
                status: status.rawValue,
                photo_path: photoPath,
                listed_at: status == .listed ? now : nil,
                reserved_at: status == .reserved ? now : nil,
                sold_at: status == .sold ? now : nil
            )
        }

        let records: [InventoryUnitRecord] = try await httpClient.send(
            to: environment.supabaseURL.appending(path: "rest/v1/inventory_units"),
            method: "POST",
            headers: authenticatedHeaders(token: session.accessToken, prefer: "return=representation"),
            body: inserts
        )
        return records.map { $0.makeInventoryUnit() }
        } catch {
            if let photoPath {
                try? await deletePhotos(at: [photoPath], token: session.accessToken)
            }
            throw error
        }
    }

    func updateInventoryUnit(_ unit: InventoryUnit) async throws -> InventoryUnit {
        let session = try await requireSession()
        let url = environment.supabaseURL
            .appending(path: "rest/v1/inventory_units")
            .appending(queryItems: [
                URLQueryItem(name: "id", value: "eq.\(unit.id.uuidString)"),
                URLQueryItem(name: "select", value: InventoryUnitRecord.selectColumns)
            ])

        let update = InventoryUnitUpdate(
            model_number: ModelNumberNormalizer.normalize(unit.modelNumber),
            product_name: unit.productName.trimmingCharacters(in: .whitespacesAndNewlines),
            brand: unit.brand?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            appliance_category: unit.applianceCategory?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            msrp: unit.msrp,
            asking_price: unit.askingPrice,
            cost_basis: unit.costBasis,
            sold_price: unit.soldPrice,
            condition: unit.condition.rawValue,
            status: unit.status.rawValue,
            photo_path: unit.photoPath,
            listed_at: unit.status == .listed ? (unit.listedAt ?? Date()) : nil,
            reserved_at: unit.status == .reserved ? (unit.reservedAt ?? Date()) : nil,
            sold_at: unit.status == .sold ? (unit.soldAt ?? Date()) : nil
        )

        let records: [InventoryUnitRecord] = try await httpClient.send(
            to: url,
            method: "PATCH",
            headers: authenticatedHeaders(token: session.accessToken, prefer: "return=representation"),
            body: update
        )

        guard let record = records.first else {
            throw AppError.lookupFailed("We couldn't update that inventory unit right now.")
        }
        return record.makeInventoryUnit()
    }

    func createQuickLoad(title: String, loadReference: String, inventoryUnitIDs: [UUID]) async throws -> Manifest {
        let session = try await requireSession()
        let selectedUnits = try await fetchInventoryUnits(ids: inventoryUnitIDs, token: session.accessToken)
        guard selectedUnits.count == inventoryUnitIDs.count else {
            throw AppError.lookupFailed("Some selected inventory units were not found.")
        }
        guard selectedUnits.allSatisfy(\.isAvailableForQuickLoad) else {
            throw AppError.lookupFailed("Only in-stock or listed inventory can be added to a quick load.")
        }

        let manifestID = UUID()
        let now = Date()
        let resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Inventory Load" : title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLoadReference = loadReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "LOAD-\(Int(now.timeIntervalSince1970))"
            : loadReference.trimmingCharacters(in: .whitespacesAndNewlines)

        struct QuickLoadRequest: Encodable {
            let manifestID: UUID
            let title: String
            let loadReference: String
            let inventoryUnitIDs: [UUID]
        }

        struct QuickLoadResponse: Decodable {
            let manifestID: UUID
            let manifestItemCount: Int
            let reservedUnitCount: Int
        }

        do {
            var headers = anonBearerHeaders
            headers["X-User-Token"] = session.accessToken
            _ = try await httpClient.send(
                to: environment.functionsURL.appending(path: "create-quick-load"),
                method: "POST",
                headers: headers,
                body: QuickLoadRequest(
                    manifestID: manifestID,
                    title: resolvedTitle,
                    loadReference: resolvedLoadReference,
                    inventoryUnitIDs: inventoryUnitIDs
                )
            ) as QuickLoadResponse
        } catch {
            if let recoveredRecord = try? await fetchManifestRecord(id: manifestID, token: session.accessToken),
               let recoveredItems = try? await fetchManifestItems(manifestID: manifestID, token: session.accessToken) {
                return recoveredRecord.makeManifest(items: recoveredItems, ownerEmail: session.user.email)
            }
            throw error
        }

        guard let manifestRecord = try await fetchManifestRecord(id: manifestID, token: session.accessToken) else {
            throw AppError.lookupFailed("The quick load was created, but we couldn't load it yet.")
        }
        let items = try await fetchManifestItems(manifestID: manifestID, token: session.accessToken)
        return manifestRecord.makeManifest(items: items, ownerEmail: session.user.email)
    }

    func syncManifestInventory(manifestID: UUID?) async throws {
        let session = try await requireSession()
        let manifests = try await fetchManifests()
        let manifestsToSync: [Manifest]
        if let manifestID {
            manifestsToSync = manifests.filter { $0.id == manifestID }
        } else {
            manifestsToSync = manifests
        }

        let existingUnits = try await fetchInventoryUnits(ids: nil, token: session.accessToken)
        let existingUnitMap: [String: InventoryUnit] = Dictionary(uniqueKeysWithValues: existingUnits.compactMap { unit in
            guard let itemID = unit.sourceManifestItemID,
                  let index = unit.sourceManifestItemIndex else { return nil }
            return ("\(itemID.uuidString):\(index)", unit)
        })

        for manifest in manifestsToSync {
            let totalMSRP = manifest.items.reduce(0) { $0 + ($1.msrp * Decimal($1.quantity)) }
            for item in manifest.items {
                let derivedBrand = item.brand?.nilIfBlank ?? deriveBrand(from: item.productName)
                let derivedCategory = item.applianceCategory?.nilIfBlank ?? deriveApplianceCategory(from: item.productName)
                let itemMSRPTotal = item.msrp * Decimal(item.quantity)
                let unitCostBasis: Decimal?
                if let loadCost = manifest.loadCost, totalMSRP > 0, item.quantity > 0 {
                    unitCostBasis = (loadCost * (itemMSRPTotal / totalMSRP)) / Decimal(item.quantity)
                } else {
                    unitCostBasis = nil
                }

                for index in 0..<item.quantity {
                    let key = "\(item.id.uuidString):\(index)"
                    if let existing = existingUnitMap[key] {
                        var update = InventoryUnitPartialUpdate()
                        if existing.brand?.nilIfBlank == nil, let derivedBrand {
                            update.brand = derivedBrand
                        }
                        if existing.applianceCategory?.nilIfBlank == nil, let derivedCategory {
                            update.appliance_category = derivedCategory
                        }
                        if existing.askingPrice == 0, item.ourPrice > 0 {
                            update.asking_price = item.ourPrice
                        }
                        if manifest.status == .sold, existing.status != InventoryStatus.sold {
                            update.status = InventoryStatus.sold.rawValue
                            update.sold_price = item.ourPrice
                            update.sold_at = manifest.updatedAt
                        }
                        if update.hasChanges {
                            try await patchInventoryUnit(id: existing.id, update: update, token: session.accessToken)
                        }
                        continue
                    }

                    let insert = InventoryUnitInsert(
                        id: UUID(),
                        org_id: manifest.orgID,
                        source_manifest_id: manifest.id,
                        source_manifest_item_id: item.id,
                        source_manifest_item_index: index,
                        model_number: item.modelNumber,
                        product_name: item.productName,
                        brand: derivedBrand,
                        appliance_category: derivedCategory,
                        msrp: item.msrp,
                        asking_price: item.ourPrice,
                        cost_basis: unitCostBasis,
                        sold_price: manifest.status == .sold ? item.ourPrice : nil,
                        condition: item.condition.rawValue,
                        status: manifest.status == .sold ? InventoryStatus.sold.rawValue : InventoryStatus.inStock.rawValue,
                        photo_path: item.photoPath,
                        listed_at: nil,
                        reserved_at: nil,
                        sold_at: manifest.status == .sold ? manifest.updatedAt : nil
                    )

                    _ = try await httpClient.send(
                        to: environment.supabaseURL.appending(path: "rest/v1/inventory_units"),
                        method: "POST",
                        headers: authenticatedHeaders(token: session.accessToken, prefer: "return=representation"),
                        body: [insert]
                    ) as [InventoryUnitRecord]
                }
            }
        }
    }

    func syncLinkedInventoryStatus(manifestID: UUID) async throws {
        let session = try await requireSession()
        guard let manifest = try await fetchManifestRecord(id: manifestID, token: session.accessToken)?.makeManifest(items: try await fetchManifestItems(manifestID: manifestID, token: session.accessToken), ownerEmail: session.user.email) else {
            return
        }

        let links = try await fetchManifestInventoryLinks(manifestID: manifestID, token: session.accessToken)
        guard !links.isEmpty else { return }

        let priceByItemID = Dictionary(uniqueKeysWithValues: manifest.items.map { ($0.id, $0.ourPrice) })
        let now = Date()

        if manifest.status == .sold {
            for link in links {
                try await patchInventoryUnit(
                    id: link.inventory_unit_id,
                    update: InventoryUnitPartialUpdate(
                        status: InventoryStatus.sold.rawValue,
                        reserved_at: nil,
                        sold_price: priceByItemID[link.manifest_item_id],
                        sold_at: now
                    ),
                    token: session.accessToken
                )
            }
            try await patchManifestInventoryLinks(
                manifestID: manifestID,
                update: ManifestInventoryLinkUpdate(release_on_delete: false),
                token: session.accessToken
            )
        } else {
            try await patchInventoryUnits(
                ids: links.map(\.inventory_unit_id),
                update: InventoryUnitStatusPatch(
                    status: InventoryStatus.reserved.rawValue,
                    reserved_at: now,
                    sold_at: nil,
                    sold_price: nil
                ),
                token: session.accessToken
            )
            try await patchManifestInventoryLinks(
                manifestID: manifestID,
                update: ManifestInventoryLinkUpdate(release_on_delete: true),
                token: session.accessToken
            )
        }
    }

    func ingestSticker(imageData: Data) async throws -> LookupSuggestion {
        struct IngestRequest: Encodable { let imageBase64: String }

        let smallData = Self.resizedJPEG(imageData, maxDimension: 768, compressionQuality: 0.55) ?? imageData
        return try await httpClient.send(
            to: environment.functionsURL.appending(path: "ingest-sticker-v2"),
            method: "POST",
            headers: anonBearerHeaders,
            body: IngestRequest(imageBase64: smallData.base64EncodedString())
        )
    }

    private func insertManifestItems(
        _ draftItems: [DraftManifestItem],
        into manifestID: UUID,
        createdAt: Date,
        token: String
    ) async throws -> [ManifestItem] {
        var createdItems: [ManifestItem] = []
        var uploadedPhotoPaths: [String] = []

        do {
            for draft in draftItems {
                let normalized = ModelNumberNormalizer.normalize(draft.modelNumber)
                if draft.lookupStatus == .confirmed || draft.lookupStatus == .cached {
                    let suggestion = LookupSuggestion(
                        normalizedModelNumber: normalized,
                        productName: draft.productName,
                        brand: draft.brand,
                        applianceCategory: draft.applianceCategory,
                        msrp: Decimal(string: draft.msrpText) ?? 0,
                        source: draft.source.isEmpty ? "operator-confirmed" : draft.source,
                        confidence: draft.confidence,
                        status: .confirmed
                    )

                    try? await confirmProduct(suggestion, aliasModelNumbers: aliasModelNumbers(for: draft))
                }

                let photoPath: String?
                if draft.imageData.isEmpty {
                    photoPath = nil
                } else {
                    do {
                        let path = try await uploadPhoto(data: draft.imageData, manifestID: manifestID, itemID: draft.id)
                        uploadedPhotoPaths.append(path)
                        photoPath = path
                    } catch {
                        throw AppError.lookupFailed("We couldn't upload one of the item photos. Please try again.")
                    }
                }

                let insert = ManifestItemInsert(
                    id: draft.id,
                    manifest_id: manifestID,
                    model_number: normalized,
                    product_name: draft.productName,
                    brand: draft.brand,
                    appliance_category: draft.applianceCategory,
                    msrp: Decimal(string: draft.msrpText) ?? 0,
                    our_price: Decimal(string: draft.ourPriceText) ?? 0,
                    condition: draft.condition.rawValue,
                    quantity: draft.quantity,
                    photo_path: photoPath,
                    lookup_status: LookupStatus.confirmed.rawValue,
                    created_at: createdAt
                )

                let records: [ManifestItemRecord]
                do {
                    records = try await httpClient.send(
                        to: environment.supabaseURL.appending(path: "rest/v1/manifest_items"),
                        method: "POST",
                        headers: authenticatedHeaders(token: token, prefer: "return=representation"),
                        body: [insert]
                    )
                } catch {
                    throw AppError.lookupFailed("We couldn't save one of the items in this load. Please try again.")
                }

                if let item = records.first?.makeManifestItem() {
                    createdItems.append(item)
                }
            }

            return createdItems
        } catch {
            if !uploadedPhotoPaths.isEmpty {
                try? await deletePhotos(at: uploadedPhotoPaths, token: token)
            }
            throw error
        }
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

        if let cached = lookupSuggestionCache[normalized] {
            return cached
        }

        if let cached = try await fetchCatalogSuggestion(normalizedModelNumber: normalized, token: session.accessToken) {
            cacheLookupSuggestion(cached)
            return cached
        }

        let suggestion: LookupSuggestion = try await httpClient.send(
            to: environment.functionsURL.appending(path: "lookup-product-v2"),
            method: "POST",
            headers: anonBearerHeaders,
            body: RequestBody(modelNumber: normalized)
        )
        cacheLookupSuggestion(suggestion)
        return suggestion
    }

    func confirmProduct(_ suggestion: LookupSuggestion, aliasModelNumbers: [String] = []) async throws {
        struct ConfirmProductRequest: Encodable {
            let normalizedModelNumber: String
            let productName: String
            let brand: String?
            let applianceCategory: String?
            let msrp: Decimal
            let source: String
            let confidence: Double
        }

        _ = try await requireSession()
        let payload = ConfirmProductRequest(
            normalizedModelNumber: suggestion.normalizedModelNumber,
            productName: suggestion.productName,
            brand: suggestion.brand?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            applianceCategory: suggestion.applianceCategory?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            msrp: suggestion.msrp,
            source: suggestion.source,
            confidence: suggestion.confidence
        )

        let confirmed: LookupSuggestion = try await httpClient.send(
            to: environment.functionsURL.appending(path: "confirm-product-v2"),
            method: "POST",
            headers: anonBearerHeaders,
            body: payload
        )
        cacheLookupSuggestion(confirmed, additionalModelNumbers: aliasModelNumbers)
    }

    func updateItem(_ item: ManifestItem, in manifest: Manifest) async throws -> Manifest {
        let session = try await requireSession()

        let update = ManifestItemUpdate(
            model_number: item.modelNumber,
            product_name: item.productName,
            brand: item.brand,
            appliance_category: item.applianceCategory,
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
                URLQueryItem(name: "is_active", value: "eq.true"),
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

    private func uploadInventoryPhoto(data: Data, sharedID: UUID) async throws -> String {
        let session = try await requireSession()
        let objectPath = "inventory/\(sharedID.uuidString).jpg"
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

    private func fetchManifestRecord(id: UUID, token: String) async throws -> ManifestRecord? {
        let url = environment.supabaseURL
            .appending(path: "rest/v1/manifests")
            .appending(queryItems: [
                URLQueryItem(name: "id", value: "eq.\(id.uuidString)"),
                URLQueryItem(name: "limit", value: "1")
            ])

        let records: [ManifestRecord] = try await httpClient.send(
            to: url,
            method: "GET",
            headers: authenticatedHeaders(token: token, prefer: nil)
        )
        return records.first
    }

    private func fetchManifestItems(manifestID: UUID, token: String) async throws -> [ManifestItem] {
        let url = environment.supabaseURL
            .appending(path: "rest/v1/manifest_items")
            .appending(queryItems: [
                URLQueryItem(name: "manifest_id", value: "eq.\(manifestID.uuidString)")
            ])

        let records: [ManifestItemRecord] = try await httpClient.send(
            to: url,
            method: "GET",
            headers: authenticatedHeaders(token: token, prefer: nil)
        )
        return records.map { $0.makeManifestItem() }
    }

    private func fetchInventoryUnits(ids: [UUID]?, token: String) async throws -> [InventoryUnit] {
        var queryItems = [
            URLQueryItem(name: "select", value: InventoryUnitRecord.selectColumns),
            URLQueryItem(name: "order", value: "updated_at.desc")
        ]
        if let ids, !ids.isEmpty {
            let idList = ids.map(\.uuidString).joined(separator: ",")
            queryItems.append(URLQueryItem(name: "id", value: "in.(\(idList))"))
        }

        let url = environment.supabaseURL
            .appending(path: "rest/v1/inventory_units")
            .appending(queryItems: queryItems)

        let records: [InventoryUnitRecord] = try await httpClient.send(
            to: url,
            method: "GET",
            headers: authenticatedHeaders(token: token, prefer: nil)
        )
        return records.map { $0.makeInventoryUnit() }
    }

    private func fetchManifestInventoryLinks(manifestID: UUID, token: String) async throws -> [ManifestInventoryLinkRecord] {
        let url = environment.supabaseURL
            .appending(path: "rest/v1/manifest_inventory_links")
            .appending(queryItems: [
                URLQueryItem(name: "manifest_id", value: "eq.\(manifestID.uuidString)")
            ])

        return try await httpClient.send(
            to: url,
            method: "GET",
            headers: authenticatedHeaders(token: token, prefer: nil)
        )
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

    private func syncCachedSessionOrgID(_ orgID: UUID?) {
        guard let current = session else { return }
        let updated = UserSession(
            accessToken: current.accessToken,
            refreshToken: current.refreshToken,
            user: AppUser(id: current.user.id, email: current.user.email, orgID: orgID),
            sessionNonce: current.sessionNonce
        )
        session = updated
        sessionStore.save(updated)
    }

    private func bootstrapAppleAccount(for existing: UserSession, inviteCode: String?) async throws -> UserSession {
        struct RequestBody: Encodable { let inviteCode: String? }
        struct Response: Decodable { let org_id: UUID }

        let response: Response = try await httpClient.send(
            to: environment.functionsURL.appending(path: "bootstrap-apple-account"),
            method: "POST",
            headers: authenticatedHeaders(token: existing.accessToken, prefer: nil),
            body: RequestBody(inviteCode: inviteCode)
        )

        let updated = UserSession(
            accessToken: existing.accessToken,
            refreshToken: existing.refreshToken,
            user: AppUser(id: existing.user.id, email: existing.user.email, orgID: response.org_id),
            sessionNonce: existing.sessionNonce
        )
        return updated
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
                URLQueryItem(name: "select", value: "normalized_model_number,product_name,brand,appliance_category,msrp,source,confidence"),
                URLQueryItem(name: "normalized_model_number", value: "eq.\(normalizedModelNumber)"),
                URLQueryItem(name: "limit", value: "1")
            ])

        let records: [CatalogProductRecord] = try await httpClient.send(
            to: url,
            method: "GET",
            headers: authenticatedHeaders(token: token, prefer: nil)
        )

        guard let record = records.first else { return nil }
        if record.source?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "model-ai" {
            return nil
        }

        return LookupSuggestion(
            normalizedModelNumber: record.normalized_model_number,
            productName: record.product_name,
            brand: record.brand,
            applianceCategory: record.appliance_category,
            msrp: record.msrp,
            source: record.source ?? "catalog-cache",
            confidence: record.confidence,
            status: .cached
        )
    }

    private func recoverManifestCreation(
        manifestID: UUID,
        expectedDraftItems: [DraftManifestItem],
        token: String,
        ownerEmail: String?
    ) async throws -> ManifestCreationRecovery {
        guard let manifestRecord = try await fetchManifestRecord(id: manifestID, token: token) else {
            return .missing
        }

        let manifestItems = try await fetchManifestItems(manifestID: manifestID, token: token)
        let expectedItemIDs = Set(expectedDraftItems.map(\.id))
        let actualItemIDs = Set(manifestItems.map(\.id))
        let manifest = manifestRecord.makeManifest(items: manifestItems, ownerEmail: ownerEmail)

        if expectedItemIDs.isSubset(of: actualItemIDs) {
            return .complete(manifest)
        }

        return .partial(manifest)
    }

    private func cleanupPartialManifest(_ manifest: Manifest, token: String) async -> Bool {
        let photoPaths = manifest.items.compactMap(\.photoPath)
        if !photoPaths.isEmpty {
            try? await deletePhotos(at: photoPaths, token: token)
        }

        do {
            try await deleteManifestByID(manifest.id, token: token)
            return true
        } catch {
            return false
        }
    }

    private func cacheLookupSuggestion(_ suggestion: LookupSuggestion, additionalModelNumbers: [String] = []) {
        let normalized = ModelNumberNormalizer.normalize(suggestion.normalizedModelNumber)
        guard !normalized.isEmpty else { return }

        let cachedSuggestion = LookupSuggestion(
            normalizedModelNumber: normalized,
            productName: suggestion.productName,
            brand: suggestion.brand,
            applianceCategory: suggestion.applianceCategory,
            msrp: suggestion.msrp,
            source: suggestion.source,
            confidence: suggestion.confidence,
            status: suggestion.status
        )

        lookupSuggestionCache[normalized] = cachedSuggestion

        for alias in additionalModelNumbers {
            let normalizedAlias = ModelNumberNormalizer.normalize(alias)
            guard !normalizedAlias.isEmpty else { continue }
            lookupSuggestionCache[normalizedAlias] = cachedSuggestion
        }
    }

    private func aliasModelNumbers(for draft: DraftManifestItem) -> [String] {
        let observed = ModelNumberNormalizer.normalize(draft.observedModelNumber ?? "")
        let canonical = ModelNumberNormalizer.normalize(draft.modelNumber)
        guard !observed.isEmpty, !canonical.isEmpty, observed != canonical else {
            return []
        }
        return [observed]
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

    private func patchInventoryUnits(ids: [UUID], update: InventoryUnitStatusPatch, token: String) async throws {
        guard !ids.isEmpty else { return }
        let idList = ids.map(\.uuidString).joined(separator: ",")
        let url = environment.supabaseURL
            .appending(path: "rest/v1/inventory_units")
            .appending(queryItems: [
                URLQueryItem(name: "id", value: "in.(\(idList))")
            ])

        _ = try await httpClient.send(
            to: url,
            method: "PATCH",
            headers: authenticatedHeaders(token: token, prefer: "return=representation"),
            body: update
        ) as [InventoryUnitRecord]
    }

    private func patchInventoryUnit(id: UUID, update: InventoryUnitPartialUpdate, token: String) async throws {
        let url = environment.supabaseURL
            .appending(path: "rest/v1/inventory_units")
            .appending(queryItems: [
                URLQueryItem(name: "id", value: "eq.\(id.uuidString)")
            ])

        _ = try await httpClient.send(
            to: url,
            method: "PATCH",
            headers: authenticatedHeaders(token: token, prefer: "return=representation"),
            body: update
        ) as [InventoryUnitRecord]
    }

    private func patchManifestInventoryLinks(manifestID: UUID, update: ManifestInventoryLinkUpdate, token: String) async throws {
        let url = environment.supabaseURL
            .appending(path: "rest/v1/manifest_inventory_links")
            .appending(queryItems: [
                URLQueryItem(name: "manifest_id", value: "eq.\(manifestID.uuidString)")
            ])

        _ = try await httpClient.send(
            to: url,
            method: "PATCH",
            headers: authenticatedHeaders(token: token, prefer: "return=representation"),
            body: update
        ) as [ManifestInventoryLinkRecord]
    }

    private func deriveBrand(from productName: String) -> String? {
        let trimmed = productName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.split(separator: " ").first.map(String.init)
    }

    private func deriveApplianceCategory(from productName: String) -> String? {
        let lowercased = productName.lowercased()
        let mappings: [(String, String)] = [
            ("refrigerator", "refrigerator"),
            ("fridge", "refrigerator"),
            ("freezer", "refrigerator"),
            ("washer", "washer"),
            ("washing machine", "washer"),
            ("dryer", "dryer"),
            ("dishwasher", "dishwasher"),
            ("microwave", "microwave"),
            ("range", "range"),
            ("oven", "range"),
            ("cooktop", "range"),
            ("stove", "range")
        ]

        return mappings.first(where: { lowercased.contains($0.0) })?.1
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
    let brand: String?
    let appliance_category: String?
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
            brand: brand,
            applianceCategory: appliance_category,
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
    let brand: String?
    let appliance_category: String?
    let msrp: Decimal
    let source: String?
    let confidence: Double
}

private enum ManifestCreationRecovery {
    case complete(Manifest)
    case partial(Manifest)
    case missing
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
    let brand: String?
    let appliance_category: String?
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
    let brand: String?
    let appliance_category: String?
    let msrp: Decimal
    let our_price: Decimal
    let condition: String
    let quantity: Int
    let photo_path: String?
    let lookup_status: String
    let created_at: Date
}

private struct InventoryUnitRecord: Decodable {
    static let selectColumns = "id,org_id,source_manifest_id,source_manifest_item_id,source_manifest_item_index,model_number,product_name,brand,appliance_category,msrp,asking_price,cost_basis,sold_price,condition,status,photo_path,created_at,updated_at,listed_at,reserved_at,sold_at"

    let id: UUID
    let org_id: UUID
    let source_manifest_id: UUID?
    let source_manifest_item_id: UUID?
    let source_manifest_item_index: Int?
    let model_number: String
    let product_name: String
    let brand: String?
    let appliance_category: String?
    let msrp: Decimal
    let asking_price: Decimal
    let cost_basis: Decimal?
    let sold_price: Decimal?
    let condition: String?
    let status: String
    let photo_path: String?
    let created_at: Date
    let updated_at: Date
    let listed_at: Date?
    let reserved_at: Date?
    let sold_at: Date?

    func makeInventoryUnit() -> InventoryUnit {
        InventoryUnit(
            id: id,
            orgID: org_id,
            sourceManifestID: source_manifest_id,
            sourceManifestItemID: source_manifest_item_id,
            sourceManifestItemIndex: source_manifest_item_index,
            modelNumber: model_number,
            productName: product_name,
            brand: brand,
            applianceCategory: appliance_category,
            msrp: msrp,
            askingPrice: asking_price,
            costBasis: cost_basis,
            soldPrice: sold_price,
            condition: ItemCondition(rawValue: condition ?? "") ?? .used,
            status: InventoryStatus(rawValue: status) ?? .inStock,
            photoPath: photo_path,
            createdAt: created_at,
            updatedAt: updated_at,
            listedAt: listed_at,
            reservedAt: reserved_at,
            soldAt: sold_at
        )
    }
}

private struct InventoryUnitInsert: Encodable {
    let id: UUID
    let org_id: UUID?
    let source_manifest_id: UUID?
    let source_manifest_item_id: UUID?
    let source_manifest_item_index: Int?
    let model_number: String
    let product_name: String
    let brand: String?
    let appliance_category: String?
    let msrp: Decimal
    let asking_price: Decimal
    let cost_basis: Decimal?
    let sold_price: Decimal?
    let condition: String
    let status: String
    let photo_path: String?
    let listed_at: Date?
    let reserved_at: Date?
    let sold_at: Date?
}

private struct InventoryUnitUpdate: Encodable {
    let model_number: String
    let product_name: String
    let brand: String?
    let appliance_category: String?
    let msrp: Decimal
    let asking_price: Decimal
    let cost_basis: Decimal?
    let sold_price: Decimal?
    let condition: String
    let status: String
    let photo_path: String?
    let listed_at: Date?
    let reserved_at: Date?
    let sold_at: Date?
}

private struct InventoryUnitStatusPatch: Encodable {
    let status: String
    let reserved_at: Date?
    let sold_at: Date?
    let sold_price: Decimal?
}

private struct InventoryUnitPartialUpdate: Encodable {
    var brand: String? = nil
    var appliance_category: String? = nil
    var asking_price: Decimal? = nil
    var status: String? = nil
    var reserved_at: Date? = nil
    var sold_price: Decimal? = nil
    var sold_at: Date? = nil

    var hasChanges: Bool {
        brand != nil ||
        appliance_category != nil ||
        asking_price != nil ||
        status != nil ||
        reserved_at != nil ||
        sold_price != nil ||
        sold_at != nil
    }
}

private struct ManifestInventoryLinkRecord: Decodable {
    let id: UUID
    let manifest_id: UUID
    let manifest_item_id: UUID
    let inventory_unit_id: UUID
    let restore_status: String
    let release_on_delete: Bool
}

private struct ManifestInventoryLinkInsert: Encodable {
    let manifest_id: UUID
    let manifest_item_id: UUID
    let inventory_unit_id: UUID
    let restore_status: String
    let release_on_delete: Bool
}

private struct ManifestInventoryLinkUpdate: Encodable {
    let release_on_delete: Bool
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension URLComponents {
    func unwrapURL() throws -> URL {
        guard let url else { throw AppError.invalidResponse }
        return url
    }
}
