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
            "Condition",
            "MSRP",
            "Our Price"
        ]

        let dateFormatter = ISO8601DateFormatter()
        let numberFormatter: NumberFormatter = {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.minimumFractionDigits = 2
            f.maximumFractionDigits = 2
            return f
        }()

        func decimalString(_ value: Decimal) -> String {
            numberFormatter.string(from: NSDecimalNumber(decimal: value)) ?? "0.00"
        }

        let rows = manifest.items.flatMap { item in
            (0 ..< item.quantity).map { _ in
                [
                    manifest.title,
                    manifest.loadReference,
                    dateFormatter.string(from: manifest.createdAt),
                    item.modelNumber,
                    item.productName,
                    item.condition.displayLabel,
                    decimalString(item.msrp),
                    decimalString(item.ourPrice)
                ]
            }
        }

        let msrpTotal = manifest.items.reduce(Decimal(0)) { $0 + $1.msrp * Decimal($1.quantity) }
        let ourPriceTotal = manifest.items.reduce(Decimal(0)) { $0 + $1.ourPrice * Decimal($1.quantity) }

        let blankRow = Array(repeating: "", count: header.count)
        let totalRow = [
            "TOTALS", "", "", "", "", "",
            decimalString(msrpTotal),
            decimalString(ourPriceTotal)
        ]

        let csv = ([header] + rows + [blankRow, totalRow])
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
