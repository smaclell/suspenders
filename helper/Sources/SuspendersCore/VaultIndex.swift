import Foundation

/// Indexes tagged notes in an Obsidian vault into snippets.
public final class VaultIndex {
    public private(set) var notes: [[Snippet]] = [] // grouped per note so big notes don't dominate
    public private(set) var lastIndexed: Date?
    private var recent: [String] = []
    private let lock = NSLock()

    public init() {}

    public var snippetCount: Int { lock.withLock { notes.reduce(0) { $0 + $1.count } } }
    public var noteCount: Int { lock.withLock { notes.count } }

    @discardableResult
    public func rebuild(config: Config) -> Int {
        guard let vaultPath = config.vaultPath else {
            lock.withLock { notes = [] }
            return 0
        }
        let built = VaultIndex.scan(vault: URL(fileURLWithPath: vaultPath), config: config)
        lock.withLock {
            notes = built
            lastIndexed = Date()
        }
        return built.count
    }

    /// Random note, then random passage within it; avoids recently shown passages.
    public func random() -> Snippet? {
        lock.withLock {
            guard !notes.isEmpty else { return nil }
            let all = notes.flatMap { $0 }
            let avoid = Set(recent.suffix(min(recent.count, max(0, all.count - 1))))
            for _ in 0..<12 {
                let note = notes.randomElement()!
                if let s = note.filter({ !avoid.contains($0.id) }).randomElement() {
                    remember(s.id)
                    return s
                }
            }
            let s = all.randomElement()
            if let s { remember(s.id) }
            return s
        }
    }

    private func remember(_ id: String) {
        recent.append(id)
        if recent.count > 30 { recent.removeFirst(recent.count - 30) }
    }

    // MARK: scanning

    static let skipDirs: Set<String> = [".obsidian", ".trash", ".git", "node_modules", ".smart-env"]

    public static func scan(vault: URL, config: Config) -> [[Snippet]] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: vault, includingPropertiesForKeys: [.isDirectoryKey],
                                             options: [.skipsPackageDescendants]) else { return [] }
        var result: [[Snippet]] = []
        let vaultName = vault.lastPathComponent
        for case let url as URL in enumerator {
            if skipDirs.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            guard url.pathExtension.lowercased() == "md",
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let rel = String(url.path.dropFirst(vault.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let snippets = snippetsFor(text: text, relativePath: rel, vaultName: vaultName, config: config)
            if !snippets.isEmpty { result.append(snippets) }
        }
        return result
    }

    public static func snippetsFor(text: String, relativePath rel: String, vaultName: String, config: Config) -> [Snippet] {
        let (fmLines, body) = Markdown.splitFrontmatter(text.replacingOccurrences(of: "\r\n", with: "\n"))
        let tags = Markdown.frontmatterTags(fmLines).union(Markdown.inlineTags(body))
        guard let tag = Markdown.matchingTag(tags, wanted: config.tags) else { return [] }

        let title = (rel as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "", options: [.caseInsensitive, .anchored, .backwards])
        let url = obsidianURL(vault: vaultName, path: rel)
        let isQuotes = config.quoteTags.map { $0.lowercased() }.contains(tag)

        if isQuotes {
            let quotes = Markdown.quotes(body)
            if !quotes.isEmpty {
                return quotes.enumerated().map { i, q in
                    Snippet(id: "\(rel)#q\(i)", kind: .quote, text: q.text, author: q.author, title: title,
                            heading: nil, path: rel, tag: tag, obsidianURL: url)
                }
            }
        }
        return Markdown.passages(body).enumerated().map { i, p in
            Snippet(id: "\(rel)#p\(i)", kind: .note, text: p.text, author: nil, title: title,
                    heading: p.heading, path: rel, tag: tag, obsidianURL: url)
        }
    }

    public static func obsidianURL(vault: String, path: String) -> String? {
        var c = URLComponents()
        c.scheme = "obsidian"
        c.host = "open"
        let file = path.hasSuffix(".md") ? String(path.dropLast(3)) : path
        c.queryItems = [URLQueryItem(name: "vault", value: vault), URLQueryItem(name: "file", value: file)]
        return c.url?.absoluteString
    }
}
