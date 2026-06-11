import SwiftUI

enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case bullet(indent: Int, text: String)
    case numbered(indent: Int, marker: String, text: String)
    case paragraph(String)
}

enum MarkdownParser {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        for rawLine in markdown.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let leading = rawLine.prefix { $0 == " " || $0 == "\t" }
            let indentWidth = leading.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            let indent = min(indentWidth / 2, 4)

            if trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix(while: { $0 == "#" })
                let rest = trimmed.dropFirst(hashes.count)
                if hashes.count <= 6, rest.hasPrefix(" ") {
                    let text = rest.trimmingCharacters(in: .whitespaces)
                    if !text.isEmpty {
                        blocks.append(.heading(level: hashes.count, text: text))
                        continue
                    }
                }
            }
            if let text = bulletText(of: trimmed) {
                blocks.append(.bullet(indent: indent, text: text))
                continue
            }
            if let (marker, text) = numberedText(of: trimmed) {
                blocks.append(.numbered(indent: indent, marker: marker, text: text))
                continue
            }
            blocks.append(.paragraph(trimmed))
        }
        return blocks
    }

    private static func bulletText(of line: String) -> String? {
        for prefix in ["- ", "* ", "• "] where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func numberedText(of line: String) -> (String, String)? {
        let digits = line.prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return ("\(digits).", String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces))
    }
}

struct MarkdownBlocksView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            ForEach(Array(MarkdownParser.parse(markdown).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inline(text)
                .font(headingFont(level))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, level <= 2 ? 16 : 8)
        case .bullet(let indent, let text):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(indent == 0 ? "•" : "◦")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textTertiary)
                inline(text)
                    .font(.system(size: 14.5))
                    .lineSpacing(4.5)
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.leading, CGFloat(indent) * 18)
        case .numbered(let indent, let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(marker)
                    .font(.system(size: 13.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
                inline(text)
                    .font(.system(size: 14.5))
                    .lineSpacing(4.5)
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.leading, CGFloat(indent) * 18)
        case .paragraph(let text):
            inline(text)
                .font(.system(size: 14.5))
                .lineSpacing(4.5)
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func inline(_ text: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        {
            return Text(attributed)
        }
        return Text(text)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .system(size: 21, weight: .semibold, design: .serif)
        case 2: return .system(size: 18, weight: .semibold, design: .serif)
        default: return .system(size: 15.5, weight: .semibold)
        }
    }
}
