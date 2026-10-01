import SwiftUI

/// Renders a parsed note with native typography, semantic colours and highlights.
struct NoteContentView: View {
    let blocks: [NoteBlock]

    init(markdown: String) {
        self.blocks = NoteParser.parse(markdown)
    }

    init(blocks: [NoteBlock]) {
        self.blocks = blocks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                NoteBlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}

struct NoteBlockView: View {
    let block: NoteBlock

    var body: some View {
        switch block.kind {
        case .heading(let level, let text):
            Text(InlineMarkdown.attributed(text))
                .font(headingFont(level))
                .padding(.top, level <= 2 ? 10 : 4)
                .accessibilityAddTraits(.isHeader)

        case .paragraph(let text):
            Text(InlineMarkdown.attributed(text))
                .font(.body)
                .lineSpacing(3)

        case .bullet(let text, let indent):
            ListRow(indent: indent) {
                Image(systemName: indent == 0 ? "circle.fill" : "circle")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(.tint)
                    .frame(width: 16)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            } content: {
                Text(InlineMarkdown.attributed(text)).lineSpacing(3)
            }

        case .numbered(let number, let text, let indent):
            ListRow(indent: indent) {
                Text("\(number).")
                    .font(.body.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(minWidth: 16, alignment: .trailing)
            } content: {
                Text(InlineMarkdown.attributed(text)).lineSpacing(3)
            }

        case .task(let text, let done, let indent):
            ListRow(indent: indent) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? Color.green : Color.secondary)
                    .frame(width: 16)
            } content: {
                Text(InlineMarkdown.attributed(text))
                    .strikethrough(done)
                    .foregroundStyle(done ? .secondary : .primary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(done ? "เสร็จแล้ว" : "ยังไม่เสร็จ")

        case .quote(let text):
            HStack(alignment: .top, spacing: 12) {
                Capsule().fill(.quaternary).frame(width: 3)
                Text(InlineMarkdown.attributed(text))
                    .italic()
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .callout(let kind, let title, let blocks):
            CalloutView(kind: kind, title: title, blocks: blocks)

        case .code(let language, let code):
            VStack(alignment: .leading, spacing: 6) {
                if !language.isEmpty {
                    Text(language.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(SyntaxHighlighter.highlight(code, language: language))
                        .font(.system(.callout, design: .monospaced))
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

        case .table(let rows):
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(InlineMarkdown.attributed(cell))
                                    .font(index == 0 ? .subheadline.weight(.semibold) : .subheadline)
                            }
                        }
                        if index == 0 { Divider().gridCellUnsizedAxes(.horizontal) }
                    }
                }
                .padding(.vertical, 4)
            }

        case .divider:
            Divider().padding(.vertical, 6)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .largeTitle.bold()
        case 2: .title2.bold()
        case 3: .title3.weight(.semibold)
        default: .headline
        }
    }
}

private struct ListRow<Marker: View, Content: View>: View {
    let indent: Int
    @ViewBuilder let marker: Marker
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            marker
            content
        }
        .padding(.leading, CGFloat(indent) * 20)
    }
}

struct CalloutView: View {
    let kind: CalloutKind
    let title: String
    let blocks: [NoteBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(InlineMarkdown.attributed(title.isEmpty ? kind.defaultTitle : title))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: kind.symbol)
                    .foregroundStyle(kind.color)
            }
            if !blocks.isEmpty {
                NoteContentView(blocks: blocks)
                    .font(.callout)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(kind.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12)
                .fill(kind.color)
                .frame(width: 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(kind.defaultTitle))
    }
}

/// Lightweight keyword colouring for code blocks.
enum SyntaxHighlighter {
    private static let keywords: Set<String> = [
        "func", "let", "var", "if", "else", "for", "while", "return", "class", "struct", "enum", "import",
        "def", "in", "from", "as", "true", "false", "nil", "None", "True", "False", "const", "function",
        "public", "private", "static", "switch", "case", "break", "continue", "try", "catch", "throw",
        "async", "await", "new", "this", "self", "print", "lambda", "with", "and", "or", "not", "elif",
        "SELECT", "FROM", "WHERE", "JOIN", "INSERT", "UPDATE", "DELETE", "int", "float", "string", "bool", "void",
    ]

    static func highlight(_ code: String, language: String) -> AttributedString {
        var result = AttributedString()
        for (lineIndex, line) in code.components(separatedBy: "\n").enumerated() {
            if lineIndex > 0 { result += AttributedString("\n") }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("#") || trimmed.hasPrefix("--") {
                var comment = AttributedString(line)
                comment.foregroundColor = Color.secondary
                result += comment
                continue
            }
            var token = ""
            var inString: Character?
            func flush() {
                guard !token.isEmpty else { return }
                var piece = AttributedString(token)
                if keywords.contains(token) {
                    piece.foregroundColor = Color.pink
                } else if token.first?.isNumber == true {
                    piece.foregroundColor = Color.orange
                }
                result += piece
                token = ""
            }
            for ch in line {
                if let quote = inString {
                    token.append(ch)
                    if ch == quote {
                        var s = AttributedString(token)
                        s.foregroundColor = Color.green
                        result += s
                        token = ""
                        inString = nil
                    }
                } else if ch == "\"" || ch == "'" {
                    flush()
                    inString = ch
                    token.append(ch)
                } else if ch.isLetter || ch.isNumber || ch == "_" {
                    token.append(ch)
                } else {
                    flush()
                    result += AttributedString(String(ch))
                }
            }
            if inString != nil {
                var s = AttributedString(token)
                s.foregroundColor = Color.green
                result += s
                token = ""
            } else {
                flush()
            }
        }
        return result
    }
}
