//
//  DataTypes.swift
//  Swisp
//
//  Created by Jan Gabrielsson on 2023-08-31.
//

import Foundation

enum DataType {
    case number
    case atom
    case cons
    case str
    case fun
    case stream
}

protocol Expr: CustomStringConvertible {
    var type: DataType { get }
    var car: Expr { get throws }
    var cdr: Expr { get throws }
    var str: String { get throws }
    var num: Double { get throws }
    var binding: Expr { get throws }
    var funVal: Func { get throws }
    func call(_ exprList: Expr, _ caller: Cons, _ env: Env) throws -> Expr
    func eval(_ env: Env) throws -> Expr
    func set(_ value: Expr) throws
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
            throw LispError.value("\(self) not an atom")
        }
    }
    var funVal: Func {
        get throws {
            throw LispError.value("\(self) not a function")
        }
    }
    func call(_ exprList: Expr, _ caller: Cons, _ env: Env) throws -> Expr {
        throw LispError.value("\(env.lastCall ?? self) not a function")
    }
    
    func set(_ value: Expr) throws { throw LispError.value("\(self) not an atom") }
    
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
    let type: DataType = .number
    let val: Double
    var num: Double { val }
    static var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        return formatter
    }
    public var description: String {
        let number = NSNumber(value: val)
        let formattedValue = Number.formatter.string(from: number)!
        return "\(formattedValue)"
    }
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
    let type: DataType = .atom
    var name: String
    var val: Expr?
    var funVal: Func?
    var binding: Expr { val! }
    func set(_ value: Expr) {
        val = value
    }
    func setf(_ f: Func) {
        funVal = f
    }
    func isNIL() -> Bool { return self.name == (UPPERCASED ? "NIL" : "nil") } // Urrrk
    func eval(_ env: Env) throws -> Expr {
        if let val = env.lookup(self) {
            return val
        }
        guard val != nil else { throw LispError.unbound("Atom \(self)") }
        return val!
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
    static func ==(lhs: Atom, rhs: Atom) -> Bool {
        return lhs.name == rhs.name
    }
    public var description: String { name }
    init(name: String, value: Expr? = nil) {
        self.name = UPPERCASED ? name.uppercased() : name
        self.val = value
    }
}

class Str : Expr {
    let type: DataType = .str
    var value: String
    var str: String { value }
    public var description: String { "\"\(value)\"" }
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

class Cons : Expr, Hashable, Equatable {
    let type: DataType = .cons
    var carValue: Expr
    var cdrValue: Expr
    var car: Expr { return carValue }
    var cdr: Expr { return cdrValue }
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
    static func ==(lhs: Cons, rhs: Cons) -> Bool {
        return lhs === rhs
    }
    func hash(into hasher: inout Hasher) { return hasher.combine(ObjectIdentifier(self)) }
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
    let type: DataType = .fun
    var name: String
    var special: Bool
    var ftype: FuncType = .builtin
    var nargs: (ParamType,Int,Int)
    func isFunc() -> Bool { return true }
    let fun: ((ArgsList,Env) throws -> Expr)
    func call(_ exprList: Expr, _ caller: Cons, _ env: Env) throws -> Expr {
        var args = [Expr]()
        if let list = exprList as? Cons {
            args = try list.toArray() { try special ? $0 : $0.eval(env) }
        }
        switch nargs { // Check correct number of arguments
        case (.param,let min, _): if args.count != min { throw LispError.param("\(name) expecting \(min) args") }
        case (.optional,let min, let max): if args.count < min && args.count > max { throw LispError.param("\(name) expecting \(min)-\(max) args") }
        case (.rest,let min, _): if args.count < min { throw LispError.param("\(name) expecting at least \(min) args") }
        }
        var res = try fun(args,env)
        if ftype == .macro {            // macros evaluates their results (macroexpand)
            if env.lisp.trace { print("MACROEXPAND:\(res)") }
            res = try res.eval(env)
            env.jitted[caller] = res    // "memoization for our macroexpanded code...
        }
        return res
    }
    public var description: String { "<\(ftype.rawValue):\(name)>" }
    init(name: String, args:(ParamType,Int,Int), special: Bool = false, fun: @escaping (ArgsList,Env) throws -> Expr) {
        self.fun = fun
        self.name = name
        self.special = special
        self.nargs = args
    }
}

extension Cons: Sequence {
    func makeIterator() -> ConsIterator {
        return ConsIterator(self)
    }
}

extension Cons {
    func toArray(cont: (Expr) throws -> Expr) throws -> [Expr] {
        var res = [Expr]()
        for e in self { try res.append(cont(e)) }
        return res
    }
    
    func eval(_ env: Env) throws -> Expr {
        env.lastCall = carValue
        if env.lisp.trace { print("CALL:\(carValue)\(cdrValue)") }
        if let code = env.jitted[self] {
            let res = try code.eval(env)
            env.lastCall = nil
            return res
        } else {
            let f = try carValue.eval(env)
            env.lastCall = nil
            let res = try f.call(cdrValue,self,env)
            if env.lisp.trace { print("RETURN:\(carValue)\(cdrValue)=\(res)") }
            return res
        }
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
