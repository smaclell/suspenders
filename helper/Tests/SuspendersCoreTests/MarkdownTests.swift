import XCTest
@testable import SuspendersCore

final class MarkdownTests: XCTestCase {
    func testFrontmatterTagsInlineList() {
        let (fm, body) = Markdown.splitFrontmatter("---\ntitle: X\ntags: [nudge, Reading]\n---\nBody")
        XCTAssertEqual(Markdown.frontmatterTags(fm), ["nudge", "reading"])
        XCTAssertEqual(body, "Body")
    }

    func testFrontmatterTagsYamlList() {
        let (fm, _) = Markdown.splitFrontmatter("---\ntags:\n  - anki\n  - \"#ideas\"\naliases: [a]\n---\n")
        XCTAssertEqual(Markdown.frontmatterTags(fm), ["anki", "ideas"])
    }

    func testInlineTagsIgnoreHeadingsAndCode() {
        let body = "# Heading\nSome text #Nudge and #anki/books\n```\n#notatag\n```\nColour #123 hex"
        XCTAssertEqual(Markdown.inlineTags(body), ["nudge", "anki/books"])
    }

    func testMatchingTagSupportsNested() {
        XCTAssertEqual(Markdown.matchingTag(["anki/books"], wanted: ["nudge", "anki"]), "anki")
        XCTAssertNil(Markdown.matchingTag(["ankify"], wanted: ["anki"]))
    }

    func testCleanInline() {
        XCTAssertEqual(Markdown.cleanInline("Read **[[Deep Work|this]]** and [site](http://x) ==now== #nudge"), "Read this and site now")
    }

    func testPassagesGroupByHeading() {
        let body = """
        Intro line that is short.

        ## Why
        \(String(repeating: "Presence matters. ", count: 12))

        Another paragraph here.

        ## How
        - Put the phone away
        - Read at night
        """
        let passages = Markdown.passages(body)
        XCTAssertTrue(passages.contains { $0.heading == "Why" })
        XCTAssertTrue(passages.contains { $0.heading == "How" && $0.text.contains("• Put the phone away") })
        XCTAssertTrue(passages.allSatisfy { $0.text.count <= 701 })
    }

    func testQuotesFromBlockquotesAndLists() {
        let body = """
        > The obstacle is the way.
        — Marcus Aurelius

        > [!quote]
        > Be where your feet are and nowhere else.

        - "Simplicity is prerequisite for reliability." — Dijkstra
        - short
        """
        let quotes = Markdown.quotes(body)
        XCTAssertEqual(quotes, [
            .init(text: "The obstacle is the way.", author: "Marcus Aurelius"),
            .init(text: "Be where your feet are and nowhere else.", author: nil),
            .init(text: "Simplicity is prerequisite for reliability.", author: "Dijkstra"),
        ])
    }

    func testSnippetsOnlyForTaggedNotes() {
        let config = Config()
        XCTAssertTrue(VaultIndex.snippetsFor(text: "No tags here at all, just words.", relativePath: "a.md", vaultName: "V", config: config).isEmpty)
        let s = VaultIndex.snippetsFor(text: "---\ntags: nudge\n---\nI am someone who rests well and shows up rested.", relativePath: "Dir/Who I am.md", vaultName: "My Vault", config: config)
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].title, "Who I am")
        XCTAssertEqual(s[0].kind, .note)
        XCTAssertEqual(s[0].obsidianURL, "obsidian://open?vault=My%20Vault&file=Dir/Who%20I%20am")
    }

    func testScheduleWrapsMidnight() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = { (h: Int, m: Int) in cal.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: h, minute: m))! }
        XCTAssertTrue(Schedule.isWithin(date(23, 0), from: "22:00", to: "05:00", calendar: cal))
        XCTAssertTrue(Schedule.isWithin(date(1, 0), from: "22:00", to: "05:00", calendar: cal))
        XCTAssertFalse(Schedule.isWithin(date(12, 0), from: "22:00", to: "05:00", calendar: cal))
        XCTAssertEqual(Schedule.minutesSince("22:00", until: "05:00", at: date(0, 30), calendar: cal), 150)
        XCTAssertEqual(Schedule.nightKey(date(1, 0), morning: "05:00", calendar: cal), "2026-11-15")
    }
}
