import Foundation

@MainActor
struct SpreadsheetExportService {
    func export(manifest: Manifest) throws -> ExportedManifest {
        let header = [
            "Manifest Name",
            "Load Reference",
            "Created Date",
            "Model Number",
            "Product Name",
            "MSRP",
            "Quantity",
            "Line Total",
            "Photo Link"
        ]

        let formatter = ISO8601DateFormatter()
        let rows = manifest.items.map { item in
            [
                manifest.title,
                manifest.loadReference,
                formatter.string(from: manifest.createdAt),
                item.modelNumber,
                item.productName,
                NSDecimalNumber(decimal: item.msrp).stringValue,
                "\(item.quantity)",
                NSDecimalNumber(decimal: item.lineTotal).stringValue,
                item.photoPath ?? ""
            ]
        }

        let csv = ([header] + rows)
            .map { $0.map(Self.escapeCSVField).joined(separator: ",") }
            .joined(separator: "\n")

        let filename = "\(manifest.title.replacingOccurrences(of: " ", with: "_"))-\(manifest.id.uuidString.prefix(6)).csv"
        let fileURL = FileManager.default.temporaryDirectory.appending(path: filename)
        guard let data = csv.data(using: .utf8) else {
            throw AppError.exportFailed
        }
        try data.write(to: fileURL)
        return ExportedManifest(fileURL: fileURL, filename: filename)
    }

    static func escapeCSVField(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
