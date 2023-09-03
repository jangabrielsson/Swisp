//
//  DataTypes.swift
//  Swisp
//
//  Created by Jan Gabrielsson on 2023-08-31.
//

import Foundation

protocol Expr: CustomStringConvertible {
    var car: Expr { get throws }
    var cdr: Expr { get throws }
    var str: String { get throws }
    var num: Double { get throws }
    var binding: Expr { get throws }
    func call(_ exprList: Expr, _ caller: Cons, _ env: Env) throws -> Expr
    func eval(_ env: Env) throws -> Expr
    func set(_ value: Expr) throws
    func isAtom() -> Bool
    func isCons() -> Bool
    func isNum() -> Bool
    func isStr() -> Bool
    func isNIL() -> Bool
    func isEq(_ expr: Expr) -> Bool
}

extension Expr {
    var str: String {
        get throws {
            throw LispError.value("Not a string")
        }
    }
    var num: Double {
        get throws {
            throw LispError.value("'\(self)' not a number")
        }
    }
    var car: Expr {
        get throws {
            throw LispError.value("'\(self)' not a cons")
        }
    }
    var cdr: Expr {
        get throws {
            throw LispError.value("'\(self)' not a cons")
        }
    }
    var binding: Expr {
        get throws {
            throw LispError.value("Not an atom \((self))")
        }
    }
    func call(_ exprList: Expr, _ caller: Cons, _ env: Env) throws -> Expr {
        throw LispError.value("\(env.lastCall ?? self) not a function")
    }
    
    func set(_ value: Expr) throws { throw LispError.value("Not an atom") }
    
    func isAtom() -> Bool { return false }
    func isCons() -> Bool { return false }
    func isNum() -> Bool { return false }
    func isStr() -> Bool { return false }
    func isNIL() -> Bool { return false }
    func isFunc() -> Bool { return false }
    func isEq(_ expr: Expr) -> Bool {
        return expr as AnyObject === self as AnyObject
    }
    func eval(_ env: Env) throws -> Expr {
        return self
    }
    public var description: String { return "<obj>" }
}

class Number : Expr {
    let val: Double
    var num: Double { val }
    static var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        //formatter.maximumFractionDigits = 2
        return formatter
    }
    public var description: String {
        let number = NSNumber(value: val)
        let formattedValue = Number.formatter.string(from: number)!
        return "\(formattedValue)"
    }
    func isAtom() -> Bool {return true }
    func isNum() -> Bool { return true }
    func isEq(_ expr: Expr) -> Bool {
        if let e = expr as? Number {
            return e.val == val
        }
        else { return false }
    }
    init(num: Double) {
        val = num
    }
}

class Atom : Expr, Hashable {
    var name: String
    var val: Expr?
    var binding: Expr { val! }
    func set(_ value: Expr) {
        val = value
    }
    func isNIL() -> Bool { return self.name == "NIL" }
    func eval(_ env: Env) throws -> Expr {
        if let val = env.lookup(self) {
            return val
        }
        guard val != nil else { throw LispError.value("Atom \(self) not bound") }
        return val!
    }
    func isAtom() -> Bool {return true }
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
    static func ==(lhs: Atom, rhs: Atom) -> Bool {
        return lhs.name == rhs.name
    }
    public var description: String { name }
    init(name: String, value: Expr? = nil) {
        self.name = name
        self.val = value
    }
}

class Str : Expr {
    var value: String
    var str: String { value }
    public var description: String { "\"\(value)\"" }
    func isStr() -> Bool {return true }
    func isAtom() -> Bool {return true }
    func isEq(_ expr: Expr) -> Bool {
        if let e = expr as? Str {
            return e.value == value
        }
        else { return false }
    }
    init(str: String) {
        self.value = str
    }
}

class Cons : Expr {
    var carValue: Expr
    var cdrValue: Expr
    var car: Expr { return carValue }
    var cdr: Expr { return cdrValue }
    func isCons() -> Bool { return true }
    public var description: String {
        var res = [String]()
        var l = self as Expr
        while let c = l as? Cons {
            res.append("\(c.carValue)")
            l = c.cdrValue
        }
        if !l.isNIL() {
            res.append(".")
            res.append("\(l)")
        }
        return "("+res.joined(separator:" ")+")"
    }
    init(car: Expr, cdr: Expr) {
        carValue = car; cdrValue = cdr
    }
}

typealias ArgsList = [Expr]

enum FuncType : String {
    case builtin = "builtin"
    case fun = "fun"
    case macro  = "macro"
}

class Func : Expr { // Expr wrapper for a Swift function
    var name: String
    var special: Bool
    var type: FuncType = .builtin
    var nargs: (ParamType,Int,Int)
    func isFunc() -> Bool { return true }
    let fun: ((ArgsList,Env) throws -> Expr)
    func call(_ exprList: Expr, _ caller: Cons, _ env: Env) throws -> Expr {
        var args = [Expr]()
        if let list = exprList as? Cons {
            args = try list.toArray() { try special ? $0 : $0.eval(env) }
        }
        switch nargs {
        case (.param,let min, _): if args.count != min { throw LispError.param("\(name) expecting \(min) args") }
        case (.optional,let min, let max): if args.count < min && args.count > max { throw LispError.param("\(name) expecting \(min)-\(max) args") }
        case (.rest,let min, _): if args.count < min { throw LispError.param("\(name) expecting at least \(min) args") }
        }
        var res = try fun(args,env)
        if type == .macro {            // macros evaluates their results (macroexpand)
            if env.lisp.trace { print("MACROEXPAND:\(res)") }
            res = try res.eval(env)
        }
        //if env.lisp.trace { print("Func:\(name)(\(args))=\(res)") }
        return res
    }
    public var description: String { "<\(type.rawValue):\(name)>" }
    init(name: String, args:(ParamType,Int,Int), special: Bool = false, fun: @escaping (ArgsList,Env) throws -> Expr) {
        self.fun = fun
        self.name = name
        self.special = special
        self.nargs = args
    }
}

extension Cons: Sequence {
    func toArray(cont: (Expr) throws -> Expr) throws -> [Expr] {
        var res = [Expr]()
        for e in self { try res.append(cont(e)) }
        return res
    }
    
    func makeIterator() -> ConsIterator {
        return ConsIterator(self)
    }
    
    func eval(_ env: Env) throws -> Expr {
        env.lastCall = carValue
        if env.lisp.trace { print("CALL:\(carValue)\(cdrValue)") }
        let f = try carValue.eval(env)
        env.lastCall = nil
        let res = try f.call(cdrValue,self,env)
        if env.lisp.trace { print("RETURN:\(carValue)\(cdrValue)=\(res)") }
        return res
    }
}

struct ConsIterator: IteratorProtocol {

    private var p: Cons?

    init(_ collection: Cons) {
        self.p = collection
    }

    mutating func next() -> Expr? {
        if let pn = p {
            let v = pn.car
            p = pn.cdr as? Cons
            return v
        }
        return nil
    }
}
