import Foundation

/// Renders the currently filtered Statistics tree to shareable formats
/// (FR-30/FR-31). All three walk the same flattened row list — the export
/// always reflects the tree's active filters, at full depth.
enum ExportService {
    static func html(rows: [TreeRow]) -> String {
        var body = ""
        for row in TreeBuilder.flatten(rows) {
            let indent = String(repeating: "&nbsp;&nbsp;&nbsp;&nbsp;", count: row.depth)
            body += """
            <tr><td>\(indent)\(escape(row.node.name))</td><td>\(escape(row.resolvedTagLabel))</td><td style="text-align:right">\(DurationFormat.short(row.totalSeconds))</td></tr>\n
            """
        }
        return """
        <!doctype html><html><head><meta charset="utf-8"><title>AppTracker Report</title>
        <style>
        body { font-family: -apple-system, sans-serif; padding: 32px; color: #1c1c1e; }
        table { border-collapse: collapse; width: 100%; max-width: 720px; }
        td { padding: 4px 10px; border-bottom: 1px solid #e5e5ea; font-size: 13px; }
        th { text-align: left; padding: 6px 10px; font-size: 11px; text-transform: uppercase; color: #6e6e73; }
        </style></head><body>
        <h1>AppTracker Report</h1>
        <table><tr><th>Item</th><th>Tag</th><th>Duration</th></tr>
        \(body)
        </table>
        </body></html>
        """
    }

    static func csv(rows: [TreeRow]) -> String {
        var lines = ["Name,Tag,Depth,Seconds"]
        for row in TreeBuilder.flatten(rows) {
            let name = row.node.name.replacingOccurrences(of: "\"", with: "\"\"")
            lines.append("\"\(name)\",\"\(row.resolvedTagLabel)\",\(row.depth),\(row.totalSeconds)")
        }
        return lines.joined(separator: "\n")
    }

    static func json(rows: [TreeRow]) -> String {
        struct ExportRow: Encodable {
            let name: String
            let tag: String
            let depth: Int
            let seconds: Int
        }
        let flat = TreeBuilder.flatten(rows).map {
            ExportRow(name: $0.node.name, tag: $0.resolvedTagLabel, depth: $0.depth, seconds: $0.totalSeconds)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(flat), let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
