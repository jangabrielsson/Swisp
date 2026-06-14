import Foundation

public struct LispError: Error, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

public final class Builtin: Equatable {
    public let name: String
    public let fn: ([SExpr]) throws -> SExpr
    public init(_ name: String, _ fn: @escaping ([SExpr]) throws -> SExpr) {
        self.name = name
        self.fn = fn
    }
    public static func == (lhs: Builtin, rhs: Builtin) -> Bool { lhs === rhs }
}

public final class MacroProc: Equatable {
    public let params: [String]
    public let body: SExpr
    public let env: Frame
    private var cache: [(rawArgs: [SExpr], expansion: SExpr)] = []

    public init(params: [String], body: SExpr, env: Frame) {
        self.params = params
        self.body = body
        self.env = env
    }

    public func cachedExpansion(for rawArgs: [SExpr]) -> SExpr? {
        cache.first { $0.rawArgs == rawArgs }?.expansion
    }

    public func storeExpansion(_ rawArgs: [SExpr], _ expansion: SExpr) {
        cache.append((rawArgs, expansion))
    }

    public static func == (lhs: MacroProc, rhs: MacroProc) -> Bool { lhs === rhs }
}

public final class Frame {
    public var bindings: [String: SExpr]
    public let parent: Frame?
    public init(_ bindings: [String: SExpr] = [:], parent: Frame? = nil) {
        self.bindings = bindings
        self.parent = parent
    }
    public func lookup(_ name: String) -> SExpr? {
        bindings[name] ?? parent?.lookup(name)
    }
}

public indirect enum SExpr: Equatable {
    case symbol(String)
    case number(Number)
    case string(String)
    case boolean(Bool)
    case cons(SExpr, SExpr)
    case null
    case builtin(Builtin)
    case closure([String], String?, SExpr, Frame)
    case macro(MacroProc)

    public static func == (lhs: SExpr, rhs: SExpr) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): return true
        case (.symbol(let a), .symbol(let b)): return a == b
        case (.number(let a), .number(let b)): return a == b
        case (.string(let a), .string(let b)): return a == b
        case (.boolean(let a), .boolean(let b)): return a == b
        case (.cons(let a1, let a2), .cons(let b1, let b2)): return a1 == b1 && a2 == b2
        case (.builtin(let a), .builtin(let b)): return a == b
        case (.macro(let a), .macro(let b)): return a == b
        default: return false
        }
    }
}

extension SExpr: CustomStringConvertible {
    public var description: String {
        switch self {
        case .null:
            return "()"
        case .symbol(let s):
            return s
        case .number(let n):
            return n.description
        case .string(let s):
            var out = "\""
            for c in s {
                switch c {
                case "\\": out += "\\\\"
                case "\"": out += "\\\""
                case "\n": out += "\\n"
                case "\t": out += "\\t"
                case "\r": out += "\\r"
                default: out.append(c)
                }
            }
            out += "\""
            return out
        case .boolean(let b):
            return b ? "#t" : "#f"
        case .builtin(let b):
            return "#<builtin: \(b.name)>"
        case .closure(let params, let rest, _, _):
            var parts = params
            if let r = rest { parts.append("."); parts.append(r) }
            return "#<closure (\(parts.joined(separator: " ")))>"
        case .macro(let mp):
            return "#<macro (\(mp.params.joined(separator: " ")))>"
        case .cons(let car, let cdr):
            return printCons(car, cdr)
        }
    }

    private func printCons(_ car: SExpr, _ cdr: SExpr) -> String {
        var parts = [car.description]
        var current = cdr
        while case .cons(let head, let tail) = current {
            parts.append(head.description)
            current = tail
        }
        if case .null = current {
            return "(\(parts.joined(separator: " ")))"
        } else {
            return "(\(parts.joined(separator: " ")) . \(current.description))"
        }
    }
}
