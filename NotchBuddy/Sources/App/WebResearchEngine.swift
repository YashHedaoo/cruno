import Foundation

// MARK: - Perplexity-Style Web Research Engine (Option 4)

public struct WebSourceCitation: Identifiable, Equatable, Sendable, Codable {
    public var id: String { url }
    public let title: String
    public let url: String
    public let domain: String
    public let snippet: String

    public init(title: String, url: String, domain: String, snippet: String) {
        self.title = title
        self.url = url
        self.domain = domain
        self.snippet = snippet
    }
}

public struct WebResearchResult: Sendable {
    public let query: String
    public let sources: [WebSourceCitation]
    public let summaryText: String
}

@MainActor
final class WebResearchEngine {
    static let shared = WebResearchEngine()

    public private(set) var lastSources: [WebSourceCitation] = []

    private init() {}

    /// Performs deep web search, parses organic sources, and extracts clean snippets.
    func search(query: String, maxResults: Int = 4) async -> WebResearchResult {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else {
            return WebResearchResult(query: query, sources: [], summaryText: "Empty search query.")
        }

        guard let encoded = cleanQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)") else {
            return WebResearchResult(query: query, sources: [], summaryText: "Invalid search query URL.")
        }

        var request = URLRequest(url: searchURL, timeoutInterval: 12)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else {
                return WebResearchResult(query: cleanQuery, sources: [], summaryText: "Unable to reach search engine.")
            }

            let parsedSources = parseDuckDuckGoHTML(html: html, limit: maxResults)
            if parsedSources.isEmpty {
                // Fallback to Instant Answer API
                if let instantResult = await fetchInstantAnswer(query: cleanQuery) {
                    self.lastSources = instantResult.sources
                    return instantResult
                }
                return WebResearchResult(query: cleanQuery, sources: [], summaryText: "No search results found.")
            }

            self.lastSources = parsedSources
            var textSummary = "Deep Web Search Results for '\(cleanQuery)':\n\n"
            for (idx, item) in parsedSources.enumerated() {
                textSummary += "[\(idx + 1)] \(item.title) (\(item.domain))\n"
                textSummary += "URL: \(item.url)\n"
                textSummary += "Snippet: \(item.snippet)\n\n"
            }

            return WebResearchResult(query: cleanQuery, sources: parsedSources, summaryText: textSummary)
        } catch {
            return WebResearchResult(query: cleanQuery, sources: [], summaryText: "Search failed: \(error.localizedDescription)")
        }
    }

    private func parseDuckDuckGoHTML(html: String, limit: Int) -> [WebSourceCitation] {
        var results: [WebSourceCitation] = []

        // Extract result blocks using regex
        let snippetPattern = "class=\"result__snippet\"[^>]*href=\"([^\"]+)\"[^>]*>([\\s\\S]*?)<\\/a>"
        guard let regex = try? NSRegularExpression(pattern: snippetPattern, options: []) else {
            return []
        }

        let nsString = html as NSString
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            guard results.count < limit,
                  match.numberOfRanges >= 3 else { break }

            let rawHref = nsString.substring(with: match.range(at: 1))
            let rawSnippet = nsString.substring(with: match.range(at: 2))

            // Parse destination URL from DuckDuckGo redirect: /l/?uddg=...
            guard let targetURL = extractTargetURL(from: rawHref) else { continue }
            guard let host = targetURL.host?.lowercased().replacingOccurrences(of: "www.", with: "") else { continue }
            if host.contains("duckduckgo.com") { continue }

            let cleanSnippet = sanitizeHTML(rawSnippet)
            let cleanTitle = host.capitalized

            results.append(WebSourceCitation(
                title: cleanTitle,
                url: targetURL.absoluteString,
                domain: host,
                snippet: cleanSnippet
            ))
        }

        return results
    }

    private func extractTargetURL(from rawHref: String) -> URL? {
        var cleanHref = rawHref.replacingOccurrences(of: "&amp;", with: "&")
        if cleanHref.hasPrefix("//") { cleanHref = "https:" + cleanHref }
        guard let components = URLComponents(string: cleanHref) else { return nil }
        if let uddg = components.queryItems?.first(where: { $0.name == "uddg" })?.value,
           let directURL = URL(string: uddg) {
            return directURL
        }
        return URL(string: cleanHref)
    }

    private func sanitizeHTML(_ input: String) -> String {
        var text = input
        let htmlTagsPattern = "<[^>]+>"
        if let regex = try? NSRegularExpression(pattern: htmlTagsPattern, options: []) {
            let range = NSRange(location: 0, length: (text as NSString).length)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }
        text = text.replacingOccurrences(of: "&#x27;", with: "'")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "\n", with: " ")
        text = text.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fetchInstantAnswer(query: String) async -> WebResearchResult? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_html=1&skip_disambig=1") else {
            return nil
        }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let abstract = (json["AbstractText"] as? String) ?? ""
        let sourceURL = (json["AbstractURL"] as? String) ?? ""
        let sourceName = (json["AbstractSource"] as? String) ?? "Source"

        guard !abstract.isEmpty, let directURL = URL(string: sourceURL), let host = directURL.host else {
            return nil
        }

        let citation = WebSourceCitation(
            title: sourceName,
            url: sourceURL,
            domain: host.replacingOccurrences(of: "www.", with: ""),
            snippet: abstract
        )

        let summary = "Instant Web Fact for '\(query)':\n\n\(abstract)\nSource: \(sourceURL)"
        return WebResearchResult(query: query, sources: [citation], summaryText: summary)
    }
}
