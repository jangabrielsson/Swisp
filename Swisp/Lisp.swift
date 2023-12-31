//
//  Lisp.swift
//  Swisp
//
//  Created by Jan Gabrielsson on 2023-08-29.
//

import Foundation
import BigNum
// import BigNumber, with type BInt, much slower....

let UPPERCASED = true       // All atoms are uppercased when read in - default. Alternative, everything case-sensitive...
typealias NumType = BigNum    // Number type. Supports Double or BInt (support any type with the arithmentic operators and taking a string as initializer)

enum LispError: Error {
    case unbound(String)
    case unboundFun(String)
    case value(String)
    case param(String)
    case syntax(String)
    case token(String)
    case parse(String)
    case user(String,Atom,Expr)
}

class LispFiles {
    var  fileMap = [String:String]()
    static let shared = LispFiles()
    func register(_ path: String, _ content: String) {
        fileMap.updateValue(content, forKey: path)
    }
    func read(_ path: String) -> String? {
        return fileMap[path]
    }
    private init() {
        register("/init.lsp",__init_lsp)
        register("/backquote.lsp",__backquote_lsp)
    }
}

class LispLogger {
    enum Flag :  String {
        case debug = "Debug"
        case trace = "Trace"
        case warning = "Warning"
        case error = "Error"
        case macroexpand = "Macroexpand"
        case call = "Call"
        case callreturn = "Return"
        case tailcall = "Tail-call"
        case readmacro = "Readmacro"
    }
    var flags = [Flag:Bool]()
    func setFlag(_ flag: Flag, _ value: Bool) {
        flags[flag] = value
    }
    func log(_ flag: Flag, _ str:String) {
        if flags[flag, default: false] { print("[\(flag.rawValue)]: \(str)") }
    }
}

class SharedDictionary<K: Hashable, V> { // Our environments/closures needs to share stuff... only used for macroexpanded expressions for now
    var dict : Dictionary<K, V>
    subscript(key : K) -> V? {
        get {
            return dict[key]
        }
        set(newValue) {
            dict[key] = newValue
        }
    }
    init() { dict = [:] }
}

class Bindings<K:Hashable,V> {
    var prev: Bindings?
    var vars = [K:V]()
    func lookup(_ key: K) -> V? {
        return vars[key] ?? prev?.lookup(key)
    }
    func bind(_ key: K, _ value: V) {
        vars.updateValue(value,forKey:key)
    }
    func set(_ key: K, _ value: V) -> Bool {
        if vars[key] == nil {
            return prev?.set(key,value) ?? false
        } else {
            vars.updateValue(value,forKey:key)
            return true
        }
    }
    init(_ prev: Bindings?) {
        self.prev = prev
    }
}

class Env {
    var lisp: LispRuntime
    var NIL: Atom
    var TRUE: Atom
    var bindings: Bindings<Atom,Expr>?
    var funbindings: Bindings<Atom,Func>?
    private(set) var frameDepth = 0
    var currInput: InputStream?
    var tailCall: Func? // Forward through eval chain
    var lastFunc: Func?
    var lastCall: Expr?
    var closure = true
    var jitted = SharedDictionary<Cons,Expr>()
    
    func push() { frameDepth += 1; bindings = Bindings(bindings); funbindings = Bindings(funbindings) }
    func pop() { frameDepth += 1; bindings = bindings?.prev; funbindings = funbindings?.prev }
    func bind(_ atom: Atom, _ expr: Expr) { bindings?.bind(atom,expr) }
    func lookup(_ atom: Atom) -> Expr? {
        return bindings?.lookup(atom)
    }
    func set(_ atom: Atom, _ expr: Expr) {
        if bindings?.set(atom,expr) == true { return }
        atom.set(expr)
    }
    func lookupfun(_ atom: Atom) -> Func? {
        return funbindings?.lookup(atom)
    }
    func bindfun(_ atom: Atom, _ fun: Func) {
        funbindings?.bind(atom,fun)
    }
    func dumpfuns() {
        var b = funbindings
        while let b1=b {
            for (k,v) in b1.vars {
                print("FB \(k)=\(v)")
            }
            b = b1.prev
        }
    }
    func copy() -> Env {
        let env = Env(lisp)
        env.bindings = bindings
        env.funbindings = funbindings
        env.frameDepth = frameDepth
        env.jitted = jitted
        env.lastCall = lastCall
        env.tailCall = tailCall
        env.currInput = currInput
        return env
    }
    init(_ lisp: LispRuntime) {
        self.lisp = lisp
        self.NIL = lisp.NIL
        self.TRUE = lisp.TRUE
    }
}

/**
    Creates a Lisp runtime for evaluating lisp expressions.
 
  - Author:
    JG
  - Version:
    0.5
 */
class LispRuntime {
    let uppercase = UPPERCASED
    var symbols : [String : Atom] = [:]
    var NIL = Atom(name:"nil",type:.null)
    var TRUE = Atom(name:"t")
    var QUOTE = Atom(name:"quote")
    var OPTIONAL = Atom(name:"&optional")
    var REST = Atom(name:"&rest")
    var LAMBDA = Atom(name:"lambda")
    var FUNCTION = Atom(name:"function")
    var logger = LispLogger()
    lazy var log: (LispLogger.Flag,String) -> () = { logger.log }()
    let stdin = ConsoleInputStream()
    lazy var parser: Parser = {
        return Parser(self)
    }()
    var readMacros = [String:Func]()
    
    func symName(_ str: String) -> String { uppercase ? str.uppercased() : str }
    
    func intern(name: String) -> Atom {
        let str = symName(name)
        if let atom = symbols[str] {
            return atom
        }
        let atom = Atom(name: str, value: nil)
        symbols[str] = atom
        return atom
    }
    
    func define(name:String,
                args:(ParamType,Int,Int),
                special: Bool = false,
                params: String? = nil,
                descr: String,
                fun:@escaping BuiltinFunc) {
        let funw = Func(name:name,args:args,special:special,fun:fun)
        funw.params = params == nil ? "()" : params!.uppercased()
        let atom = intern(name:name)
        atom.setf(funw)
    }
    
    func define(name:String) -> Atom {
        intern(name:name)
    }
    
    init(loadLib:Bool = true) {
        NIL.set(NIL)
        TRUE.set(TRUE)
        symbols[NIL.name] = NIL
        symbols[TRUE.name] = TRUE
        symbols[QUOTE.name] = QUOTE
        symbols[OPTIONAL.name]=OPTIONAL
        symbols[REST.name] = REST
        symbols[LAMBDA.name] = LAMBDA
        symbols[FUNCTION.name] = FUNCTION
        define(name:"true").set(TRUE)
        setupBuiltins()
        if loadLib {
            if case (false,let msg) = load("/init.lsp") {
                print("\(msg)")
            }
        }
    }
    
    func readExpr(_ stream: InputStream) throws -> Expr? {
        return try parser.readExpr(stream)
    }
    
    func load(_ path: String, log: Bool = false) -> (Bool,String) {
        let content = LispFiles.shared.fileMap[path]!
        return load(StringInputStream(content),log:log)
    }
        
    func load(_ stream: InputStream, log: Bool = false) -> (Bool,String) {
        do {
            while true {
                if let expr = try readExpr(stream) {
                    if expr.isNIL() { break }
                    let res = try eval(expr)
                    if true {
                        print("\(res)")
                    }
                } else { break }
            }
        } catch {
            if true { print("\(error)") }
            return (false,"\(error)")
        }
        return (true,"ok")
    }
    
    func read(_ stream: InputStream) throws -> Expr {
        return try parser.readExpr(stream)
    }
    
    func eval(_ expr: Expr) throws -> Expr {
        return try expr.eval(Env(self),nil)
    }
    
    func eval(_ str: String) throws -> Expr {
        let stream = StringInputStream(str)
        return try eval(parser.readExpr(stream))
    }
    
    func eq(_ expr1: Expr, _ expr2: Expr) throws -> Bool {
        return expr1.isEq(expr2)
    }
    
    func equal(_ expr1: Expr, _ expr2: Expr) throws -> Bool {
        if try eq(expr1,expr2) { return true }
        if !(expr1 is Cons && expr2 is Cons) { return false }
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

