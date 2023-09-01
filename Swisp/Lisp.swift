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

class Env {
    var lisp: LispState
    var bindings = [[Atom:Expr]]()
    var currInput: InputStream?
    
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
    var OPTIONAL = Atom(name:"&OPTIONAL")
    var REST = Atom(name:"&REST")
    var parser = Parser()
    var trace: Bool = false
    var readMacros = [String:Func]()
    
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
    
    init(loadLib:Bool = true) {
        NIL.set(NIL)
        TRUE.set(TRUE)
        parser.lisp = self
        symbols["NIL"] = NIL
        symbols["TRUE"] = TRUE
        symbols["&OPTIONAL"] = OPTIONAL
        symbols["&REST"] = REST
        define(name:"T").set(TRUE)
        define(name:"FN").set(intern(name:"LAMBDA"))
        QUOTE = define(name:"QUOTE")
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

