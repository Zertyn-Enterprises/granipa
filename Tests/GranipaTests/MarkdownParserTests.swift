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
}
