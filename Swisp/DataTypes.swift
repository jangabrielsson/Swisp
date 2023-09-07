//
//  DataTypes.swift
//  Swisp
//
//  Created by Jan Gabrielsson on 2023-08-31.
//

import Foundation
import BigNum

enum DataType {
    case number
    case atom
    case null   // Special type of atom. Easier to recognize...
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
    var num: NumType { get throws }
    var binding: Expr { get throws }
    var funVal: Func { get throws }
    func call(_ exprList: Expr, _ caller: Cons, _ env: Env, _ tail: Func?) throws -> Expr
    func eval(_ env: Env, _ tail: Func?) throws -> Expr
    func set(_ value: Expr) throws
    func isNIL() -> Bool
    func isEq(_ expr: Expr) -> Bool
}

extension Expr {
    var str: String {
        get throws {
            throw LispError.value("\(self) not a string")
        }
    }
    var num: NumType {
        get throws {
            throw LispError.value("\(self) not a number")
        }
    }
    var car: Expr {
        get throws {
            throw LispError.value("\(self) not a cons")
        }
    }
    var cdr: Expr {
        get throws {
            throw LispError.value("\(self) not a cons")
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
    func call(_ exprList: Expr, _ caller: Cons, _ env: Env, _ tail: Func?) throws -> Expr {
        throw LispError.value("\(env.lastCall ?? self) not a function")
    }
    
    func set(_ value: Expr) throws { throw LispError.value("\(self) not an atom") }
    
    func isNIL() -> Bool { return false }
    func isFunc() -> Bool { return false }
    func isEq(_ expr: Expr) -> Bool {
        return expr as AnyObject === self as AnyObject
    }
    func eval(_ env: Env, _ tail :Func?) throws -> Expr {
        return self
    }
    //public var description: String { return "<Expr>" }
}

class Number : Expr {
    let type: DataType = .number
    let val: NumType
    var num: NumType { val }
    public var description: String { return "\(val)" }
    func isEq(_ expr: Expr) -> Bool {
        if let e = expr as? Number {
            return e.val == val
        }
        else { return false }
    }
    init(num: NumType) {
        val = num
    }
    init(num: Int) {
        val = NumType(num)
    }
    init(num: Double) {
        val = NumType(Int(num))
    }
    init(num: String) {
        val = NumType(num) ?? NumType(0)
    }
}

class Atom : Expr, Hashable {
    let type: DataType
    var name: String
    var val: Expr?
    private (set) var fun: Func?
    var binding: Expr { val! }
    func set(_ value: Expr) {
        val = value
    }
    func setf(_ f: Func) {
        fun = f
    }
    var funVal: Func {
        get throws {
            guard fun != nil else { throw LispError.unboundFun("Atom \(self)") }
            return fun!
        }
    }
    func isNIL() -> Bool { return self.type == .null }
    func eval(_ env: Env, _ tail: Func?=nil) throws -> Expr {
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
    init(name: String, value: Expr? = nil, type:DataType = .atom) {
        self.name = UPPERCASED ? name.uppercased() : name
        self.type = type
        self.val = value
    }
}

class Str : Expr {
    let type: DataType = .str
    var value: String
    var str: String { value }
    let quoted: Bool
    public var description: String { quoted ? "\"\(value)\"" : value }
    func isEq(_ expr: Expr) -> Bool {
        if let e = expr as? Str {
            return e.value == value
        }
        else { return false }
    }
    init(str: String, quoted:Bool = true) {
        self.value = str
        self.quoted = quoted
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
    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self)) // ToDo Problematic. ObjId is reused when object is GC'ed...
    }
    init(car: Expr, cdr: Expr) {
        carValue = car; cdrValue = cdr
    }
}

typealias ArgsArray = [Expr]
typealias BuiltinFunc = ([Expr],Env,Func?) throws -> Expr

enum FuncType : String {
    case builtin = "builtin"
    case fun = "fun"
    case macro  = "macro"
}

class Func : Expr { // Expr wrapper for a Swift function
    let type: DataType = .fun
    var name: String
    var special: Bool
    var tailArgs: [Expr]?
    var ftype: FuncType = .builtin
    var funVal: Func { return self }
    var nargs: (ParamType,Int,Int)
    func isFunc() -> Bool { return true }
    let fun: BuiltinFunc
    func call(_ exprList: Expr, _ caller: Cons, _ env: Env, _ tail: Func?) throws -> Expr {
        var args = [Expr]()
        if let list = exprList as? Cons {
            args = try list.toArray() { try special ? $0 : $0.eval(env,nil) }
        }
        switch nargs { // Check correct number of arguments, exact, with &optionals, and with &rest
        case (.param,let min, _): if args.count != min { throw LispError.param("\(name) expecting \(min) args") }
        case (.optional,let min, let max): if args.count < min || args.count > max { throw LispError.param("\(name) expecting \(min)-\(max) args") }
        case (.rest,let min, _): if args.count < min { throw LispError.param("\(name) expecting at least \(min) args") }
        }

        env.lastFunc = self
        var res = try fun(args,env,tail)
        if ftype == .macro {            // macros evaluates their results (macroexpand)
            env.jitted[caller] = res    // "memoization for our macroexpanded code...
            env.lisp.log(.macroexpand,"\(res)")
            res = try res.eval(env,nil)
        }
        return res
    }
    public var description: String { "<\(ftype.rawValue):\(name)>" }
    init(name: String, args:(ParamType,Int,Int), special: Bool = false, fun: @escaping BuiltinFunc) {
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
    
    func eval(_ env: Env, _ tail: Func? = nil) throws -> Expr {
        env.lastCall = carValue
        env.lisp.log(.call,"\(carValue)\(cdrValue)")
        if let code = env.jitted[self] {
            //print("Running jitted: \(code) - \(id) - \(self)")
            let res = try code.eval(env,nil)
            env.lastCall = nil
            return res
        } else {
            let f = try carValue.funVal
            env.lastCall = nil
            let res = try f.call(cdrValue,self,env,tail)
            env.lisp.log(.callreturn,"\(carValue)\(cdrValue)=\(res)")
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
