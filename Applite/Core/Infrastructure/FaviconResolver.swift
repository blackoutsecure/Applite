import Foundation
import OSLog

actor FaviconResolver {
    static let shared = FaviconResolver()

    private struct Cached {
        let urls: [URL]
        let expires: Date
    }

    private var cache: [URL: Cached] = [:]
    private var pending: [URL: Task<[URL], Never>] = [:]
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Applite",
        category: "FaviconResolver"
    )
    static let maximumHTMLBytes = 128 * 1024

    func candidates(for homepage: URL, configuration: URLSessionConfiguration) async -> [URL] {
        guard let homepage = Self.httpURL(homepage) else {
            Self.logger.info("Skipping favicon discovery for an unsupported homepage URL")
            return []
        }
        if let cached = cache[homepage], cached.expires > Date() {
            return cached.urls
        }
        if let task = pending[homepage] {
            return await task.value
        }

        let task = Task { await Self.discover(homepage, configuration: configuration) }
        pending[homepage] = task
        let urls = await task.value
        pending[homepage] = nil
        if cache.count >= 256, let oldest = cache.min(by: { $0.value.expires < $1.value.expires })?.key {
            cache.removeValue(forKey: oldest)
        }
        cache[homepage] = Cached(urls: urls, expires: Date().addingTimeInterval(300))
        return urls
    }

    private static func discover(_ homepage: URL, configuration: URLSessionConfiguration) async -> [URL] {
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: homepage, timeoutInterval: 8)
        request.setValue("text/html, application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.httpShouldHandleCookies = false

        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  response.mimeType == "text/html" || response.mimeType == "application/xhtml+xml",
                  let pageURL = response.url.flatMap(httpURL) else {
                logger.info("Favicon homepage did not return usable HTML: \(homepage.absoluteString)")
                return candidates(in: "", pageURL: homepage)
            }
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count >= maximumHTMLBytes { break }
            }
            return candidates(in: String(decoding: data, as: UTF8.self), pageURL: pageURL)
        } catch {
            logger.info("Favicon discovery failed for \(homepage.absoluteString): \(error.localizedDescription)")
            return candidates(in: "", pageURL: homepage)
        }
    }

    static func candidates(in html: String, pageURL: URL) -> [URL] {
        guard let pageURL = httpURL(pageURL) else { return [] }
        let headEnd = html.range(of: "</head", options: .caseInsensitive)?.lowerBound ?? html.endIndex
        let head = String(html[..<headEnd]).replacing(
            #/(?is)<!--.*?-->|<script\b[^>]*>.*?</script\s*>|<style\b[^>]*>.*?</style\s*>/#,
            with: ""
        )
        let tags = head.matches(of: #/(?is)<(link|base)\b(?:[^"'<>]|"[^"]*"|'[^']*')*>/#)
        var baseURL = pageURL
        if let base = tags.first(where: { $0.1.lowercased() == "base" }),
           let href = attributes(in: String(base.0))["href"],
           let resolved = URL(string: href, relativeTo: pageURL)?.absoluteURL,
           let url = httpURL(resolved) {
            baseURL = url
        }
        var icons: [(url: URL, priority: Int)] = []
        for tag in tags where tag.1.lowercased() == "link" {
            let attributes = attributes(in: String(tag.0))
            let rel = Set((attributes["rel"] ?? "").lowercased().split(whereSeparator: \.isWhitespace).map(String.init))
            guard rel.contains("icon") || rel.contains("apple-touch-icon") || rel.contains("apple-touch-icon-precomposed"),
                  let href = attributes["href"],
                  let resolved = URL(string: href, relativeTo: baseURL)?.absoluteURL,
                  let url = httpURL(resolved) else { continue }
            let svg = attributes["type"]?.lowercased() == "image/svg+xml" || url.pathExtension.lowercased() == "svg"
            let priority = svg ? 2 : (rel.contains("icon") ? 0 : 1)
            icons.append((url, priority))
        }
        var result: [URL] = []
        var seen: Set<URL> = []
        for icon in icons.enumerated().sorted(by: {
            $0.element.priority == $1.element.priority
                ? $0.offset < $1.offset
                : $0.element.priority < $1.element.priority
        }) where seen.insert(icon.element.url).inserted {
            result.append(icon.element.url)
            if result.count == 3 { break }
        }
        if let root = URL(string: "/favicon.ico", relativeTo: pageURL)?.absoluteURL,
           seen.insert(root).inserted {
            result.append(root)
        }
        return result
    }

    private static func attributes(in tag: String) -> [String: String] {
        var result: [String: String] = [:]
        for attribute in tag.matches(of: #/([a-zA-Z][\w:-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))/#) {
            if let value = attribute.2 ?? attribute.3 ?? attribute.4 {
                result[attribute.1.lowercased()] = String(value).replacing(
                    #/(?i)&(?:amp|#38|#x26);/#, with: "&"
                )
            }
        }
        return result
    }

    private static func httpURL(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil else { return nil }
        components.fragment = nil
        return components.url
    }
}
