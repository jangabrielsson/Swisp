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
                    optionals.append((p,env.NIL))
                } else if let p = e as? Cons {
                    optionals.append((p.carValue as! Atom,try p.cdrValue.car))
                } else {
                    throw LispError.syntax("Bad lambda parameters")
                }
            case .rest: rest = e as? Atom
            }
        }
    } else if !a.isEq(env.NIL) {
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
            } else { env.bind(rest,env.NIL) }
        }
        var r: Expr?
        for i in 1..<body.count {
            r = try body[i].eval(env)
        }
        env.pop()
        return r ?? env.NIL
    }
    let fn = Func(name:"lambda",args:(state,params.count,params.count+optionals.count),fun:nf)
    return fn
}

func let_star(_ args: ArgsList, _ env: Env) throws -> Expr {
    env.push()
    for p in args[0] as! Cons {
        let v = try p.car as! Atom
        env.bind(v,env.NIL)
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
            return try args[0].num > args[1].num ? env.TRUE : env.NIL
        }
        define(name:"<",args:(.param,2,2)) { args,env in
            return try args[0].num < args[1].num ? env.TRUE : env.NIL
        }
        define(name:"cons",args:(.param,2,2)) { args,_ in
            return Cons(car: args[0], cdr: args[1])
        }
        define(name:"car",args:(.param,1,1)) { args,_ in
            return try args[0].car
        }
        define(name:"cdr",args:(.param,1,1)) { args,_ in
            return try args[0].cdr
        }
        define(name:"eq",args:(.param,2,2)) { args,env in
            return args[0].isEq(args[1]) ? env.TRUE : env.NIL
        }
        define(name:"consp",args:(.param,1,1)) { args,env in
            return args[0] is Cons ? env.TRUE : env.NIL
        }
        define(name:"numberp",args:(.param,1,1)) { args,env in
            return args[0] is Number ? env.TRUE : env.NIL
        }
        define(name:"atom",args:(.param,1,1)) { args,env in
            return args[0] is Atom || args[0] is Number || args[0] is Str ? env.TRUE : env.NIL
        }
        define(name:"quote",args:(.param,1,1),special:true) { args,_ in
            return args[0]
        }
        define(name:"rplaca",args:(.param,2,2)) { args,_ in
            (args[0] as! Cons).carValue = args[1]
            return args[1]
        }
        define(name:"rplacd",args:(.param,2,2)) { args,_ in
            (args[0] as! Cons).cdrValue = args[1]
            return args[1]
        }
        define(name:"progn",args:(.rest,0,0)) { args,_ in
            return args.last!
        }
        define(name:"print",args:(.rest,0,100)) { args,env in
            for e in args {
                print("\(e) ",terminator: "")
            }
            print()
            return args.last ?? env.NIL
        }
        define(name:"eval",args:(.param,1,1)) { args,env in
            return try args[0].eval(env)
        }
        define(name:"setq",args:(.rest,2,2),special:true) { args,env in
            var r: Expr = env.NIL
            for i in stride(from: 0, to: args.count, by: 2) {
                let v = args[i] as! Atom
                r = try args[i+1].eval(env)
                env.set(v,r)
            }
            return r
        }
        define(name:"list",args:(.rest,0,0)) { args,env in
            return try env.lisp.arrayToList(args)
        }
        define(name:"if",args:(.optional,2,3),special:true) { args,env in
            if args.count > 2 {
                return try !args[0].eval(env).isEq(env.NIL) ? args[1].eval(env) : args[2].eval(env)
            } else {
                return try !args[0].eval(env).isEq(env.NIL) ? args[1].eval(env) : env.NIL
            }
        }
        define(name:"or",args:(.param,2,2),special:true) { args,env in
            let e = try args[0].eval(env)
            if !e.isEq(env.NIL) { return e }
            return try args[1].eval(env)
        }
        define(name:"strformat",args:(.optional,1,100)) { args,env in
            let fmt = try args[0].str
            var va = [any CVarArg]()
            for e in args[1..<args.count] {
                switch e.type {
                case .atom: va.append((e as! Atom).name)
                case .number: va.append((e as! Number).val)
                case .str: va.append((e as! Str).value)
                case .cons: va.append("\(e)")
                case .fun: va.append("\(e)")
                }
            }
            return Str(str:String(format: fmt.replacingOccurrences(of: "%s", with: "%@"), arguments:va))
        }
        define(name:"read",args:(.param,0,0)) { args,env in
            if let stream = env.currInput {
                return try env.lisp.readExpr(stream)!
            }
            print("No input stream set")
            return env.NIL
        }
        define(name:"peekchar",args:(.param,0,0)) { args,env in
            if let stream = env.currInput {
                if let c = stream.peek() {
                    var bb = ""
                    bb.unicodeScalars.append(contentsOf: [c])
                    return Str(str:bb)
                }
                return env.NIL
            }
            print("No input stream set")
            return env.NIL
        }
        define(name:"skipchar",args:(.param,0,0)) { args,env in
            if let stream = env.currInput {
                _ = stream.next()
            } else {
                print("No input stream set")
            }
            return env.NIL
        }
        define(name:"flush",args:(.param,0,0)) { args,env in // TBD
            return env.NIL
        }
        define(name:"readfile",args:(.param,1,1)) { args,env in
            let path = try args[0].str
            if case (false,let msg) = env.lisp.load(path) {
                return Str(str:msg)
            }
            return env.TRUE
        }
        define(name:"readmacro",args:(.param,2,2)) { args,env in
            let sym = args[0] as! Str
            let fun = args[1] as! Func
            env.lisp.readMacros.updateValue(fun, forKey: sym.value)
            return sym
        }
        define(name:"defun",args:(.rest,2,100),special:true) { args,env in
            let name = args[0] as! Atom
            let params = args[1]
            let body = try env.lisp.arrayToList(args[2...])
            let lambda = Cons(car: env.lisp.intern(name:"lambda"),
                              cdr: Cons(car: params,cdr: body))
            let fun = try lambda.eval(env) as! Func
            fun.name = name.name
            fun.ftype = .fun
            name.set(fun)
            return name
        }
        define(name:"defmacro",args:(.rest,2,100),special:true) { args,env in
            let name = args[0]
            let newArgs = args[1...].map { $0 }
            let fun = try lambda(newArgs,env) as! Func
            fun.ftype = .macro
            fun.special = true
            fun.name = "\(name)"
            try name.set(fun)
            return name
        }
        define(name:"while",args:(.rest,1,100),special:true) { args,env in
            let NIL = env.NIL
            let test = args[0]
            while try !test.eval(env).isEq(NIL) {
                for e in args[1...] {
                    try _ = e.eval(env)
                }
            }
            return NIL
        }
        define(name:"cond",args:(.rest,1,100),special:true) { args,env in
            let NIL = env.NIL
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
        define(name:"gensym",args:(.param,0,0)) { args,env in
            return env.lisp.intern(name:"<gensym\(Int.random(in: 1..<10000000))>")
        }
        define(name:"clock",args:(.param,0,0)) { args,env in
            let date = Date()
            return Number(num:date.timeIntervalSince1970 * 1000)
        }
        define(name:"lambda",args:(.rest,1,100),special:true,fun:lambda)
        define(name:"fn",args:(.rest,1,100),special:true,fun:lambda)
        define(name:"let*",args:(.rest,1,100),special:true,fun:let_star)
        define(name:"let",args:(.rest,1,100),special:true,fun:let_star)
    }
}

