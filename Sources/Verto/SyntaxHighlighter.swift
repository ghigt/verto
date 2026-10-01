import AppKit
import SwiftUI

/// Coloration syntaxique légère, sans dépendance : un tokenizer unique (commentaires, chaînes,
/// nombres, mots-clés, types, appels de fonction) paramétré par langage. Couleurs du thème
/// par défaut de Xcode, en clair comme en sombre.
enum SyntaxHighlighter {
    static func highlight(_ code: String, language: String?) -> AttributedString {
        guard let language, let spec = LanguageSpec.named(language) else { return AttributedString(code) }
        var tokenizer = Tokenizer(code: code, spec: spec)
        return tokenizer.run()
    }

    enum Token {
        case keyword, string, comment, number, type, function, attribute

        var color: Color {
            switch self {
            case .keyword: return Self.dynamic(0x9B2393, 0xFC5FA3)
            case .string: return Self.dynamic(0xC41A16, 0xFC6A5D)
            case .comment: return Self.dynamic(0x5D6C79, 0x7F8C98)
            case .number: return Self.dynamic(0x1C00CF, 0xD0BF69)
            case .type: return Self.dynamic(0x0B4F79, 0x5DD8FF)
            case .function: return Self.dynamic(0x326D74, 0x67B7A4)
            case .attribute: return Self.dynamic(0x815F03, 0xFD8F3F)
            }
        }

        private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
                return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                               green: CGFloat((hex >> 8) & 0xFF) / 255,
                               blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
            })
        }
    }
}

struct LanguageSpec {
    var keywords: Set<String> = []
    var literals: Set<String> = []
    var lineComments: [String] = []
    var blockComment: (start: String, end: String)?
    var quotes: Set<Character> = ["\"", "'"]
    /// Préfixes d'identifiant colorés à part : `@decorator`, `$VAR`, `#if`…
    var prefixes: Set<Character> = []
    var caseInsensitive = false
    /// Identifiants en Majuscule = types.
    var capitalizedTypes = true
    /// Clé suivie de `:` (JSON, YAML, CSS) ou `=` (TOML) colorée comme attribut.
    var keySeparators: Set<Character> = []
    /// HTML / XML : noms de balise et attributs.
    var markup = false

    static func named(_ name: String) -> LanguageSpec? {
        switch name.lowercased() {
        case "swift": return swift
        case "python", "py", "python3": return python
        case "javascript", "js", "jsx", "mjs", "cjs", "typescript", "ts", "tsx": return javascript
        case "json", "jsonc", "json5": return json
        case "bash", "sh", "shell", "zsh", "console", "shellsession", "fish": return shell
        case "go", "golang": return go
        case "rust", "rs": return rust
        case "c", "h", "cpp", "c++", "cc", "hpp", "cxx", "objc", "objective-c", "objectivec", "m", "mm": return cFamily
        case "cs", "csharp", "c#": return csharp
        case "java", "kotlin", "kt", "kts", "scala", "groovy", "dart": return jvm
        case "ruby", "rb": return ruby
        case "php": return php
        case "sql", "mysql", "postgresql", "postgres", "sqlite", "plsql": return sql
        case "html", "xml", "svg", "xhtml", "vue", "plist", "xaml": return markupSpec
        case "css", "scss", "sass", "less": return css
        case "yaml", "yml": return yaml
        case "toml", "ini", "conf", "properties": return toml
        case "lua": return lua
        case "dockerfile", "docker": return dockerfile
        default: return nil
        }
    }

    private static func words(_ s: String) -> Set<String> { Set(s.split(separator: " ").map(String.init)) }

    static let swift = LanguageSpec(
        keywords: words("associatedtype class deinit enum extension fileprivate func import init inout internal let open operator private precedencegroup protocol public rethrows static struct subscript typealias var break case catch continue default defer do else fallthrough for guard if in repeat return throw switch where while as is try await async throws some any self Self super get set willSet didSet mutating nonmutating override lazy weak unowned final required convenience indirect actor nonisolated isolated consuming borrowing"),
        literals: words("true false nil"),
        lineComments: ["//"], blockComment: ("/*", "*/"), quotes: ["\""], prefixes: ["@", "#"]
    )
    static let python = LanguageSpec(
        keywords: words("and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield match case self cls print"),
        literals: words("True False None"),
        lineComments: ["#"], prefixes: ["@"]
    )
    static let javascript = LanguageSpec(
        keywords: words("break case catch class const continue debugger default delete do else export extends finally for function if import in instanceof let new return super switch this throw try typeof var void while with yield async await of static get set from as interface type enum implements namespace declare readonly private protected public abstract keyof infer satisfies"),
        literals: words("true false null undefined NaN Infinity"),
        lineComments: ["//"], blockComment: ("/*", "*/"), quotes: ["\"", "'", "`"], prefixes: ["@"]
    )
    static let json = LanguageSpec(
        literals: words("true false null"), lineComments: ["//"], blockComment: ("/*", "*/"), quotes: ["\""],
        capitalizedTypes: false, keySeparators: [":"]
    )
    static let shell = LanguageSpec(
        keywords: words("if then else elif fi case esac for while until do done in function select return exit export local readonly declare unset source alias echo cd sudo set shift trap eval exec"),
        literals: words("true false"),
        lineComments: ["#"], prefixes: ["$"], capitalizedTypes: false
    )
    static let go = LanguageSpec(
        keywords: words("break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var"),
        literals: words("true false nil iota"),
        lineComments: ["//"], blockComment: ("/*", "*/"), quotes: ["\"", "'", "`"]
    )
    static let rust = LanguageSpec(
        keywords: words("as async await break const continue crate dyn else enum extern fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait type unsafe use where while macro_rules"),
        literals: words("true false None Some Ok Err"),
        lineComments: ["//"], blockComment: ("/*", "*/"), quotes: ["\""], prefixes: ["#"]
    )
    static let cFamily = LanguageSpec(
        keywords: words("auto break case char const continue default do double else enum extern float for goto if inline int long register restrict return short signed sizeof static struct switch typedef union unsigned void volatile while bool class namespace template typename public private protected virtual override final new delete this throw try catch using constexpr nullptr noexcept explicit friend operator mutable static_cast dynamic_cast reinterpret_cast const_cast decltype interface implementation end property self super id instancetype nonatomic strong weak"),
        literals: words("true false NULL nullptr nil YES NO"),
        lineComments: ["//"], blockComment: ("/*", "*/"), prefixes: ["#", "@"]
    )
    static let csharp = LanguageSpec(
        keywords: words("abstract as base bool break byte case catch char checked class const continue decimal default delegate do double else enum event explicit extern finally fixed float for foreach goto if implicit in int interface internal is lock long namespace new object operator out override params private protected public readonly ref return sbyte sealed short sizeof stackalloc static string struct switch this throw try typeof uint ulong unchecked unsafe ushort using virtual void volatile while var async await get set record init yield"),
        literals: words("true false null"),
        lineComments: ["//"], blockComment: ("/*", "*/"), prefixes: ["#", "@"]
    )
    static let jvm = LanguageSpec(
        keywords: words("abstract assert boolean break byte case catch char class const continue default do double else enum extends final finally float for goto if implements import instanceof int interface long native new package private protected public return short static strictfp super switch synchronized this throw throws transient try void volatile while var val fun object when is in out data sealed open override companion lateinit suspend internal inline reified typealias def trait yield record"),
        literals: words("true false null"),
        lineComments: ["//"], blockComment: ("/*", "*/"), quotes: ["\"", "'"], prefixes: ["@"]
    )
    static let ruby = LanguageSpec(
        keywords: words("alias and begin break case class def defined? do else elsif end ensure for if in module next not or redo rescue retry return self super then undef unless until when while yield require require_relative attr_accessor attr_reader attr_writer puts private protected public lambda proc"),
        literals: words("true false nil"),
        lineComments: ["#"], prefixes: ["@", "$", ":"]
    )
    static let php = LanguageSpec(
        keywords: words("abstract and array as break callable case catch class clone const continue declare default do echo else elseif empty enddeclare endfor endforeach endif endswitch endwhile extends final finally fn for foreach function global goto if implements include include_once instanceof insteadof interface isset list match namespace new or print private protected public readonly require require_once return static switch throw trait try unset use var while xor yield"),
        literals: words("true false null TRUE FALSE NULL"),
        lineComments: ["//", "#"], blockComment: ("/*", "*/"), prefixes: ["$"]
    )
    static let sql = LanguageSpec(
        keywords: words("select from where and or not insert into values update set delete create table drop alter add column index view primary key foreign references join inner left right outer full cross on as group by order having limit offset distinct union all exists in between like is case when then else end begin commit rollback transaction with returning default constraint unique check asc desc count sum avg min max cast coalesce if replace database schema grant revoke trigger procedure function returns declare int integer bigint varchar text boolean date timestamp serial float real numeric char"),
        literals: words("null true false"),
        lineComments: ["--"], blockComment: ("/*", "*/"), caseInsensitive: true, capitalizedTypes: false
    )
    static let markupSpec = LanguageSpec(
        blockComment: ("<!--", "-->"), capitalizedTypes: false, markup: true
    )
    static let css = LanguageSpec(
        keywords: words("important media import from to and not only keyframes supports font-face root hover focus active before after"),
        lineComments: ["//"], blockComment: ("/*", "*/"), prefixes: ["@", "$", "-"], capitalizedTypes: false, keySeparators: [":"]
    )
    static let yaml = LanguageSpec(
        literals: words("true false null yes no on off ~"),
        lineComments: ["#"], prefixes: ["&", "*", "!"], capitalizedTypes: false, keySeparators: [":"]
    )
    static let toml = LanguageSpec(
        literals: words("true false"),
        lineComments: ["#", ";"], capitalizedTypes: false, keySeparators: ["="]
    )
    static let lua = LanguageSpec(
        keywords: words("and break do else elseif end for function goto if in local not or repeat return then until while require self"),
        literals: words("true false nil"),
        lineComments: ["--"], blockComment: ("--[[", "]]")
    )
    static let dockerfile = LanguageSpec(
        keywords: words("FROM RUN CMD LABEL EXPOSE ENV ADD COPY ENTRYPOINT VOLUME USER WORKDIR ARG ONBUILD STOPSIGNAL HEALTHCHECK SHELL AS"),
        lineComments: ["#"], prefixes: ["$"], capitalizedTypes: false
    )
}

private struct Tokenizer {
    let chars: [Character]
    let spec: LanguageSpec
    var i = 0
    var output = AttributedString()
    var plain = ""
    var inTag = false

    init(code: String, spec: LanguageSpec) {
        chars = Array(code)
        self.spec = spec
    }

    mutating func run() -> AttributedString {
        // Le commentaire de ligne le plus long d'abord (`--[[` avant `--`).
        let lineComments = spec.lineComments.sorted { $0.count > $1.count }
        while i < chars.count {
            let c = chars[i]

            if let block = spec.blockComment, matches(block.start) {
                let start = i
                i += block.start.count
                while i < chars.count, !matches(block.end) { i += 1 }
                i = min(i + block.end.count, chars.count)
                emit(start, .comment)
                continue
            }

            if !spec.markup, lineComments.contains(where: { matches($0) }) {
                let start = i
                while i < chars.count, chars[i] != "\n" { i += 1 }
                emit(start, .comment)
                continue
            }

            if spec.markup {
                if c == "<" {
                    plainChar(c)
                    i += 1
                    if i < chars.count, chars[i] == "/" || chars[i] == "!" || chars[i] == "?" {
                        plainChar(chars[i])
                        i += 1
                    }
                    let start = i
                    while i < chars.count, isIdentifierChar(chars[i]) || chars[i] == "-" || chars[i] == ":" { i += 1 }
                    emit(start, .keyword)
                    inTag = true
                    continue
                }
                if c == ">" { inTag = false }
                if !inTag {
                    plainChar(c)
                    i += 1
                    continue
                }
            }

            if spec.quotes.contains(c) || (spec.markup && (c == "\"" || c == "'")) {
                let start = i
                scanString(quote: c)
                emit(start, isKey() ? .attribute : .string)
                continue
            }

            if c.isASCII && c.isNumber {
                let start = i
                while i < chars.count, chars[i].isLetter || chars[i].isNumber || chars[i] == "." || chars[i] == "_" {
                    if chars[i] == ".", i + 1 < chars.count, !chars[i + 1].isNumber { break }
                    i += 1
                }
                emit(start, .number)
                continue
            }

            if spec.prefixes.contains(c), isPrefixedIdentifier(at: i) {
                let start = i
                i += 1
                if c == "$", i < chars.count, chars[i] == "{" {
                    while i < chars.count, chars[i] != "}" { i += 1 }
                    i = min(i + 1, chars.count)
                } else if c == "$", i < chars.count, "?@#!*0123456789".contains(chars[i]) {
                    i += 1
                } else {
                    while i < chars.count, isIdentifierChar(chars[i]) || chars[i] == "-" { i += 1 }
                }
                let prefixed = String(chars[start..<i])
                emit(start, spec.keywords.contains(String(prefixed.dropFirst())) ? .keyword : .attribute)
                continue
            }

            if c.isLetter || c == "_" {
                let start = i
                while i < chars.count, isIdentifierChar(chars[i]) || (spec.keySeparators.contains(":") && chars[i] == "-") { i += 1 }
                if i < chars.count, chars[i] == "?" || chars[i] == "!", spec.keywords.contains(String(chars[start...i])) { i += 1 }
                let word = String(chars[start..<i])
                emit(start, classify(word))
                continue
            }

            plainChar(c)
            i += 1
        }
        flushPlain()
        return output
    }

    private func classify(_ word: String) -> SyntaxHighlighter.Token? {
        let key = spec.caseInsensitive ? word.lowercased() : word
        if spec.markup { return .function } // attribut dans une balise
        if isKey() { return .attribute }
        if spec.keywords.contains(key) { return .keyword }
        if spec.literals.contains(key) { return .number }
        if nextNonSpace() == "(" { return .function }
        if spec.capitalizedTypes, word.first?.isUppercase == true { return .type }
        return nil
    }

    private func isKey() -> Bool {
        guard !spec.keySeparators.isEmpty, let next = nextNonSpace(), spec.keySeparators.contains(next) else { return false }
        // CSS : `a:hover` n'est pas une propriété ; on exige un espace ou une fin de ligne après `:`.
        if next == ":", let after = charAfterNextNonSpace() { return after == " " || after == "\n" || after == "\t" }
        return true
    }

    private func nextNonSpace() -> Character? {
        var j = i
        while j < chars.count, chars[j] == " " { j += 1 }
        return j < chars.count ? chars[j] : nil
    }

    private func charAfterNextNonSpace() -> Character? {
        var j = i
        while j < chars.count, chars[j] == " " { j += 1 }
        return j + 1 < chars.count ? chars[j + 1] : nil
    }

    private func isIdentifierChar(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }

    private func isPrefixedIdentifier(at index: Int) -> Bool {
        guard index + 1 < chars.count else { return false }
        if index > 0, isIdentifierChar(chars[index - 1]) || chars[index - 1] == chars[index] { return false }
        let next = chars[index + 1]
        if chars[index] == "$" { return isIdentifierChar(next) || next == "{" || "?@#!*0123456789".contains(next) }
        return next.isLetter || next == "_" || (chars[index] == "-" && next == "-")
    }

    private func matches(_ s: String) -> Bool {
        var j = i
        for c in s {
            guard j < chars.count, chars[j] == c else { return false }
            j += 1
        }
        return true
    }

    private mutating func scanString(quote: Character) {
        let triple = String(repeating: quote, count: 3)
        if matches(triple) {
            i += 3
            while i < chars.count, !matches(triple) {
                if chars[i] == "\\" { i += 1 }
                i += 1
            }
            i = min(i + 3, chars.count)
            return
        }
        i += 1
        while i < chars.count, chars[i] != quote {
            if chars[i] == "\\" { i += 1 }
            else if chars[i] == "\n", quote != "`" { break }
            i += 1
        }
        i = min(i + 1, chars.count)
    }

    private mutating func plainChar(_ c: Character) { plain.append(c) }

    private mutating func flushPlain() {
        guard !plain.isEmpty else { return }
        output.append(AttributedString(plain))
        plain = ""
    }

    private mutating func emit(_ start: Int, _ token: SyntaxHighlighter.Token?) {
        guard start < i else { return }
        let text = String(chars[start..<min(i, chars.count)])
        guard let token else {
            plain += text
            return
        }
        flushPlain()
        var piece = AttributedString(text)
        piece.foregroundColor = token.color
        output.append(piece)
    }
}
