//
//  Lisp.swift
//  Swisp
//
//  Created by Jan Gabrielsson on 2023-08-29.
//

import Foundation

enum LispError: Error {
    case valueError(String)
    case tokenError(String)
    case parseError(String)
}

protocol Expr: CustomStringConvertible {
    var car: Expr { get throws }
    var cdr: Expr { get throws }
    var str: String { get throws }
    var num: Double { get throws }
    var binding: Expr { get throws }
    func call(_ expr: Expr, _ env: Env) throws -> Expr
    func eval(_ env: Env) throws -> Expr
    func set(_ value: Expr) throws
    func isAtom() -> Bool
    func isCons() -> Bool
    func isNum() -> Bool
    func isStr() -> Bool
    func isNIL() -> Bool
    func isEq(_ expr: Expr) throws -> Bool
}

extension Expr {
    var str: String {
        get throws {
            throw LispError.valueError("Not a string")
        }
    }
    var num: Double {
        get throws {
            throw LispError.valueError("'\(self)' not a number")
        }
    }
    var car: Expr {
        get throws {
            throw LispError.valueError("'\(self)' not a cons")
        }
    }
    var cdr: Expr {
        get throws {
            throw LispError.valueError("'\(self)' not a cons")
        }
    }
    var binding: Expr {
        get throws {
            throw LispError.valueError("Not an atom \((self))")
        }
    }
    func call(_ expr: Expr, _ env: Env) throws -> Expr {
        throw LispError.valueError("\(self) not a function")
    }
    
    func set(_ value: Expr) throws { throw LispError.valueError("Not an atom") }
    
    func isAtom() -> Bool { return false }
    func isCons() -> Bool { return false }
    func isNum() -> Bool { return false }
    func isStr() -> Bool { return false }
    func isNIL() -> Bool { return false }
    func isFunc() -> Bool { return false }
    func isEq(_ expr: Expr) throws -> Bool {
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
        formatter.maximumFractionDigits = 2
        return formatter
    }
    public var description: String {
        let number = NSNumber(value: val)
        let formattedValue = Number.formatter.string(from: number)!
        return "\(formattedValue)"
    }
    func isNum() -> Bool { return true }
    func isEq(_ expr: Expr) throws -> Bool {
        return try expr.isNum() && val == expr.num
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
    func isNIL() -> Bool { return self === Lisp.NIL }
    func eval(_ env: Env) throws -> Expr {
        if let val = env.lookup(self) {
            return val
        }
        guard val != nil else { throw LispError.valueError("Atom \(self) not bound") }
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
    func isEq(_ expr: Expr) throws -> Bool {
        return try expr.isStr() && value == expr.str
    }
    init(str: String) {
        self.value = str
    }
}

class Cons : Expr {
    let carValue: Expr
    var cdrValue: Expr
    var car: Expr { return carValue }
    var cdr: Expr { return cdrValue }
    func isCons() -> Bool { return true }
    public var description: String {
        var res = [String]()
        var l = self as Expr
        while l.isCons() {
            res.append(try! "\(l.car)")
            l = try! l.cdr
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

class Func : Expr { // Expr wrapper for a Swift function
    let fun: ((ArgsList,Env) throws -> Expr)
    let name: String
    var ev: Bool
    var isMacro: Bool = false
    func isFunc() -> Bool { return true }
    func call(_ exprList: Expr, _ env: Env) throws -> Expr {
        var args = [Expr]()
        if exprList.isCons() {
            args = try (exprList as! Cons).toArray() { try ev ? $0.eval(env) : $0 }
        }
        let res = try fun(args,env)
        if env.lisp.trace { print("Func:\(name)(\(args))=\(res)") }
        return res
    }
    public var description: String { "<builtin:\(name)>" }
    init(fun: @escaping (ArgsList,Env) throws -> Expr, name: String, evaluate: Bool = true) {
        self.fun = fun
        self.name = name
        self.ev = evaluate
    }
}

extension Cons {
    func toArray(cont: (Expr) throws -> Expr) throws -> [Expr] {
        var res = [Expr]()
        var p = self as Expr
        while p.isCons() {
            let c = p as! Cons
            try res.append(cont(c.carValue))
            p = c.cdrValue
        }
        return res
    }
    
    func eval(_ env: Env) throws -> Expr {
        let f = try carValue.eval(env)
        return try f.call(cdrValue,env)
    }
}

class Env {
    var lisp: LispState
    var bindings = [[Atom:Expr]]()
    
    func push() {
        bindings.append([:])
    }
    func pop() {
        _ = bindings.popLast()
    }
    func bind(_ atom: Atom, _ expr: Expr) {
        //print("Binding \(atom)=\(expr)")
        bindings[bindings.count-1].updateValue(expr,forKey:atom)
    }
    func lookup(_ atom: Atom) -> Expr? {
        for be in bindings.reversed() {
            if let e = be[atom] { return e }
        }
        return nil
    }
    func set(_ atom: Atom, _ expr: Expr) {
        for var be in bindings.reversed() {
            if be[atom] != nil {
                be.updateValue(expr,forKey:atom)
                return
            }
        }
        atom.set(expr)
    }
    init(_ lisp: LispState) {
        self.lisp = lisp
    }
}

class LispState {
    var symbols : [String : Atom] = [:]
    var NIL = Atom(name:"NIL")
    var TRUE = Atom(name:"TRUE")
    var QUOTE: Atom?
    var parser = Parser()
    var trace: Bool = false
    
    func intern(name: String) -> Atom {
        if let atom = symbols[name] {
            return atom
        }
        let atom = Atom(name: name, value: NIL)
        symbols[name] = atom
        return atom
    }
    
    func define(name:String, evaluate: Bool = true, fun:@escaping (ArgsList,Env) throws -> Expr) {
        intern(name:name).set(Func(fun:fun,name:name,evaluate:evaluate))
    }
    func define(name:String) -> Atom {
        intern(name:name)
    }
    
    init() {
        NIL.set(NIL)
        TRUE.set(TRUE)
        parser.lisp = self
        symbols["NIL"] = NIL
        symbols["TRUE"] = TRUE
        symbols["T"] = TRUE
        QUOTE = define(name:"QUOTE")
        setupBuiltins()
    }
    
    func readExpr(_ stream: InputStream) throws -> Expr? {
        return try parser.readExpr(stream)
    }
    
    func load(_ stream: InputStream, log: Bool = false) throws -> (Bool,String) {
        do {
            while true {
                if let expr = try readExpr(stream) {
                    if try expr.isEq(NIL) { break }
                    print("LR<\(expr)")
                    let res = try eval(expr)
                    if log {
                        print("\(res)")
                    }
                } else { break }
            }
        } catch {
            return (false,"\(error)")
        }
        return (true,"ok")
    }
    
    func read(_ stream: InputStream) throws -> Expr {
        return try parser.readExpr(stream)
    }
    
    func eval(_ expr: Expr) throws -> Expr {
        return try expr.eval(Env(self))
    }
    
    func eval(_ str: String) throws -> Expr {
        let stream = StringInputStream(str)
        return try eval(parser.readExpr(stream))
    }
    
    func eq(_ expr1: Expr, _ expr2: Expr) throws -> Bool {
        return try expr1.isEq(expr2)
    }
    
    func equal(_ expr1: Expr, _ expr2: Expr) throws -> Bool {
        if try eq(expr1,expr2) { return true }
        if !(expr1.isCons() && expr2.isCons()) { return false }
        return try equal(expr1.car,expr2.car) && equal(expr1.cdr,expr2.cdr)
    }
    
    func arrayToList(_ exprs: some Sequence<Expr>, offset: Int = 0, cont:((Expr) throws -> Expr) = {$0}) throws -> Expr {
        var p = NIL as Expr
        for e in exprs.reversed() {
            p = try Cons(car:cont(e),cdr:p)
        }
        return p
    }
}

