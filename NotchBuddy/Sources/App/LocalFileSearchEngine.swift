import AppKit
import Foundation
import PDFKit

// MARK: - Local Mac File & Clipboard Assistant Engine (Option 5)

public struct FileSearchResultItem: Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let fileExtension: String
    public let sizeBytes: Int64
    public let formattedSize: String
    public let modifiedDate: Date?
}

@MainActor
final class LocalFileSearchEngine {
    static let shared = LocalFileSearchEngine()

    private var recentClipboards: [String] = []
    private var lastChangeCount: Int = -1

    private init() {
        trackClipboard()
    }

    /// Searches files across user's home or specific folder via Spotlight metadata engine.
    func searchFiles(query: String, scope: String? = nil, limit: Int = 10) async -> [FileSearchResultItem] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else { return [] }

        let searchScope: String
        if let scope = scope, !scope.isEmpty {
            if scope.hasPrefix("~") {
                searchScope = (scope as NSString).expandingTildeInPath
            } else if scope.lowercased() == "downloads" {
                searchScope = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? NSHomeDirectory()
            } else if scope.lowercased() == "desktop" {
                searchScope = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path ?? NSHomeDirectory()
            } else if scope.lowercased() == "documents" {
                searchScope = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? NSHomeDirectory()
            } else {
                searchScope = scope
            }
        } else {
            searchScope = NSHomeDirectory()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        // Search inside scope by name or content
        process.arguments = ["-onlyin", searchScope, cleanQuery]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }

            let lines = output.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.contains("/Library/") && !$0.contains("/.git/") && !$0.contains("/DerivedData/") }

            let fm = FileManager.default
            var items: [FileSearchResultItem] = []

            for path in lines.prefix(limit) {
                guard fm.fileExists(atPath: path) else { continue }
                let url = URL(fileURLWithPath: path)
                let attrs = (try? fm.attributesOfItem(atPath: path)) ?? [:]
                let size = (attrs[.size] as? Int64) ?? 0
                let modDate = attrs[.modificationDate] as? Date

                let formattedSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                items.append(FileSearchResultItem(
                    path: path,
                    name: url.lastPathComponent,
                    fileExtension: url.pathExtension.lowercased(),
                    sizeBytes: size,
                    formattedSize: formattedSize,
                    modifiedDate: modDate
                ))
            }
            return items
        } catch {
            return []
        }
    }

    /// Reads and parses content of a file (handles text, markdown, code, and PDFs).
    func readFileContent(path: String, maxCharacters: Int = 18_000) async -> String {
        let cleanPath = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: cleanPath)

        guard FileManager.default.fileExists(atPath: cleanPath) else {
            return "File does not exist at: \(cleanPath)"
        }

        let ext = url.pathExtension.lowercased()

        // PDF Document parsing
        if ext == "pdf" {
            guard let pdfDoc = PDFDocument(url: url) else {
                return "Unable to open PDF document."
            }
            var text = ""
            let pageCount = min(pdfDoc.pageCount, 15)
            for i in 0..<pageCount {
                if let page = pdfDoc.page(at: i), let pageStr = page.string {
                    text += "--- Page \(i + 1) ---\n" + pageStr + "\n\n"
                    if text.count > maxCharacters { break }
                }
            }
            if text.isEmpty {
                return "PDF document contains no selectable text (may be a scanned document)."
            }
            return String(text.prefix(maxCharacters))
        }

        // Standard text, code, markdown, json, yaml, csv, log
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            if let string = String(data: data.prefix(maxCharacters * 2), encoding: .utf8) {
                let trimmed = string.count > maxCharacters ? String(string.prefix(maxCharacters)) + "\n[...truncated...]" : string
                return trimmed
            } else {
                return "Binary file (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))). Cannot display as plain text."
            }
        } catch {
            return "Error reading file: \(error.localizedDescription)"
        }
    }

    /// Gets current clipboard contents and maintains recent clipboard history.
    func getClipboardContent() -> String {
        trackClipboard()
        let pb = NSPasteboard.general
        if let str = pb.string(forType: .string), !str.isEmpty {
            var summary = "Current Clipboard:\n\(str)"
            if recentClipboards.count > 1 {
                summary += "\n\nRecent Clipboard History:\n"
                for (idx, item) in recentClipboards.prefix(4).enumerated() {
                    let preview = item.prefix(80).replacingOccurrences(of: "\n", with: " ")
                    summary += "[\(idx + 1)] \(preview)...\n"
                }
            }
            return summary
        }
        return "Clipboard is empty."
    }

    private func trackClipboard() {
        let pb = NSPasteboard.general
        if pb.changeCount != lastChangeCount {
            lastChangeCount = pb.changeCount
            if let str = pb.string(forType: .string), !str.isEmpty {
                if !recentClipboards.contains(str) {
                    recentClipboards.insert(str, at: 0)
                    if recentClipboards.count > 10 {
                        recentClipboards.removeLast()
                    }
                }
            }
        }
    }
}
