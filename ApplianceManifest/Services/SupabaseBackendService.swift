import Foundation

@MainActor
protocol BackendServicing {
    func restoreSession() async -> UserSession?
    func signIn(email: String, password: String) async throws -> UserSession
    func signUp(email: String, password: String, inviteCode: String) async throws -> UserSession
    func signOut() async
    func fetchManifests() async throws -> [Manifest]
    func createManifest(title: String, loadReference: String, draftItems: [DraftManifestItem]) async throws -> Manifest
    func updateManifest(_ manifest: Manifest) async throws -> Manifest
    func deleteItems(_ items: [ManifestItem], from manifest: Manifest) async throws -> Manifest
    func extractModelNumber(from imageData: Data) async throws -> String
    func lookupProduct(modelNumber: String) async throws -> LookupSuggestion
    func confirmProduct(_ suggestion: LookupSuggestion) async throws
    func exportManifest(_ manifest: Manifest) async throws -> ExportedManifest
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
        session = stored
        return stored
    }

    func signIn(email: String, password: String) async throws -> UserSession {
        struct RequestBody: Encodable {
            let email: String
            let password: String
        }

        let url = environment.supabaseURL.appending(path: "auth/v1/token")
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw AppError.invalidResponse
        }
        components.queryItems = [URLQueryItem(name: "grant_type", value: "password")]

        let response: AuthResponse = try await httpClient.send(
            to: try components.unwrapURL(),
            method: "POST",
            headers: anonHeaders,
            body: RequestBody(email: email, password: password)
        )

        let newSession = response.session
        session = newSession
        sessionStore.save(newSession)
        return newSession
    }

    func signUp(email: String, password: String, inviteCode: String) async throws -> UserSession {
        struct RequestBody: Encodable {
            let email: String
            let password: String
            let inviteCode: String
        }

        let response: AuthResponse = try await httpClient.send(
            to: environment.functionsURL.appending(path: "sign-up-with-invite"),
            method: "POST",
            headers: anonHeaders,
            body: RequestBody(email: email, password: password, inviteCode: inviteCode)
        )

        let newSession = response.session
        session = newSession
        sessionStore.save(newSession)
        return newSession
    }

    func signOut() async {
        session = nil
        sessionStore.clear()
    }

    func fetchManifests() async throws -> [Manifest] {
        let session = try requireSession()
        let url = environment.supabaseURL.appending(path: "rest/v1/manifests")
        let headers = authenticatedHeaders(token: session.accessToken, prefer: nil)
        let records: [ManifestRecord] = try await httpClient.send(to: url, method: "GET", headers: headers)
        let items = try await fetchManifestItems()
        let itemsByManifest = Dictionary(grouping: items, by: \.manifestID)

        return records.map { record in
            record.makeManifest(items: itemsByManifest[record.id] ?? [])
        }
        .sorted(by: { $0.updatedAt > $1.updatedAt })
    }

    func createManifest(title: String, loadReference: String, draftItems: [DraftManifestItem]) async throws -> Manifest {
        let session = try requireSession()
        let manifestID = UUID()
        let now = Date()

        let manifestInsert = ManifestInsert(
            id: manifestID,
            title: title,
            load_reference: loadReference,
            owner_id: session.user.id,
            status: ManifestStatus.draft.rawValue,
            created_at: now,
            updated_at: now
        )

        _ = try await httpClient.send(
            to: environment.supabaseURL.appending(path: "rest/v1/manifests"),
            method: "POST",
            headers: authenticatedHeaders(token: session.accessToken, prefer: "return=representation"),
            body: [manifestInsert]
        ) as [ManifestRecord]

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

            try await confirmProduct(suggestion)
            let photoPath = try await uploadPhoto(data: draft.imageData, manifestID: manifestID, itemID: draft.id)

            let insert = ManifestItemInsert(
                id: draft.id,
                manifest_id: manifestID,
                model_number: normalized,
                product_name: draft.productName,
                msrp: Decimal(string: draft.msrpText) ?? 0,
                quantity: draft.quantity,
                photo_path: photoPath,
                lookup_status: LookupStatus.confirmed.rawValue,
                created_at: now
            )

            let records: [ManifestItemRecord] = try await httpClient.send(
                to: environment.supabaseURL.appending(path: "rest/v1/manifest_items"),
                method: "POST",
                headers: authenticatedHeaders(token: session.accessToken, prefer: "return=representation"),
                body: [insert]
            )

            if let item = records.first?.makeManifestItem() {
                createdItems.append(item)
            }
        }

        return Manifest(
            id: manifestID,
            title: title,
            loadReference: loadReference,
            ownerID: session.user.id,
            createdAt: now,
            updatedAt: now,
            status: .draft,
            items: createdItems
        )
    }

    func updateManifest(_ manifest: Manifest) async throws -> Manifest {
        let session = try requireSession()

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

    func deleteItems(_ items: [ManifestItem], from manifest: Manifest) async throws -> Manifest {
        guard !items.isEmpty else { return manifest }
        let session = try requireSession()
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

    func extractModelNumber(from imageData: Data) async throws -> String {
        let raw = try await ocrService.extractModelNumber(from: imageData)
        let normalized = ModelNumberNormalizer.normalize(raw)
        guard !normalized.isEmpty else {
            throw AppError.ocrFailed
        }
        return normalized
    }

    func lookupProduct(modelNumber: String) async throws -> LookupSuggestion {
        struct RequestBody: Encodable {
            let modelNumber: String
        }

        let session = try requireSession()
        return try await httpClient.send(
            to: environment.functionsURL.appending(path: "lookup-product"),
            method: "POST",
            headers: authenticatedHeaders(token: session.accessToken, prefer: nil),
            body: RequestBody(modelNumber: ModelNumberNormalizer.normalize(modelNumber))
        )
    }

    func confirmProduct(_ suggestion: LookupSuggestion) async throws {
        struct ProductUpsert: Encodable {
            let normalized_model_number: String
            let product_name: String
            let msrp: Decimal
            let source: String
            let confidence: Double
            let last_verified_at: Date
        }

        let session = try requireSession()
        let upsert = ProductUpsert(
            normalized_model_number: suggestion.normalizedModelNumber,
            product_name: suggestion.productName,
            msrp: suggestion.msrp,
            source: suggestion.source,
            confidence: suggestion.confidence,
            last_verified_at: Date()
        )

        _ = try await httpClient.send(
            to: environment.supabaseURL.appending(path: "rest/v1/product_catalog"),
            method: "POST",
            headers: authenticatedHeaders(token: session.accessToken, prefer: "resolution=merge-duplicates,return=minimal"),
            body: [upsert]
        ) as EmptyResponse
    }

    func exportManifest(_ manifest: Manifest) async throws -> ExportedManifest {
        try exportService.export(manifest: manifest)
    }

    private func uploadPhoto(data: Data, manifestID: UUID, itemID: UUID) async throws -> String {
        let session = try requireSession()
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
        let session = try requireSession()
        let url = environment.supabaseURL.appending(path: "rest/v1/manifest_items")
        let records: [ManifestItemRecord] = try await httpClient.send(
            to: url,
            method: "GET",
            headers: authenticatedHeaders(token: session.accessToken, prefer: nil)
        )

        return records.map { $0.makeManifestItem() }
    }

    private func requireSession() throws -> UserSession {
        guard let session else { throw AppError.unauthenticated }
        return session
    }

    private var anonHeaders: [String: String] {
        [
            "Content-Type": "application/json",
            "apikey": environment.supabaseAnonKey
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

private struct AuthResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let user: SupabaseUser

    var session: UserSession {
        UserSession(
            accessToken: access_token,
            refreshToken: refresh_token,
            user: AppUser(id: user.id, email: user.email)
        )
    }
}

private struct SupabaseUser: Decodable {
    let id: UUID
    let email: String
}

private struct ManifestRecord: Decodable {
    let id: UUID
    let title: String
    let load_reference: String
    let owner_id: UUID
    let created_at: Date
    let updated_at: Date
    let status: String

    func makeManifest(items: [ManifestItem]) -> Manifest {
        Manifest(
            id: id,
            title: title,
            loadReference: load_reference,
            ownerID: owner_id,
            createdAt: created_at,
            updatedAt: updated_at,
            status: ManifestStatus(rawValue: status) ?? .draft,
            items: items.sorted(by: { $0.createdAt < $1.createdAt })
        )
    }
}

private struct ManifestItemRecord: Decodable {
    let id: UUID
    let manifest_id: UUID
    let model_number: String
    let product_name: String
    let msrp: Decimal
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
            quantity: quantity,
            photoPath: photo_path,
            lookupStatus: LookupStatus(rawValue: lookup_status) ?? .pending,
            createdAt: created_at
        )
    }
}

private struct ManifestInsert: Encodable {
    let id: UUID
    let title: String
    let load_reference: String
    let owner_id: UUID
    let status: String
    let created_at: Date
    let updated_at: Date
}

private struct ManifestUpdate: Encodable {
    let title: String
    let load_reference: String
    let status: String
    let updated_at: Date
}

private struct ManifestItemInsert: Encodable {
    let id: UUID
    let manifest_id: UUID
    let model_number: String
    let product_name: String
    let msrp: Decimal
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
