import Foundation

public enum ParserError: Error, CustomStringConvertible {
    case unexpectedToken(SourceLocation, String)
    case unexpectedEOF(String)
    case trailingTokens(SourceLocation, String)

    public var description: String {
        switch self {
        case .unexpectedToken(let loc, let s):
            return "\(loc): unexpected \(s)"
        case .unexpectedEOF(let s):
            return "unexpected EOF: \(s)"
        case .trailingTokens(let loc, let s):
            return "\(loc): unexpected \(s) after expression"
        }
    }
}

public struct Parser {
    private let tokens: [LocatedToken]
    private var index: Int

    public init(tokens: [LocatedToken]) {
        self.tokens = tokens
        self.index = 0
    }

    public mutating func parse() throws -> SExpr {
        let expr = try parseExpr()
        if index < tokens.count {
            let remaining = tokens[index...]
            throw ParserError.trailingTokens(remaining.first!.location, "'\(remaining.first!.token)'")
        }
        return expr
    }

    public mutating func parseAll() throws -> [SExpr] {
        var exprs: [SExpr] = []
        while index < tokens.count {
            exprs.append(try parseExpr())
        }
        return exprs
    }

    private mutating func parseExpr() throws -> SExpr {
        guard index < tokens.count else {
            throw ParserError.unexpectedEOF("unexpected end of input")
        }

        let located = tokens[index]
        let token = located.token
        let loc = located.location

        switch token {
        case .leftParen:
            return try parseList()

        case .quote:
            index += 1
            let expr = try parseExpr()
            return .cons(.symbol("quote"), .cons(expr, .null))

        case .quasiquote:
            index += 1
            let expr = try parseExpr()
            return .cons(.symbol("quasiquote"), .cons(expr, .null))

        case .unquote:
            index += 1
            let expr = try parseExpr()
            return .cons(.symbol("unquote"), .cons(expr, .null))

        case .unquoteSplicing:
            index += 1
            let expr = try parseExpr()
            return .cons(.symbol("unquote-splicing"), .cons(expr, .null))

        case .number(let n):
            index += 1
            return .number(n)

        case .symbol(let s):
            index += 1
            return .symbol(s)

        case .string(let s):
            index += 1
            return .string(s)

        case .boolean(let b):
            index += 1
            return .boolean(b)

        case .dot:
            throw ParserError.unexpectedToken(loc, "'.' outside of list")

        case .rightParen:
            throw ParserError.unexpectedToken(loc, "unmatched ')'")
        }
    }

    private mutating func parseList() throws -> SExpr {
        index += 1 // consume '('
        var elements: [SExpr] = []

        while index < tokens.count {
            let located = tokens[index]

            if case .rightParen = located.token {
                index += 1 // consume ')'
                var result: SExpr = .null
                for expr in elements.reversed() {
                    result = .cons(expr, result)
                }
                return result
            }

            if case .dot = located.token {
                index += 1 // consume '.'
                let rest = try parseExpr()
                guard index < tokens.count, case .rightParen = tokens[index].token else {
                    throw ParserError.unexpectedToken(located.location, "expected ')' after dotted pair")
                }
                index += 1 // consume ')'
                var result = rest
                for expr in elements.reversed() {
                    result = .cons(expr, result)
                }
                return result
            }

            let expr = try parseExpr()
            elements.append(expr)
        }

        throw ParserError.unexpectedEOF("expected ')'")
    }
}
