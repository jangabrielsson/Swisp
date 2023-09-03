//
//  Lisp.swift
//  Swisp
//
//  Created by Jan Gabrielsson on 2023-08-29.
//

import Foundation
let UPPERCASED = true

enum LispError: Error {
    case value(String)
    case param(String)
    case syntax(String)
    case token(String)
    case parse(String)
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
        register("/test.lsp",__test_lsp)
    }
}

class Env {
    var lisp: LispState
    var NIL: Atom
    var TRUE: Atom
    var bindings = [[Atom:Expr]]()
    var currInput: InputStream?
    var lastCall: Expr?
    
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
        for i in stride(from:bindings.count-1,through:0,by:-1) {
            if bindings[i][atom] != nil {
                bindings[i].updateValue(expr,forKey:atom)
                return
            }
        }
        atom.set(expr)
    }
    init(_ lisp: LispState) {
        self.lisp = lisp
        self.NIL = lisp.NIL
        self.TRUE = lisp.TRUE
    }
}

class LispState {
    let uppercase = UPPERCASED
    var symbols : [String : Atom] = [:]
    var NIL = Atom(name:"nil")
    var TRUE = Atom(name:"t")
    var QUOTE = Atom(name:"quote")
    var OPTIONAL = Atom(name:"&optional")
    var REST = Atom(name:"&rest")
    lazy var parser: Parser = {
        return Parser(self)
    }()
    var trace: Bool = false
    var readMacros = [String:Func]()
    
    func symName(_ str: String) -> String { uppercase ? str.uppercased() : str }
    
    func intern(name: String) -> Atom {
        let str = symName(name)
        if let atom = symbols[str] {
            return atom
        }
        let atom = Atom(name: str, value: NIL)
        symbols[str] = atom
        return atom
    }
    
    func define(name:String, args:(ParamType,Int,Int), special: Bool = false, fun:@escaping (ArgsList,Env) throws -> Expr) {
        let funw = Func(name:name,args:args,special:special,fun:fun)
        intern(name:name).set(funw)
    }
        
    func define(name:String) -> Atom {
        intern(name:name)
    }
    
    init(loadLib:Bool = true, trace:Bool = false) {
        NIL.set(NIL)
        TRUE.set(TRUE)
        symbols[NIL.name] = NIL
        symbols[TRUE.name] = TRUE
        symbols[QUOTE.name] = QUOTE
        symbols[OPTIONAL.name]=OPTIONAL
        symbols[REST.name] = REST
        define(name:"true").set(TRUE)
        self.trace = trace
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
                    if expr.isEq(NIL) { break }
                    //print("LR<\(expr)")
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
        return try expr.eval(Env(self))
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

