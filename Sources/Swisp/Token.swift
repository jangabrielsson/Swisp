import BigInt
import Foundation

public enum Number: Equatable, CustomStringConvertible {
    case integer(Int)
    case bigInt(BigInt)
    case float(Double)

    public var description: String {
        switch self {
        case .integer(let v): return String(v)
        case .bigInt(let v): return String(v)
        case .float(let v): return String(v)
        }
    }
}

public enum Token: Equatable, CustomStringConvertible {
    case leftParen
    case rightParen
    case number(Number)
    case symbol(String)
    case string(String)
    case boolean(Bool)
    case quote
    case quasiquote
    case unquote
    case unquoteSplicing
    case dot

    public var description: String {
        switch self {
        case .leftParen: return "("
        case .rightParen: return ")"
        case .number(let n): return n.description
        case .symbol(let s): return s
        case .string(let s): return "\"\(s)\""
        case .boolean(let b): return b ? "#t" : "#f"
        case .quote: return "'"
        case .quasiquote: return "`"
        case .unquote: return ","
        case .unquoteSplicing: return ",@"
        case .dot: return "."
        }
    }
}

public struct LocatedToken: CustomStringConvertible {
    public let token: Token
    public let location: SourceLocation

    public init(token: Token, location: SourceLocation) {
        self.token = token
        self.location = location
    }

    public var description: String {
        "\(location)\t\(token)"
    }
}
