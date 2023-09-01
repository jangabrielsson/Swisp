//
//  Builtins.swift
//  Swisp
//
//  Created by Jan Gabrielsson on 2023-08-30.
//

import Foundation

// Builtins gets their arguments evaluated (from Func.call )

//func lambda(_ args: ArgsList, _ env: Env) throws -> Expr {
//    var params: [Atom]
//    var rest: Atom?
//    let a = args[0]
//    if try a.isEq(env.lisp.NIL) {
//        params = []
//    } else if let c = a as? Cons {
//        let pe = try c.toArray() { $0 }
//        params = pe.map() { $0 as! Atom }
//        if params.count > 1 && params[params.count-2].name.hasPrefix("&") {
//            rest = params.popLast()
//            _ = params.popLast()
//        }
//    } else {
//        throw LispError.valueError("Bad lambda parameters")
//    }
//    let body = args
//    let nf = { [params] (_ args:ArgsList,_ env:Env) throws -> Expr in
//        env.push()
//        for i in 0..<params.count {
//            env.bind(params[i],i < args.count ? args[i] : env.lisp.NIL)
//        }
//        if let rest {
//            if args.count > params.count {
//                let val = try env.lisp.arrayToList(args[params.count...]) //{ try $0.eval(env) }
//                env.bind(rest,val)
//            } else { env.bind(rest,env.lisp.NIL) }
//        }
//        var r: Expr?
//        for i in 1..<body.count {
//            r = try body[i].eval(env)
//        }
//        env.pop()
//        return r ?? env.lisp.NIL
//    }
//    return Func(fun:nf,name:"LAMBDA")
//}

enum ParamType {
    case param
    case optional
    case rest
}

func lambda(_ args: ArgsList, _ env: Env) throws -> Expr {
    var params = [Atom]()
    var optionals = [(Atom,Expr)]()
    var rest: Atom?
    let a = args[0]
    if a.isEq(env.lisp.NIL) {
        //
    } else if let c = a as? Cons {
        var state: ParamType = .param
        for e in c {
            if e.isEq(env.lisp.OPTIONAL) {
                if state != .param { throw LispError.valueError("Bad lambda parameters") }
                state = .optional
                continue
            } else if e.isEq(env.lisp.REST) {
                if state == .rest { throw LispError.valueError("Bad lambda parameters") }
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
                    throw LispError.valueError("Bad lambda parameters")
                }
            case .rest: rest = e as? Atom
            }
        }
    } else {
        throw LispError.valueError("Bad lambda parameters")
    }
    let body = args
    let nf = { [params,optionals,rest] (_ args:ArgsList,_ env:Env) throws -> Expr in
        env.push()
        var n = 0
        if args.count < params.count { throw LispError.valueError("Too few parameters, expected \(params.count)") }
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
    return Func(fun:nf,name:"LAMBDA")
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
        define(name:"+") { args,_ in
            return try Number(num: args[0].num + args[1].num)
        }
        define(name:"-") { args,_ in
            return try Number(num: args[0].num - args[1].num)
        }
        define(name:"*") { args,_ in
            return try Number(num: args[0].num * args[1].num)
        }
        define(name:"/") { args,_ in
            return try Number(num: args[0].num / args[1].num)
        }
        define(name:">") { args,env in
            return try args[0].num > args[1].num ? env.lisp.TRUE : env.lisp.NIL
        }
        define(name:"<") { args,env in
            return try args[0].num < args[1].num ? env.lisp.TRUE : env.lisp.NIL
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
            return args[0].isEq(args[1]) ? env.lisp.TRUE : env.lisp.NIL
        }
        define(name:"CONSP") { args,env in
            return args[0].isCons() ? env.lisp.TRUE : env.lisp.NIL
        }
        define(name:"NUMBERP") { args,env in
            return args[0].isNum() ? env.lisp.TRUE : env.lisp.NIL
        }
        define(name:"ATOM") { args,env in
            return args[0].isAtom() ? env.lisp.TRUE : env.lisp.NIL
        }
        define(name:"QUOTE",evaluate:false) { args,_ in
            return args[0]
        }
        define(name:"RPLACA") { args,_ in
            (args[0] as! Cons).carValue = args[1]
            return args[1]
        }
        define(name:"RPLACD") { args,_ in
            (args[0] as! Cons).cdrValue = args[1]
            return args[1]
        }
        define(name:"PROGN") { args,_ in
            return args.last!
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
        define(name:"LIST") { args,env in
            return try env.lisp.arrayToList(args)
        }
        define(name:"IF",evaluate:false) { args,env in
            if args.count > 2 {
                return try !args[0].eval(env).isEq(env.lisp.NIL) ? args[1].eval(env) : args[2].eval(env)
            } else {
                return try !args[0].eval(env).isEq(env.lisp.NIL) ? args[1].eval(env) : env.lisp.NIL
            }
        }
        define(name:"STRFORMAT") { args,env in
            //let fmt = try args[0].str
            return Str(str:"Not implemented yet")
        }
        define(name:"READ") { args,env in
            if let stream = env.currInput {
                return try env.lisp.readExpr(stream)!
            }
            print("No input stream set")
            return env.lisp.NIL
        }
        define(name:"PEEKCHAR") { args,env in
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
        define(name:"SKIPCHAR") { args,env in
            if let stream = env.currInput {
                _ = stream.next()
            } else {
                print("No input stream set")
            }
            return env.lisp.NIL
        }
        define(name:"READFILE") { args,env in
            let path = try args[0].str
            if case (false,let msg) = env.lisp.load(path) {
                return Str(str:msg)
            }
            return env.lisp.TRUE
        }
        define(name:"READMACRO") { args,env in
            let sym = args[0] as! Str
            let fun = args[1] as! Func
            env.lisp.readMacros.updateValue(fun, forKey: sym.value)
            return sym
        }
        define(name:"DEFUN",evaluate:false) { args,env in
            let name = args[0] as! Atom
            let params = args[1]
            let body = try env.lisp.arrayToList(args[2...])
            let lambda = Cons(car: env.lisp.intern(name:"LAMBDA"),
                              cdr: Cons(car: params,cdr: body))
            try name.set(lambda.eval(env))
            return name
        }
        define(name:"DEFMACRO",evaluate:false) { args,env in
            let name = args[0] as! Atom
            let params = args[1]
            let body = try env.lisp.arrayToList(args[2...])
            let lambda = try Cons(car: env.lisp.intern(name:"LAMBDA"),
                              cdr: Cons(car: params,cdr: body)).eval(env) as! Func
            lambda.ev = false
            let nf = { (_ args:ArgsList,_ env:Env) throws -> Expr in
                if env.lisp.trace { print("MACROARGS:\(args)") }
                let res = try lambda.fun(args,env)
                if env.lisp.trace { print("MACROEXP:\(res)") }
                return try res.eval(env)
            }
            let macro = Func(fun:nf,name:"MACRO",evaluate:false)
            name.set(macro)
            return name
        }
        define(name:"WHILE",evaluate: false) { args,env in
            let NIL = env.lisp.NIL
            let test = args[0]
            while try !test.eval(env).isEq(NIL) {
                for e in args[1...] {
                    try _ = e.eval(env)
                }
            }
            return NIL
        }
        
        define(name:"LAMBDA",evaluate:false,fun:lambda)
        define(name:"LET*",evaluate:false,fun:let_star)
    }
}

