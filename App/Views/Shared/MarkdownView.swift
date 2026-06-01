import SwiftUI
#if os(iOS)
import UIKit
#endif

/// A lightweight Markdown renderer for chat output: headings, bullet/numbered
/// lists, fenced code blocks, blockquotes, tables, and inline bold/italic/code/links.
/// SwiftUI's `Text` can't style block elements on its own, so we parse blocks
/// ourselves and render inline spans with AttributedString.
struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(MarkdownParser.parse(text)) { block in
                render(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(.accentColor)
    }

    @ViewBuilder private func render(_ block: MarkdownParser.Block) -> some View {
        switch block.kind {
        case .heading(let level):
            Text(inline(block.text))
                .font(headingFont(level)).fontWeight(.semibold)
                .padding(.top, level <= 2 ? 4 : 1)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                Text(inline(block.text)).frame(maxWidth: .infinity, alignment: .leading)
            }
        case .numbered(let n):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(n).").foregroundStyle(.secondary).monospacedDigit()
                Text(inline(block.text)).frame(maxWidth: .infinity, alignment: .leading)
            }
        case .quote:
            Text(inline(block.text))
                .italic().foregroundStyle(.secondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle().frame(width: 3).foregroundStyle(.secondary.opacity(0.4))
                }
        case .code:
            Text(block.text)
                .font(.system(.callout, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .textSelection(.enabled)
                .overlay(alignment: .topTrailing) {
                    Button {
                        copyToPasteboard(block.text)
                    } label: {
                        Image(systemName: "doc.on.doc").font(.caption2).padding(6)
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
        case .table(let rows):
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(inline(cell)).font(r == 0 ? .callout.bold() : .callout)
                        }
                    }
                    if r == 0 { Divider() }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        case .paragraph:
            Text(inline(block.text))
        }
    }

    private func copyToPasteboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title2
        case 2: .title3
        default: .headline
        }
    }

    private func inline(_ string: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: string, options: options))
            ?? AttributedString(string)
    }
}

enum MarkdownParser {
    struct Block: Identifiable {
        enum Kind: Equatable {
            case heading(Int), bullet, numbered(Int), quote, code, paragraph
            case table([[String]])
        }
        let id = UUID()
        let kind: Kind
        var text: String = ""
    }

    static func parse(_ text: String) -> [Block] {
        var blocks: [Block] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let raw = lines[i]
            // Fenced code block.
            if raw.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                i += 1 // skip closing fence
                blocks.append(Block(kind: .code, text: code.joined(separator: "\n")))
                continue
            }
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { i += 1; continue }

            // GitHub-style table: consecutive lines starting with "|".
            if line.hasPrefix("|") {
                var rows: [[String]] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    var cells = lines[i].split(separator: "|", omittingEmptySubsequences: false)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                    if cells.first == "" { cells.removeFirst() }
                    if cells.last == "" { cells.removeLast() }
                    rows.append(cells)
                    i += 1
                }
                // Drop the |---|---| separator row if present.
                let body = rows.enumerated().filter { idx, row in
                    !(idx == 1 && row.allSatisfy { $0.allSatisfy { "-:| ".contains($0) } })
                }.map(\.element)
                blocks.append(Block(kind: .table(body)))
                continue
            }

            if let (level, rest) = heading(line) {
                blocks.append(Block(kind: .heading(level), text: rest))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                blocks.append(Block(kind: .bullet, text: String(line.dropFirst(2))))
            } else if let (n, rest) = numbered(line) {
                blocks.append(Block(kind: .numbered(n), text: rest))
            } else if line.hasPrefix("> ") {
                blocks.append(Block(kind: .quote, text: String(line.dropFirst(2))))
            } else {
                blocks.append(Block(kind: .paragraph, text: line))
            }
            i += 1
        }
        return blocks
    }

    private static func heading(_ s: String) -> (Int, String)? {
        var level = 0
        var idx = s.startIndex
        while idx < s.endIndex, s[idx] == "#" { level += 1; idx = s.index(after: idx) }
        guard level > 0, level <= 6, idx < s.endIndex, s[idx] == " " else { return nil }
        return (level, String(s[s.index(after: idx)...]))
    }

    private static func numbered(_ s: String) -> (Int, String)? {
        guard let dot = s.firstIndex(of: "."), let n = Int(s[s.startIndex..<dot]) else { return nil }
        let after = s.index(after: dot)
        guard after < s.endIndex, s[after] == " " else { return nil }
        return (n, String(s[s.index(after: after)...]))
    }
}
