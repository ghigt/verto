import AppKit
import SwiftUI

/// Rendu Markdown du résultat. `AttributedString(markdown:)` ne gère que l'inline côté SwiftUI
/// (gras, italique, code, liens) : les blocs (titres, listes, code, citations, tableaux) sont
/// découpés ici, puis chaque bloc délègue son texte à l'inline.
enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case code(language: String?, code: String)
    case list([ListItem])
    case quote([MarkdownBlock])
    case table(header: [String], alignments: [HorizontalAlignment], rows: [[String]])
    case rule

    struct ListItem {
        enum Marker { case bullet, number(String), task(done: Bool) }
        var level: Int
        var marker: Marker
        var text: String
    }
}

enum MarkdownParser {
    static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var i = 0

        func flush() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph = []
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flush()
                i += 1
                continue
            }

            // Bloc de code : un bloc non fermé (en cours de streaming) court jusqu'à la fin.
            if let fence = Fence(line) {
                flush()
                var code: [String] = []
                i += 1
                while i < lines.count, !fence.isClosed(by: lines[i]) {
                    code.append(lines[i])
                    i += 1
                }
                i += 1
                blocks.append(.code(language: fence.language, code: code.joined(separator: "\n")))
                continue
            }

            if let (level, title) = heading(trimmed) {
                flush()
                blocks.append(.heading(level: level, text: title))
                i += 1
                continue
            }

            if isRule(trimmed) {
                flush()
                blocks.append(.rule)
                i += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flush()
                var inner: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix(">") else { break }
                    var content = t.dropFirst()
                    if content.first == " " { content = content.dropFirst() }
                    inner.append(String(content))
                    i += 1
                }
                blocks.append(.quote(parse(inner.joined(separator: "\n"))))
                continue
            }

            if listItem(line) != nil {
                flush()
                var items: [MarkdownBlock.ListItem] = []
                while i < lines.count {
                    let l = lines[i]
                    if let item = listItem(l) {
                        items.append(item)
                    } else if l.trimmingCharacters(in: .whitespaces).isEmpty {
                        // Liste « aérée » : une ligne vide entre deux éléments ne la coupe pas.
                        guard i + 1 < lines.count, listItem(lines[i + 1]) != nil else { break }
                    } else if l.first == " " || l.first == "\t", !items.isEmpty {
                        items[items.count - 1].text += "\n" + l.trimmingCharacters(in: .whitespaces)
                    } else {
                        break
                    }
                    i += 1
                }
                blocks.append(.list(items))
                continue
            }

            if trimmed.hasPrefix("|"), i + 1 < lines.count, let alignments = tableSeparator(lines[i + 1]) {
                flush()
                let header = cells(trimmed)
                var rows: [[String]] = []
                i += 2
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix("|") else { break }
                    rows.append(cells(t))
                    i += 1
                }
                blocks.append(.table(header: header, alignments: alignments, rows: rows))
                continue
            }

            paragraph.append(line)
            i += 1
        }
        flush()
        return blocks
    }

    private struct Fence {
        let char: Character
        let length: Int
        let language: String?

        init?(_ line: String) {
            let t = line.drop(while: { $0 == " " })
            guard line.count - t.count <= 3, let c = t.first, c == "`" || c == "~" else { return nil }
            let run = t.prefix(while: { $0 == c }).count
            guard run >= 3 else { return nil }
            let info = t.dropFirst(run).trimmingCharacters(in: .whitespaces)
            if c == "`" && info.contains("`") { return nil }
            char = c
            length = run
            let lang = info.split(separator: " ").first.map(String.init)
            language = lang?.isEmpty == false ? lang : nil
        }

        func isClosed(by line: String) -> Bool {
            let t = line.trimmingCharacters(in: .whitespaces)
            return t.count >= length && t.allSatisfy { $0 == char }
        }
    }

    private static func heading(_ trimmed: String) -> (Int, String)? {
        let level = trimmed.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level) else { return nil }
        let rest = trimmed.dropFirst(level)
        guard rest.isEmpty || rest.first == " " else { return nil }
        var title = rest.trimmingCharacters(in: .whitespaces)
        // `## Titre ##` : les # fermants sont facultatifs.
        while title.hasSuffix("#") { title.removeLast() }
        return (level, title.trimmingCharacters(in: .whitespaces))
    }

    private static func isRule(_ trimmed: String) -> Bool {
        let compact = trimmed.filter { $0 != " " }
        guard compact.count >= 3, let c = compact.first, "-*_".contains(c) else { return false }
        return compact.allSatisfy { $0 == c }
    }

    private static func listItem(_ line: String) -> MarkdownBlock.ListItem? {
        var indent = 0
        for c in line {
            if c == " " { indent += 1 } else if c == "\t" { indent += 4 } else { break }
        }
        var rest = Substring(line).drop(while: { $0 == " " || $0 == "\t" })
        var marker: MarkdownBlock.ListItem.Marker
        if let c = rest.first, "-*+".contains(c) {
            marker = .bullet
            rest = rest.dropFirst()
        } else {
            let digits = rest.prefix(while: { $0.isASCII && $0.isNumber })
            guard (1...9).contains(digits.count), let p = rest.dropFirst(digits.count).first, p == "." || p == ")" else {
                return nil
            }
            marker = .number(digits + ".")
            rest = rest.dropFirst(digits.count + 1)
        }
        guard rest.first == " " || rest.first == "\t" else { return nil }
        rest = rest.drop(while: { $0 == " " || $0 == "\t" })
        if case .bullet = marker {
            for (box, done) in [("[ ] ", false), ("[x] ", true), ("[X] ", true)] where rest.hasPrefix(box) {
                marker = .task(done: done)
                rest = rest.dropFirst(box.count)
            }
        }
        return .init(level: min(indent / 2, 6), marker: marker, text: String(rest))
    }

    private static func cells(_ row: String) -> [String] {
        var t = Substring(row)
        if t.hasPrefix("|") { t = t.dropFirst() }
        if t.hasSuffix("|") { t = t.dropLast() }
        return t.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func tableSeparator(_ line: String) -> [HorizontalAlignment]? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("-"), t.hasPrefix("|") || t.contains("|") else { return nil }
        var alignments: [HorizontalAlignment] = []
        for cell in cells(t) {
            let left = cell.hasPrefix(":"), right = cell.hasSuffix(":")
            let dashes = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            guard !dashes.isEmpty, dashes.allSatisfy({ $0 == "-" }) else { return nil }
            alignments.append(left && right ? .center : right ? .trailing : .leading)
        }
        return alignments
    }

    /// Inline : gras, italique, barré, `code`, liens. Les retours à la ligne sont conservés.
    static func inline(_ text: String, size: CGFloat) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        var result = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        let codeRanges = result.runs
            .filter { $0.inlinePresentationIntent?.contains(.code) == true }
            .map(\.range)
        for range in codeRanges {
            result[range].font = .system(size: size * 0.88, design: .monospaced)
            result[range].backgroundColor = Color.primary.opacity(0.08)
        }
        return result
    }
}

// MARK: - Vues

struct MarkdownView: View {
    let text: String
    var fontSize: CGFloat = 15

    var body: some View {
        MarkdownBlocksView(blocks: MarkdownParser.parse(text), fontSize: fontSize)
    }
}

private struct MarkdownBlocksView: View {
    let blocks: [MarkdownBlock]
    let fontSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            Text(MarkdownParser.inline(text, size: fontSize))
                .font(.system(size: headingSize(level), weight: level <= 2 ? .bold : .semibold))
                .padding(.top, level <= 2 ? 4 : 2)
        case let .paragraph(text):
            Text(MarkdownParser.inline(text, size: fontSize))
                .font(.system(size: fontSize))
        case let .code(language, code):
            CodeBlockView(language: language, code: code)
        case let .list(items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    listRow(item)
                }
            }
        case let .quote(inner):
            MarkdownBlocksView(blocks: inner, fontSize: fontSize)
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5).fill(Color.secondary.opacity(0.4)).frame(width: 3)
                }
        case let .table(header, alignments, rows):
            tableView(header: header, alignments: alignments, rows: rows)
        case .rule:
            Divider().padding(.vertical, 4)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return fontSize + 6
        case 2: return fontSize + 3
        case 3: return fontSize + 1
        default: return fontSize
        }
    }

    private func listRow(_ item: MarkdownBlock.ListItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Group {
                switch item.marker {
                case .bullet:
                    Text(item.level == 0 ? "•" : "◦")
                case let .number(n):
                    Text(n).monospacedDigit()
                case let .task(done):
                    Image(systemName: done ? "checkmark.square.fill" : "square")
                        .foregroundStyle(done ? Color.accentColor : Color.secondary)
                }
            }
            .font(.system(size: fontSize))
            .foregroundStyle(.secondary)
            .frame(minWidth: 14, alignment: .trailing)
            Text(MarkdownParser.inline(item.text, size: fontSize))
                .font(.system(size: fontSize))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, CGFloat(item.level) * 18)
    }

    private func tableView(header: [String], alignments: [HorizontalAlignment], rows: [[String]]) -> some View {
        let columns = max(header.count, rows.map(\.count).max() ?? 0)
        func cell(_ row: [String], _ column: Int) -> String { column < row.count ? row[column] : "" }
        func alignment(_ column: Int) -> HorizontalAlignment { column < alignments.count ? alignments[column] : .leading }
        return ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                GridRow {
                    ForEach(0..<columns, id: \.self) { c in
                        Text(MarkdownParser.inline(cell(header, c), size: fontSize - 1))
                            .fontWeight(.semibold)
                            .gridColumnAlignment(alignment(c))
                    }
                }
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(0..<columns, id: \.self) { c in
                            Text(MarkdownParser.inline(cell(row, c), size: fontSize - 1))
                        }
                    }
                }
            }
            .font(.system(size: fontSize - 1))
            .padding(.vertical, 2)
        }
    }
}

private struct CodeBlockView: View {
    let language: String?
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(code, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Copier le code")
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(SyntaxHighlighter.highlight(code, language: language))
                    .font(.system(size: 12.5, design: .monospaced))
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
                    .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}
