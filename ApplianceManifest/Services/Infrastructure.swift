import Foundation
import ImageIO
import LocalAuthentication
import Vision

final class HTTPClient: @unchecked Sendable {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let session: URLSession

    init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 120
        session = URLSession(configuration: config)
    }

    func send<T: Decodable, Body: Encodable>(
        to url: URL,
        method: String,
        headers: [String: String],
        body: Body
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = try encoder.encode(body)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        if T.self == EmptyResponse.self, data.isEmpty {
            return EmptyResponse() as! T
        }
        return try decoder.decode(T.self, from: data)
    }

    func send<T: Decodable>(
        to url: URL,
        method: String,
        headers: [String: String]
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    func sendWithoutResponse(
        to url: URL,
        method: String,
        headers: [String: String]
    ) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = method
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
    }

    func sendRaw(
        to url: URL,
        method: String,
        headers: [String: String],
        body: Data
    ) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Request failed."
            if message.contains("not_appliance") {
                throw AppError.notAppliance
            }
            throw AppError.lookupFailed(message)
        }
    }
}

final class SessionStore {
    private let defaults = UserDefaults.standard
    private let key = "appliance_manifest.session"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func save(_ session: UserSession) {
        if let data = try? encoder.encode(session) {
            defaults.set(data, forKey: key)
        }
    }

    func restore() -> UserSession? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(UserSession.self, from: data)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

@MainActor
final class BiometricService {
    private let defaults = UserDefaults.standard
    private let enabledKey = "loadscan.biometrics_enabled"

    var isEnabled: Bool {
        get { defaults.bool(forKey: enabledKey) }
        set { defaults.set(newValue, forKey: enabledKey) }
    }

    var canUseBiometrics: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    var biometricType: LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }

    func authenticate() async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return false }
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Verify your identity to access LoadScan"
            )
        } catch {
            return false
        }
    }
}

struct ModelNumberNormalizer {
    static func normalize(_ raw: String) -> String {
        raw
            .uppercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }
}

actor VisionOCRService {
    func extractModelNumber(from imageData: Data) async throws -> String {
        guard let image = CGImageSourceFactory.makeCGImage(from: imageData) else {
            throw AppError.ocrFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let strings = observations.compactMap { $0.topCandidates(1).first?.string }
                let joined = strings.joined(separator: " ")
                let extracted = Self.findBestModelNumber(in: joined)
                if extracted.isEmpty {
                    continuation.resume(throwing: AppError.ocrFailed)
                } else {
                    continuation.resume(returning: extracted)
                }
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func findBestModelNumber(in text: String) -> String {
        let t = text.uppercased()

        // Primary: all common appliance sticker label variants
        let labelPatterns: [String] = [
            #"MODEL\s*(?:NO\.?|NUM(?:BER)?|#)?\s*[:\-#]?\s*([A-Z0-9][A-Z0-9\-\/\.]{4,24})"#,
            #"MOD\.?\s*(?:NO\.?|#)?\s*[:\-]?\s*([A-Z0-9][A-Z0-9\-\/\.]{4,24})"#,
            #"M[\/\.]N\.?\s*[:\-]?\s*([A-Z0-9][A-Z0-9\-\/\.]{4,24})"#,
            #"MODELE\s*[:\-]?\s*([A-Z0-9][A-Z0-9\-\/\.]{4,24})"#,
            #"MODELO\s*[:\-]?\s*([A-Z0-9][A-Z0-9\-\/\.]{4,24})"#,
            #"MODELL\s*[:\-]?\s*([A-Z0-9][A-Z0-9\-\/\.]{4,24})"#,
            #"ITEM\s*(?:NO\.?|#)\s*[:\-]?\s*([A-Z0-9][A-Z0-9\-\/\.]{4,24})"#,
            #"PART\s*(?:NO\.?|#)\s*[:\-]?\s*([A-Z0-9][A-Z0-9\-\/\.]{4,24})"#,
            #"CAT(?:ALOG)?\s*(?:NO\.?|#)\s*[:\-]?\s*([A-Z0-9][A-Z0-9\-\/\.]{4,24})"#,
            #"MFG\.?\s*(?:MODEL|NO\.?|#)\s*[:\-]?\s*([A-Z0-9][A-Z0-9\-\/\.]{4,24})"#,
            #"PRODUCT\s*(?:CODE|NO\.?|#)\s*[:\-]?\s*([A-Z0-9][A-Z0-9\-\/\.]{4,24})"#,
            #"TYPE\s*(?:NO\.?|#)?\s*[:\-]?\s*([A-Z0-9][A-Z0-9\-\/\.]{4,24})"#,
        ]

        for pattern in labelPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
               let range = Range(match.range(at: 1), in: t) {
                let candidate = String(t[range])
                if isValidModelNumber(candidate) {
                    return candidate
                }
            }
        }

        // Fallback: collect all alphanumeric tokens, score and pick the best
        let tokenPattern = #"[A-Z0-9][A-Z0-9\-]{4,24}"#
        guard let regex = try? NSRegularExpression(pattern: tokenPattern) else { return "" }
        let matches = regex.matches(in: t, range: NSRange(t.startIndex..., in: t))
        return matches
            .compactMap { Range($0.range, in: t).map { String(t[$0]) } }
            .filter { isValidModelNumber($0) }
            .max(by: { modelNumberScore($0) < modelNumberScore($1) }) ?? ""
    }

    // Must have at least 1 letter AND 2 digits, length 5–22
    private static func isValidModelNumber(_ s: String) -> Bool {
        guard s.count >= 5, s.count <= 22 else { return false }
        let letters = s.filter(\.isLetter).count
        let digits  = s.filter(\.isNumber).count
        return letters >= 1 && digits >= 2
    }

    // Higher score = more model-number-like
    private static func modelNumberScore(_ s: String) -> Int {
        let letters = s.filter(\.isLetter).count
        let digits  = s.filter(\.isNumber).count
        return min(letters, digits) * 3 + min(s.count, 14)
    }
}

enum CGImageSourceFactory {
    static func makeCGImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

extension URL {
    func appending(queryItems: [URLQueryItem]) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self
        }
        components.queryItems = (components.queryItems ?? []) + queryItems
        return components.url ?? self
    }
}
