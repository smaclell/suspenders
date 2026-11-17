import Foundation

public struct Snippet: Codable, Equatable {
    public enum Kind: String, Codable { case note, quote }
    public var id: String
    public var kind: Kind
    public var text: String
    public var author: String?
    public var title: String
    public var heading: String?
    public var path: String
    public var tag: String
    public var source: String = "vault"
    public var obsidianURL: String?
}

/// Pure markdown helpers for Obsidian-flavoured notes.
public enum Markdown {
    // MARK: frontmatter & tags

    /// Splits a note into (frontmatter lines, body).
    public static func splitFrontmatter(_ text: String) -> (frontmatter: [String], body: String) {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return ([], text) }
        for i in 1..<lines.count where lines[i].trimmingCharacters(in: .whitespaces) == "---" {
            return (Array(lines[1..<i]), lines[(i + 1)...].joined(separator: "\n"))
        }
        return ([], text)
    }

    public static func frontmatterTags(_ lines: [String]) -> Set<String> {
        var tags = Set<String>()
        var inList = false
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let colon = line.firstIndex(of: ":"), !line.hasPrefix("-") {
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                inList = (key == "tags" || key == "tag")
                guard inList else { continue }
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if !value.isEmpty {
                    let cleaned = value.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                    cleaned.split(whereSeparator: { $0 == "," || $0 == " " }).forEach { tags.insert(normalizeTag(String($0))) }
                    inList = false
                }
            } else if inList, line.hasPrefix("-") {
                tags.insert(normalizeTag(String(line.dropFirst())))
            }
        }
        tags.remove("")
        return tags
    }

    static let inlineTagRegex = try! NSRegularExpression(pattern: "(?:^|[\\s(])#([\\p{L}\\p{N}_/-]*[\\p{L}_/-][\\p{L}\\p{N}_/-]*)")

    public static func inlineTags(_ body: String) -> Set<String> {
        var tags = Set<String>()
        for line in stripCodeBlocks(body).components(separatedBy: "\n") {
            let ns = line as NSString
            for m in inlineTagRegex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                tags.insert(normalizeTag(ns.substring(with: m.range(at: 1))))
            }
        }
        return tags
    }

    static func normalizeTag(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#\"'"))
            .lowercased()
    }

    /// First configured tag that matches (including nested tags such as `anki/books`).
    public static func matchingTag(_ noteTags: Set<String>, wanted: [String]) -> String? {
        for w in wanted.map({ $0.lowercased() }) where noteTags.contains(where: { $0 == w || $0.hasPrefix(w + "/") }) {
            return w
        }
        return nil
    }

    // MARK: cleaning

    public static func stripCodeBlocks(_ text: String) -> String {
        var out: [String] = []
        var inFence = false
        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") || line.trimmingCharacters(in: .whitespaces).hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            if !inFence { out.append(line) }
        }
        return out.joined(separator: "\n")
    }

    private static let replacements: [(NSRegularExpression, String)] = [
        ("!\\[\\[[^\\]]*\\]\\]", ""), // embeds
        ("!\\[[^\\]]*\\]\\([^)]*\\)", ""), // images
        ("\\[\\[[^\\]|]*\\|([^\\]]*)\\]\\]", "$1"), // [[target|alias]]
        ("\\[\\[([^\\]]*)\\]\\]", "$1"), // [[target]]
        ("\\[([^\\]]*)\\]\\([^)]*\\)", "$1"), // [text](url)
        ("(\\*\\*|__)(.+?)\\1", "$2"), // bold
        ("(?<![\\w*])\\*(?!\\s)(.+?)(?<!\\s)\\*(?![\\w*])", "$1"), // *italic*
        ("==(.+?)==", "$1"), // highlights
        ("`([^`]*)`", "$1"), // inline code
        ("%%.*?%%", ""), // comments
        ("\\^[A-Za-z0-9-]+\\s*$", ""), // block ids
        ("(?:^|\\s)#[\\p{L}\\p{N}_/-]*[\\p{L}_/-][\\p{L}\\p{N}_/-]*", ""), // inline tags
    ].map { (try! NSRegularExpression(pattern: $0.0, options: [.anchorsMatchLines]), $0.1) }

    public static func cleanInline(_ text: String) -> String {
        var s = text
        for (re, template) in replacements {
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
        }
        return s.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func headingText(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("#") else { return nil }
        let hashes = t.prefix(while: { $0 == "#" })
        guard hashes.count <= 6, t.dropFirst(hashes.count).first == " " else { return nil }
        return cleanInline(String(t.dropFirst(hashes.count)))
    }

    static func listItemText(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        for prefix in ["- [ ] ", "- [x] ", "- ", "* ", "+ "] where t.hasPrefix(prefix) {
            return String(t.dropFirst(prefix.count))
        }
        if let dot = t.firstIndex(of: "."), t[..<dot].allSatisfy(\.isNumber), !t[..<dot].isEmpty,
           t[t.index(after: dot)...].hasPrefix(" ") {
            return String(t[t.index(dot, offsetBy: 2)...])
        }
        return nil
    }

    // MARK: passages

    public struct Passage: Equatable {
        public var heading: String?
        public var text: String
    }

    /// Splits a note body into readable passages, grouped by heading.
    public static func passages(_ body: String, minChars: Int = 180, maxChars: Int = 700) -> [Passage] {
        var sections: [(heading: String?, paragraphs: [String])] = [(nil, [])]
        var current: [String] = []

        func flushParagraph() {
            let text = cleanInline(current.joined(separator: "\n"))
            if !text.isEmpty { sections[sections.count - 1].paragraphs.append(text) }
            current = []
        }

        for line in stripCodeBlocks(body).components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let h = headingText(line) {
                flushParagraph()
                sections.append((h, []))
            } else if trimmed.isEmpty || trimmed == "---" || trimmed.hasPrefix("> [!") {
                flushParagraph()
            } else if trimmed.hasPrefix("|") {
                continue // tables don't read well as passages
            } else {
                var l = trimmed
                if l.hasPrefix(">") { l = String(l.drop(while: { $0 == ">" || $0 == " " })) }
                if let item = listItemText(l) { l = "• " + item }
                current.append(l)
            }
        }
        flushParagraph()

        var result: [Passage] = []
        for section in sections {
            var buffer = ""
            for p in section.paragraphs {
                if buffer.isEmpty { buffer = p } else if buffer.count + p.count + 2 <= maxChars { buffer += "\n\n" + p } else {
                    result.append(Passage(heading: section.heading, text: truncate(buffer, to: maxChars)))
                    buffer = p
                }
                if buffer.count >= minChars {
                    result.append(Passage(heading: section.heading, text: truncate(buffer, to: maxChars)))
                    buffer = ""
                }
            }
            if !buffer.isEmpty {
                // Short trailing text joins the previous passage of the same section when it fits.
                if let last = result.last, last.heading == section.heading, last.text.count + buffer.count + 2 <= maxChars {
                    result[result.count - 1].text += "\n\n" + buffer
                } else {
                    result.append(Passage(heading: section.heading, text: truncate(buffer, to: maxChars)))
                }
            }
        }
        // Drop fragments that are too thin to be meaningful, unless that's all there is.
        let meaningful = result.filter { $0.text.count >= 25 }
        return meaningful.isEmpty ? result.filter { !$0.text.isEmpty } : meaningful
    }

    static func truncate(_ text: String, to max: Int) -> String {
        guard text.count > max else { return text }
        let cut = String(text.prefix(max))
        if let r = cut.range(of: "[.!?](?=\\s)", options: [.regularExpression, .backwards]), cut.distance(from: cut.startIndex, to: r.upperBound) > max / 2 {
            return String(cut[..<r.upperBound])
        }
        return cut.trimmingCharacters(in: .whitespaces) + "…"
    }

    // MARK: quotes

    public struct Quote: Equatable {
        public var text: String
        public var author: String?
    }

    private static let authorSplit = try! NSRegularExpression(pattern: "^(.*?)\\s+(?:—|–|--|~)\\s*([^—–]{2,80})$")

    public static func splitAuthor(_ raw: String) -> Quote {
        let s = raw.trimmingCharacters(in: .whitespaces)
        let ns = s as NSString
        if let m = authorSplit.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) {
            return Quote(text: stripQuotes(ns.substring(with: m.range(at: 1))), author: ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces))
        }
        return Quote(text: stripQuotes(s), author: nil)
    }

    static func stripQuotes(_ s: String) -> String {
        s.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”' ").union(.whitespaces))
    }

    /// Blockquotes and list items in a quotes note become individual quotes.
    public static func quotes(_ body: String) -> [Quote] {
        var result: [Quote] = []
        var block: [String] = []

        func flushBlock() {
            guard !block.isEmpty else { return }
            var lines = block
            var author: String?
            if let last = lines.last, let a = attribution(last) { author = a; lines.removeLast() }
            let joined = cleanInline(lines.joined(separator: " "))
            var q = splitAuthor(joined)
            if q.author == nil { q.author = author }
            if q.text.count >= 12 { result.append(q) }
            block = []
        }

        for line in stripCodeBlocks(body).components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix(">") {
                let inner = String(t.drop(while: { $0 == ">" || $0 == " " }))
                if inner.hasPrefix("[!") { continue } // callout header
                if inner.isEmpty { flushBlock() } else { block.append(inner) }
                continue
            }
            flushBlock()
            if let a = attribution(t), !result.isEmpty, result[result.count - 1].author == nil {
                result[result.count - 1].author = a // attribution on the line after a quote
            } else if let item = listItemText(t) {
                let q = splitAuthor(cleanInline(item))
                if q.text.count >= 12 { result.append(q) }
            }
        }
        flushBlock()
        return result
    }

    static func attribution(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        for prefix in ["— ", "– ", "-- ", "~ "] where t.hasPrefix(prefix) {
            let a = cleanInline(String(t.dropFirst(prefix.count)))
            return a.isEmpty ? nil : a
        }
        return nil
    }
}
