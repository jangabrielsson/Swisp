import BigInt
import Foundation

public enum TokenizerError: Error, CustomStringConvertible {
    case unterminatedString(SourceLocation)
    case invalidNumber(SourceLocation, String)
    case invalidHash(SourceLocation, Character)

    public var description: String {
        switch self {
        case .unterminatedString(let loc):
            return "\(loc): unterminated string"
        case .invalidNumber(let loc, let s):
            return "\(loc): invalid number '\(s)'"
        case .invalidHash(let loc, let c):
            return "\(loc): invalid '#\(c)'"
        }
    }
}

public struct Tokenizer {
    private let input: String
    private var index: String.Index
    private var line: Int
    private var column: Int

    public init(input: String) {
        self.input = input
        self.index = input.startIndex
        self.line = 1
        self.column = 1
    }

    public mutating func tokenize() throws -> [LocatedToken] {
        var tokens: [LocatedToken] = []
        while index < input.endIndex {
            skipWhitespaceAndComments()
            guard index < input.endIndex else { break }

            let start = currentLocation()
            let c = input[index]

            switch c {
            case "(":
                tokens.append(LocatedToken(token: .leftParen, location: start))
                advance()
            case ")":
                tokens.append(LocatedToken(token: .rightParen, location: start))
                advance()
            case "'":
                tokens.append(LocatedToken(token: .quote, location: start))
                advance()
            case "`":
                tokens.append(LocatedToken(token: .quasiquote, location: start))
                advance()
            case ",":
                if let next = peekNext(), next == "@" {
                    tokens.append(LocatedToken(token: .unquoteSplicing, location: start))
                    advance()
                    advance()
                } else {
                    tokens.append(LocatedToken(token: .unquote, location: start))
                    advance()
                }
            case "\"":
                tokens.append(try readString(start: start))
            case "#":
                tokens.append(try readHash(start: start))
            case ".":
                tokens.append(try readDotOrSymbol(start: start))
            case _ where c.isNumber:
                tokens.append(try readNumber(from: start))
            case "-", "+":
                if c == "-", let next = peekNext(), next.isNumber || next == "." {
                    tokens.append(try readNumber(from: start))
                } else {
                    let sym = readSymbol()
                    tokens.append(LocatedToken(token: .symbol(sym), location: start))
                }
            default:
                let sym = readSymbol()
                tokens.append(LocatedToken(token: .symbol(sym), location: start))
            }
        }
        return tokens
    }

    // MARK: - Readers

    private mutating func readString(start: SourceLocation) throws -> LocatedToken {
        advance() // consume opening "
        var value = ""
        while index < input.endIndex {
            let c = input[index]
            if c == "\"" {
                advance() // consume closing "
                return LocatedToken(token: .string(value), location: start)
            } else if c == "\\" {
                advance()
                guard index < input.endIndex else {
                    throw TokenizerError.unterminatedString(start)
                }
                let escaped = input[index]
                switch escaped {
                case "\"": value.append("\"")
                case "\\": value.append("\\")
                case "n": value.append("\n")
                case "t": value.append("\t")
                case "r": value.append("\r")
                default: value.append(escaped)
                }
                advance()
            } else {
                value.append(c)
                advance()
            }
        }
        throw TokenizerError.unterminatedString(start)
    }

    private mutating func readHash(start: SourceLocation) throws -> LocatedToken {
        advance() // consume #
        guard index < input.endIndex else {
            throw TokenizerError.invalidHash(start, " ")
        }
        let c = input[index]
        advance()
        switch c {
        case "t": return LocatedToken(token: .boolean(true), location: start)
        case "f": return LocatedToken(token: .boolean(false), location: start)
        default: throw TokenizerError.invalidHash(start, c)
        }
    }

    private mutating func readDotOrSymbol(start: SourceLocation) throws -> LocatedToken {
        if let next = peekNext(), !isDelimiter(next) {
            let sym = readSymbol()
            return LocatedToken(token: .symbol(sym), location: start)
        }
        advance()
        return LocatedToken(token: .dot, location: start)
    }

    private mutating func readNumber(from start: SourceLocation) throws -> LocatedToken {
        var numStr = ""

        if index < input.endIndex, input[index] == "-" || input[index] == "+" {
            numStr.append(input[index])
            advance()
        }

        var hasDot = false
        while index < input.endIndex {
            let c = input[index]
            if c.isNumber {
                numStr.append(c)
                advance()
            } else if c == "." && !hasDot {
                if let next = peekNext(), next.isNumber {
                    hasDot = true
                    numStr.append(c)
                    advance()
                } else {
                    numStr.append(c)
                    advance()
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
        throw TokenizerError.invalidNumber(start, numStr)
    }

    private mutating func readSymbol() -> String {
        var value = ""
        while index < input.endIndex {
            let c = input[index]
            if isDelimiter(c) { break }
            value.append(c)
            advance()
        }
        return value
    }

    // MARK: - Helpers

    private func currentLocation() -> SourceLocation {
        SourceLocation(line: line, column: column)
    }

    private mutating func advance() {
        if index < input.endIndex {
            if input[index] == "\n" {
                line += 1
                column = 1
            } else if input[index] == "\t" {
                column += 4
            } else {
                column += 1
            }
            index = input.index(after: index)
        }
    }

    private func peekNext() -> Character? {
        let next = input.index(after: index)
        guard next < input.endIndex else { return nil }
        return input[next]
    }

    private mutating func skipWhitespaceAndComments() {
        while index < input.endIndex {
            let c = input[index]
            if c == ";" {
                while index < input.endIndex, input[index] != "\n" {
                    advance()
                }
            } else if c.isWhitespace {
                advance()
            } else {
                break
            }
        }
    }

    private func isDelimiter(_ c: Character) -> Bool {
        c.isWhitespace
            || c == "(" || c == ")"
            || c == "\"" || c == "'"
            || c == "`" || c == ","
            || c == ";"
    }
}
