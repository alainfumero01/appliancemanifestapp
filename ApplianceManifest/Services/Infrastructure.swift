import Foundation
import ImageIO
import Vision

@MainActor
final class HTTPClient {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
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
        let (data, response) = try await URLSession.shared.data(for: request)
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
        let (data, response) = try await URLSession.shared.data(for: request)
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
        let (data, response) = try await URLSession.shared.data(for: request)
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
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Request failed."
            throw AppError.lookupFailed(message)
        }
    }
}

@MainActor
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
        let pattern = #"(?:MODEL|MOD|M/N|MODEL\sNO\.?)[:\s-]*([A-Z0-9\-]{5,})"#
        if
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range(at: 1), in: text)
        {
            return String(text[range])
        }

        let fallbackPattern = #"[A-Z0-9]{5,}(?:-[A-Z0-9]{2,})*"#
        guard let regex = try? NSRegularExpression(pattern: fallbackPattern) else { return "" }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
            .max(by: { $0.count < $1.count }) ?? ""
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
