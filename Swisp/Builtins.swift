//
//  Builtins.swift
//  Swisp
//
//  Created by Jan Gabrielsson on 2023-08-30.
//

import Foundation

// Builtins gets their arguments evaluated (from Func.call )
enum ParamType {
    case param
    case optional
    case rest
}

func lambda(_ args: ArgsList, _ env: Env) throws -> Expr {
    var params = [Atom]()
    var optionals = [(Atom,Expr)]()
    var state: ParamType = .param
    var rest: Atom?
    let a = args[0]
    if let c = a as? Cons {
        for e in c {
            if e.isEq(env.lisp.OPTIONAL) {
                if state != .param { throw LispError.syntax("Bad lambda parameters") }
                state = .optional
                continue
            } else if e.isEq(env.lisp.REST) {
                if state == .rest { throw LispError.syntax("Bad lambda parameters") }
                state = .rest
                continue
            }
            switch state {
            case .param: params.append(e as! Atom)
            case .optional:
                if let p = e as? Atom {
                    optionals.append((p,env.lisp.NIL))
                } else if let p = e as? Cons {
                    optionals.append((p.carValue as! Atom,try p.cdrValue.car))
                } else {
                    throw LispError.syntax("Bad lambda parameters")
                }
            case .rest: rest = e as? Atom
            }
        }
    } else if !a.isEq(env.lisp.NIL) {
        throw LispError.syntax("Bad lambda parameters")
    }
    let body = args
    let nf = { [params,optionals,rest] (_ args:ArgsList,_ env:Env) throws -> Expr in
        env.push()
        var n = 0
        if args.count < params.count { throw LispError.param("Too few parameters, expected \(params.count)") }
        for i in n..<params.count { env.bind(params[i],args[i]) }
        n = params.count
        for i in 0..<optionals.count {
            let (v,e) = optionals[i]
            env.bind(v,n+i < args.count ? args[n+i] : try e.eval(env))
        }
        n += optionals.count
        if let rest {
            if args.count > n {
                let val = try env.lisp.arrayToList(args[n...])
                env.bind(rest,val)
            } else { env.bind(rest,env.lisp.NIL) }
        }
        var r: Expr?
        for i in 1..<body.count {
            r = try body[i].eval(env)
        }
        env.pop()
        return r ?? env.lisp.NIL
    }
    let fn = Func(name:"LAMBDA",args:(state,params.count,params.count+optionals.count),fun:nf)
    return fn
}

func let_star(_ args: ArgsList, _ env: Env) throws -> Expr {
    env.push()
    for p in args[0] as! Cons {
        let v = try p.car as! Atom
        env.bind(v,env.lisp.NIL)
        try env.bind(v,p.cdr.car.eval(env))
    }
    var res: Expr?
    for p in args[1...] {
        res = try p.eval(env)
    }
    env.pop()
    return res!
}
    
extension LispState {
    func setupBuiltins() {
        define(name:"+",args:(.param,2,2)) { args,_ in
            return try Number(num: args[0].num + args[1].num)
        }
        define(name:"-",args:(.param,2,2)) { args,_ in
            return try Number(num: args[0].num - args[1].num)
        }
        define(name:"*",args:(.param,2,2)) { args,_ in
            return try Number(num: args[0].num * args[1].num)
        }
        define(name:"/",args:(.param,2,2)) { args,_ in
            return try Number(num: args[0].num / args[1].num)
        }
        define(name:">",args:(.param,2,2)) { args,env in
            return try args[0].num > args[1].num ? env.lisp.TRUE : env.lisp.NIL
        }
        define(name:"<",args:(.param,2,2)) { args,env in
            return try args[0].num < args[1].num ? env.lisp.TRUE : env.lisp.NIL
        }
        define(name:"CONS",args:(.param,2,2)) { args,_ in
            return Cons(car: args[0], cdr: args[1])
        }
        define(name:"CAR",args:(.param,1,1)) { args,_ in
            return try args[0].car
        }
        define(name:"CDR",args:(.param,1,1)) { args,_ in
            return try args[0].cdr
        }
        define(name:"EQ",args:(.param,2,2)) { args,env in
            return args[0].isEq(args[1]) ? env.lisp.TRUE : env.lisp.NIL
        }
        define(name:"CONSP",args:(.param,1,1)) { args,env in
            return args[0].isCons() ? env.lisp.TRUE : env.lisp.NIL
        }
        define(name:"NUMBERP",args:(.param,1,1)) { args,env in
            return args[0].isNum() ? env.lisp.TRUE : env.lisp.NIL
        }
        define(name:"ATOM",args:(.param,1,1)) { args,env in
            return args[0].isAtom() ? env.lisp.TRUE : env.lisp.NIL
        }
        define(name:"QUOTE",args:(.param,1,1),special:true) { args,_ in
            return args[0]
        }
        define(name:"RPLACA",args:(.param,2,2)) { args,_ in
            (args[0] as! Cons).carValue = args[1]
            return args[1]
        }
        define(name:"RPLACD",args:(.param,2,2)) { args,_ in
            (args[0] as! Cons).cdrValue = args[1]
            return args[1]
        }
        define(name:"PROGN",args:(.rest,0,0)) { args,_ in
            return args.last!
        }
        define(name:"PRINT",args:(.rest,0,100)) { args,env in
            for e in args {
                print("\(e) ",terminator: "")
            }
            print()
            return args.last ?? env.lisp.NIL
        }
        define(name:"EVAL",args:(.param,1,1)) { args,env in
            return try args[0].eval(env)
        }
        define(name:"SETQ",args:(.rest,2,2),special:true) { args,env in
            var r: Expr = env.lisp.NIL
            for i in stride(from: 0, to: args.count, by: 2) {
                let v = args[i] as! Atom
                r = try args[i+1].eval(env)
                env.set(v,r)
            }
            return r
        }
        define(name:"LIST",args:(.rest,0,0)) { args,env in
            return try env.lisp.arrayToList(args)
        }
        define(name:"IF",args:(.optional,2,3),special:true) { args,env in
            if args.count > 2 {
                return try !args[0].eval(env).isEq(env.lisp.NIL) ? args[1].eval(env) : args[2].eval(env)
            } else {
                return try !args[0].eval(env).isEq(env.lisp.NIL) ? args[1].eval(env) : env.lisp.NIL
            }
        }
        define(name:"OR",args:(.param,2,2),special:true) { args,env in
            let e = try args[0].eval(env)
            if !e.isEq(env.lisp.NIL) { return e }
            return try args[1].eval(env)
        }
        define(name:"STRFORMAT",args:(.optional,1,100)) { args,env in
            //let fmt = try args[0].str
            return Str(str:"Not implemented yet")
        }
        define(name:"READ",args:(.param,0,0)) { args,env in
            if let stream = env.currInput {
                return try env.lisp.readExpr(stream)!
            }
            print("No input stream set")
            return env.lisp.NIL
        }
        define(name:"PEEKCHAR",args:(.param,0,0)) { args,env in
            if let stream = env.currInput {
                if let c = stream.peek() {
                    var bb = ""
                    bb.unicodeScalars.append(contentsOf: [c])
                    return Str(str:bb)
                }
                return env.lisp.NIL
            }
            print("No input stream set")
            return env.lisp.NIL
        }
        define(name:"SKIPCHAR",args:(.param,0,0)) { args,env in
            if let stream = env.currInput {
                _ = stream.next()
            } else {
                print("No input stream set")
            }
            return env.lisp.NIL
        }
        define(name:"READFILE",args:(.param,1,1)) { args,env in
            let path = try args[0].str
            if case (false,let msg) = env.lisp.load(path) {
                return Str(str:msg)
            }
            return env.lisp.TRUE
        }
        define(name:"READMACRO",args:(.param,2,2)) { args,env in
            let sym = args[0] as! Str
            let fun = args[1] as! Func
            env.lisp.readMacros.updateValue(fun, forKey: sym.value)
            return sym
        }
        define(name:"DEFUN",args:(.rest,2,100),special:true) { args,env in
            let name = args[0] as! Atom
            let params = args[1]
            let body = try env.lisp.arrayToList(args[2...])
            let lambda = Cons(car: env.lisp.intern(name:"LAMBDA"),
                              cdr: Cons(car: params,cdr: body))
            let fun = try lambda.eval(env) as! Func
            fun.name = name.name
            fun.type = .fun
            name.set(fun)
            return name
        }
        define(name:"DEFMACRO",args:(.rest,2,100),special:true) { args,env in
            let name = args[0]
            let newArgs = args[1...].map { $0 }
            let fun = try lambda(newArgs,env) as! Func
            fun.type = .macro
            fun.special = true
            fun.name = "\(name)"
            try name.set(fun)
            return name
        }
        define(name:"WHILE",args:(.rest,1,100),special:true) { args,env in
            let NIL = env.lisp.NIL
            let test = args[0]
            while try !test.eval(env).isEq(NIL) {
                for e in args[1...] {
                    try _ = e.eval(env)
                }
            }
            return NIL
        }
        define(name:"COND",args:(.rest,1,100),special:true) { args,env in
            let NIL = env.lisp.NIL
            for e in args {
                if let c = e as? Cons {
                    if try !c.carValue.eval(env).isEq(NIL) {
                        let b = c.cdrValue as! Cons
                        var r: Expr?
                        for v in b {
                            r = try v.eval(env)
                        }
                        return r ?? NIL
                    }
                } else { throw LispError.syntax("Bad COND syntax") }
            }
            return NIL
        }
        define(name:"GENSYM",args:(.param,0,0)) { args,env in
            return env.lisp.intern(name:"<GENSYM\(Int.random(in: 1..<10000000))>")
        }
        define(name:"CLOCK",args:(.param,0,0)) { args,env in
            return Number(num:0)
        }
        define(name:"LAMBDA",args:(.rest,1,100),special:true,fun:lambda)
        define(name:"FN",args:(.rest,1,100),special:true,fun:lambda)
        define(name:"LET*",args:(.rest,1,100),special:true,fun:let_star)
        define(name:"LET",args:(.rest,1,100),special:true,fun:let_star)
    }
}

