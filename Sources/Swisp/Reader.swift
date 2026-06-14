import BigInt
import Foundation

// MARK: - Dispatch Table

var readerDispatchTable: [Character: SExpr] = [:]

// MARK: - Reader

public class Reader {
    public private(set) var input: String
    public private(set) var position: String.Index
    public var line: Int
    public var column: Int

    public init(input: String) {
        self.input = input
        self.position = input.startIndex
        self.line = 1
        self.column = 1
    }

    public func peekChar() -> Character? {
        guard position < input.endIndex else { return nil }
        return input[position]
    }

    @discardableResult
    public func readChar() -> Character? {
        guard position < input.endIndex else { return nil }
        let c = input[position]
        advance()
        return c
    }

    public var isEOF: Bool { position >= input.endIndex }

    private func advance() {
        if position < input.endIndex {
            if input[position] == "\n" {
                line += 1
                column = 1
            } else if input[position] == "\t" {
                column += 4
            } else {
                column += 1
            }
            input.formIndex(after: &position)
        }
    }

    public func location() -> SourceLocation {
        SourceLocation(line: line, column: column)
    }
}

// MARK: - Character Helpers

func isDelimiter(_ c: Character) -> Bool {
    c.isWhitespace
        || c == "(" || c == ")"
        || c == "\"" || c == "'"
        || c == "`" || c == ","
        || c == ";"
}

func isTokenStart(_ c: Character) -> Bool {
    !c.isWhitespace && c != "(" && c != ")"
        && c != "\"" && c != "'"
        && c != "`" && c != ","
        && c != ";"
}

// MARK: - Token Reading

enum ReadError: Error, CustomStringConvertible {
    case unterminatedString(SourceLocation)
    case invalidNumber(SourceLocation, String)
    case unexpected(String)

    var description: String {
        switch self {
        case .unterminatedString(let loc): return "\(loc): unterminated string"
        case .invalidNumber(let loc, let s): return "\(loc): invalid number '\(s)'"
        case .unexpected(let s): return s
        }
    }
}

func readToken(_ reader: Reader) throws -> LocatedToken? {
    reader.skipWhitespaceAndComments()
    guard !reader.isEOF else { return nil }

    let start = reader.location()
    let c = reader.readChar()!

    switch c {
    case "(":
        return LocatedToken(token: .leftParen, location: start)
    case ")":
        return LocatedToken(token: .rightParen, location: start)
    case "'":
        return LocatedToken(token: .quote, location: start)
    case "`":
        return LocatedToken(token: .quasiquote, location: start)
    case ",":
        if let next = reader.peekChar(), next == "@" {
            reader.readChar()
            return LocatedToken(token: .unquoteSplicing, location: start)
        }
        return LocatedToken(token: .unquote, location: start)
    case "\"":
        return try readStringToken(reader, start: start)
    case "#":
        return try readHashToken(reader, start: start)
    case ".":
        if let next = reader.peekChar(), !isDelimiter(next) {
            let sym = readSymbol(reader)
            return LocatedToken(token: .symbol(sym), location: start)
        }
        return LocatedToken(token: .dot, location: start)
    case _ where c.isNumber || c == "-" || c == "+":
        if c.isNumber {
            return try readNumberToken(reader, start: start, first: String(c))
        }
        // - or +: check if followed by number
        if c == "-" || c == "+" {
            if let next = reader.peekChar(), next.isNumber || next == "." {
                return try readNumberToken(reader, start: start, first: String(c))
            }
        }
        let sym = readSymbol(reader, first: String(c))
        return LocatedToken(token: .symbol(sym), location: start)
    default:
        let sym = readSymbol(reader, first: String(c))
        return LocatedToken(token: .symbol(sym), location: start)
    }
}

func readStringToken(_ reader: Reader, start: SourceLocation) throws -> LocatedToken {
    var value = ""
    while let c = reader.readChar() {
        if c == "\"" {
            return LocatedToken(token: .string(value), location: start)
        } else if c == "\\" {
            guard let escaped = reader.readChar() else {
                throw ReadError.unterminatedString(start)
            }
            switch escaped {
            case "\"": value.append("\"")
            case "\\": value.append("\\")
            case "n": value.append("\n")
            case "t": value.append("\t")
            case "r": value.append("\r")
            default: value.append(escaped)
            }
        } else {
            value.append(c)
        }
    }
    throw ReadError.unterminatedString(start)
}

func readHashToken(_ reader: Reader, start: SourceLocation) throws -> LocatedToken {
    guard let c = reader.readChar() else {
        throw ReadError.unexpected("\(start): invalid #")
    }
    switch c {
    case "t": return LocatedToken(token: .boolean(true), location: start)
    case "f": return LocatedToken(token: .boolean(false), location: start)
    default: throw ReadError.unexpected("\(start): invalid '#\(c)'")
    }
}

func readNumberToken(_ reader: Reader, start: SourceLocation, first: String) throws -> LocatedToken {
    var numStr = first
    var hasDot = false

    while let c = reader.peekChar() {
        if c.isNumber {
            numStr.append(c)
            reader.readChar()
        } else if c == "." && !hasDot {
            reader.readChar() // consume the .
            if let next = reader.peekChar(), next.isNumber {
                hasDot = true
                numStr.append(".")
                // next digit picked up in next iteration
            } else {
                // Not a decimal — just a trailing dot
                numStr.append(".")
                break
            }
        } else {
            break
        }
    }

    if hasDot || numStr.contains(".") {
        if let val = Double(numStr) {
            return LocatedToken(token: .number(.float(val)), location: start)
        }
    } else {
        if let val = Int(numStr) {
            return LocatedToken(token: .number(.integer(val)), location: start)
        }
        if let val = BigInt(numStr) {
            return LocatedToken(token: .number(.bigInt(val)), location: start)
        }
    }
    throw ReadError.invalidNumber(start, numStr)
}

func readSymbol(_ reader: Reader, first: String = "") -> String {
    var value = first
    while let c = reader.peekChar() {
        if isDelimiter(c) { break }
        value.append(c)
        reader.readChar()
    }
    return value
}

// MARK: - Expression Reading

func readExpr(_ reader: Reader) throws -> SExpr? {
    reader.skipWhitespaceAndComments()
    guard !reader.isEOF else { return nil }

    // Dispatch table check
    if let c = reader.peekChar(), let macroFn = readerDispatchTable[c] {
        reader.readChar()
        let step = apply(macroFn, [.string(String(c))]) { val in .done(val) }
        return try trampoline(step)
    }

    // Regular token reading
    guard let located = try readToken(reader) else { return nil }
    return try parseExpr(located, reader)
}

func parseExpr(_ located: LocatedToken, _ reader: Reader) throws -> SExpr {
    let token = located.token
    let loc = located.location

    switch token {
    case .leftParen:
        return try parseList(reader)

    case .quote:
        guard let expr = try readExpr(reader) else {
            throw ReadError.unexpected("unexpected EOF after quote")
        }
        return .cons(.symbol("quote"), .cons(expr, .null))

    case .quasiquote:
        guard let expr = try readExpr(reader) else {
            throw ReadError.unexpected("unexpected EOF after quasiquote")
        }
        return .cons(.symbol("quasiquote"), .cons(expr, .null))

    case .unquote:
        guard let expr = try readExpr(reader) else {
            throw ReadError.unexpected("unexpected EOF after unquote")
        }
        return .cons(.symbol("unquote"), .cons(expr, .null))

    case .unquoteSplicing:
        guard let expr = try readExpr(reader) else {
            throw ReadError.unexpected("unexpected EOF after unquote-splicing")
        }
        return .cons(.symbol("unquote-splicing"), .cons(expr, .null))

    case .number(let n):
        return .number(n)

    case .symbol(let s):
        return .symbol(s)

    case .string(let s):
        return .string(s)

    case .boolean(let b):
        return .boolean(b)

    case .dot:
        throw ReadError.unexpected("\(loc): '.' outside of list")

    case .rightParen:
        throw ReadError.unexpected("\(loc): unmatched ')'")
    }
}

func parseList(_ reader: Reader) throws -> SExpr {
    var elements: [SExpr] = []

    while true {
        reader.skipWhitespaceAndComments()
        guard !reader.isEOF else {
            throw ReadError.unexpected("unexpected EOF: expected ')'")
        }

        guard let c = reader.peekChar() else {
            throw ReadError.unexpected("unexpected EOF: expected ')'")
        }

        if c == ")" {
            reader.readChar()
            var result: SExpr = .null
            for expr in elements.reversed() {
                result = .cons(expr, result)
            }
            return result
        }

        if c == "." {
            // Read the . as a token to distinguish dot from symbol prefix
            guard let dotToken = try readToken(reader) else {
                throw ReadError.unexpected("unexpected EOF")
            }
            if case .dot = dotToken.token {
                // Dotted pair
                guard let rest = try readExpr(reader) else {
                    throw ReadError.unexpected("unexpected EOF after '.'")
                }
                reader.skipWhitespaceAndComments()
                guard let close = reader.readChar(), close == ")" else {
                    throw ReadError.unexpected("expected ')' after dotted pair")
                }
                var result = rest
                for expr in elements.reversed() {
                    result = .cons(expr, result)
                }
                return result
            }
            // It was a symbol starting with . — parse it normally
            let expr = try parseExpr(dotToken, reader)
            elements.append(expr)
            continue
        }

        // Dispatch table check inside lists
        if let macroFn = readerDispatchTable[c] {
            reader.readChar()
            let step = apply(macroFn, [.string(String(c))]) { val in .done(val) }
            elements.append(try trampoline(step))
            continue
        }

        // Regular token
        guard let located = try readToken(reader) else {
            throw ReadError.unexpected("unexpected EOF: expected ')'")
        }
        let expr = try parseExpr(located, reader)
        elements.append(expr)
    }
}

// MARK: - Top-level Read

/// The global reader for the current input stream.
public var currentReader: Reader?

/// Read one S-expression from the current global reader.
public func readOne() throws -> SExpr? {
    guard currentReader != nil else {
        fatalError("read: no input source")
    }
    return try readExpr(currentReader!)
}

// MARK: - Skipping Whitespace

extension Reader {
    @discardableResult
    public func skipWhitespaceAndComments() -> Bool {
        var skipped = false
        while position < input.endIndex {
            let c = input[position]
            if c == ";" {
                advance()
                while position < input.endIndex, input[position] != "\n" {
                    advance()
                }
                skipped = true
            } else if c.isWhitespace {
                advance()
                skipped = true
            } else {
                break
            }
        }
        return skipped
    }
}
