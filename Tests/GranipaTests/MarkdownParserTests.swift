import Testing

@testable import Granipa

@Suite struct MarkdownParserTests {
    @Test func parsesHeadingsBulletsAndParagraphs() {
        let blocks = MarkdownParser.parse(
            """
            ## Decisions
            - Launch moved to July
              - Backend ready
            Plain closing line.
            """)
        #expect(
            blocks == [
                .heading(level: 2, text: "Decisions"),
                .bullet(indent: 0, text: "Launch moved to July"),
                .bullet(indent: 1, text: "Backend ready"),
                .paragraph("Plain closing line."),
            ])
    }

    @Test func parsesNumberedLists() {
        let blocks = MarkdownParser.parse("1. First\n2) Second")
        #expect(
            blocks == [
                .numbered(indent: 0, marker: "1.", text: "First"),
                .numbered(indent: 0, marker: "2.", text: "Second"),
            ])
    }

    @Test func hashtagWithoutSpaceIsNotAHeading() {
        #expect(MarkdownParser.parse("#topic") == [.paragraph("#topic")])
    }

    @Test func skipsBlankLines() {
        let blocks = MarkdownParser.parse("\n\n- one\n\n\n- two\n")
        #expect(blocks.count == 2)
    }

    @Test func yearIsNotANumberedItem() {
        #expect(MarkdownParser.parse("2026. A great year") == [.paragraph("2026. A great year")])
    }

    @Test func prefixParseMatchesFullParseAndStopsEarly() {
        let markdown = "## Decisions\n- Launch moved to July\n- ignored filler\nplain closer\n"
        let full = MarkdownParser.parse(markdown)
        let prefix = MarkdownParser.parse(markdown, maxBlocks: 2)
        #expect(prefix.blocks == Array(full.prefix(2)))
        #expect(prefix.linesVisited == 2)
        #expect(full.count == 4)

        let leading = MarkdownParser.parse("\n\nHello\nWorld\n", maxBlocks: 2)
        #expect(leading.blocks == [.paragraph("Hello"), .paragraph("World")])
        #expect(leading.linesVisited == 4)
        #expect(MarkdownParser.parse("", maxBlocks: 2).blocks.isEmpty)
        #expect(MarkdownParser.parse("Hello", maxBlocks: 0).blocks.isEmpty)
    }
}
