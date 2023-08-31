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
    
    init(loadLibs:Bool = true) {
        NIL.set(NIL)
        TRUE.set(TRUE)
        parser.lisp = self
        symbols["NIL"] = NIL
        symbols["TRUE"] = TRUE
        define(name:"T").set(TRUE)
        define(name:"FN").set(intern(name:"LAMBDA"))
        QUOTE = define(name:"QUOTE")
        setupBuiltins()
        if loadLibs {
            do {
                try _ = load(StringInputStream(init_lsp))
            }  catch {
            }
        }
    }
    
    func readExpr(_ stream: InputStream) throws -> Expr? {
        return try parser.readExpr(stream)
    }
    
    func load(_ stream: InputStream, log: Bool = false) throws -> (Bool,String) {
        do {
            while true {
                if let expr = try readExpr(stream) {
                    if try expr.isEq(NIL) { break }
                    //print("LR<\(expr)")
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

