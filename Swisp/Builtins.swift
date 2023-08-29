//
//  Builtins.swift
//  Swisp
//
//  Created by Jan Gabrielsson on 2023-08-30.
//

import Foundation

func lambda(_ args: ArgsList, _ env: Env) throws -> Expr {
    var params: [Atom]
    let a = args[0]
    if try a.isEq(env.lisp.NIL) {
        params = []
    } else if a.isCons() {
        let pe = try (a as! Cons).toArray() { $0 }
        params = pe.map() { $0 as! Atom }
    } else {
        throw LispError.valueError("Bad lambda parameters")
    }
    let body = args
    let nf = { [params] (_ args:ArgsList,_ env:Env) throws -> Expr in
        var i = 0
        env.push()
        for v in params {
            try env.bind(v,args[i].eval(env))
            i = i+1
        }
        var r: Expr?
        for i in 1..<body.count {
            r = try body[i].eval(env)
        }
        env.pop()
        return r ?? env.lisp.NIL
    }
    return Func(fun:nf,name:"LAMBDA")
}

extension LispState {
    func setupBuiltins() {
        define(name:"ADD") { args,_ in
            return try Number(num: args[0].num + args[1].num)
        }
        define(name:"SUB") { args,_ in
            return try Number(num: args[0].num - args[1].num)
        }
        define(name:"MUL") { args,_ in
            return try Number(num: args[0].num * args[1].num)
        }
        define(name:"DIV") { args,_ in
            return try Number(num: args[0].num / args[1].num)
        }
        define(name:"CONS") { args,_ in
            return Cons(car: args[0], cdr: args[1])
        }
        define(name:"CAR") { args,_ in
            return try args[0].car
        }
        define(name:"CDR") { args,_ in
            return try args[0].cdr
        }
        define(name:"EQ") { args,env in
            return try args[0].isEq(args[1]) ? env.lisp.TRUE : env.lisp.NIL
        }
        define(name:"QUOTE",evaluate:false) { args,_ in
            return args[0]
        }
        define(name:"PRINT") { args,_ in
            let args = args[0]
            print("\(args)")
            return args
        }
        define(name:"EVAL") { args,env in
            return try args[0].eval(env)
        }
        define(name:"SETQ", evaluate:false) { args,env in
            let v = args[0] as! Atom
            let r = try args[1].eval(env)
            env.set(v,r)
            return r
        }
        define(name:"LAMBDA",evaluate:false,fun:lambda)
    }
}

