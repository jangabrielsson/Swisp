//
//  Builtins.swift
//  Swisp
//
//  Created by Jan Gabrielsson on 2023-08-30.
//

import Foundation
import BigNum

enum ParamType {
    case param
    case optional
    case rest
}


func lambda(_ args: ArgsArray, _ env: Env, tail:Func?=nil) throws -> Func { // Builtins gets their arguments evaluated (from Func.call )
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
    } else if !a.isNIL() {
        throw LispError.syntax("Bad lambda parameters")
    }
    let body = args
    let myEnv = env.copy()
    let nf = { [params,optionals,rest] (_ args0:ArgsArray,_ env:Env, tail:Func?) throws -> Expr in
        let myFunc = env.lastFunc
        if let tf = tail, tf === myFunc {
            env.lisp.log(.tailcall,"\(tf)")
            tf.tailArgs = args0
            return tf
        }
        var args = args0
        myEnv.push()
        while true {
            var n = 0
            if args.count < params.count { throw LispError.param("Too few parameters, expected \(params.count)") }
            for i in n..<params.count { myEnv.bind(params[i],args[i]) }
            n = params.count
            for i in 0..<optionals.count {
                let (v,e) = optionals[i]
                myEnv.bind(v,n+i < args.count ? args[n+i] : try e.eval(myEnv,nil))
            }
            n += optionals.count
            if let rest {
                if args.count > n {
                    let val = try myEnv.lisp.arrayToList(args[n...])
                    myEnv.bind(rest,val)
                } else { myEnv.bind(rest,myEnv.NIL) }
            }
            var r: Expr?
            let np = body.count
            if np > 0 {
                try body[1..<np-1].forEach() { _ = try $0.eval(myEnv,nil) }
                r = try body.last!.eval(myEnv,myFunc)
            }
            if let tf = r as? Func, tf === myFunc { // tail recursive call - loop...
                args = tf.tailArgs!
                continue
            }
            myEnv.pop()
            return r ?? myEnv.NIL
        }
    }
    let fn = Func(name:"lambda",args:(state,params.count,params.count+optionals.count),fun:nf)
    return fn
}

func let_stmt(_ args: ArgsArray, _ env: Env, rec:Bool, tail:Func?=nil) throws -> Expr {
    env.push()
    for p in args[0] as! Cons {
        let v = try p.car as! Atom
        if rec { env.bind(v,env.NIL) }
        try env.bind(v,p.cdr.car.eval(env,nil))
    }
    var res: Expr?
    try args[1...].forEach() { res = try $0.eval(env,nil) }
    env.pop()
    return res ?? env.NIL
}

extension LispRuntime {
    func setupBuiltins() {
        define(name:"+",args:(.param,2,2)) { args,_,_ in
            return try Number(num: args[0].num + args[1].num)
        }
        define(name:"-",args:(.optional,1,2)) { args,_,_ in
            if args.count == 1 { return try Number(num: 0-args[0].num) }
            return try Number(num: args[0].num - args[1].num)
        }
        define(name:"*",args:(.param,2,2)) { args,_,_ in
            return try Number(num: args[0].num * args[1].num)
        }
        define(name:"/",args:(.param,2,2)) { args,_,_ in
            return try Number(num: args[0].num / args[1].num)
        }
        define(name:"%",args:(.param,2,2)) { args,_,_ in
            return try Number(num: args[0].num % args[1].num)
        }
        define(name:">",args:(.param,2,2)) { args,env,_ in
            return try args[0].num > args[1].num ? env.TRUE : env.NIL
        }
        define(name:"<",args:(.param,2,2)) { args,env,_ in
            return try args[0].num < args[1].num ? env.TRUE : env.NIL
        }
        define(name:"cons",args:(.param,2,2)) { args,_,_ in
            return Cons(car: args[0], cdr: args[1])
        }
        define(name:"car",args:(.param,1,1)) { args,_,_ in
            return try args[0].car
        }
        define(name:"cdr",args:(.param,1,1)) { args,_,_ in
            return try args[0].cdr
        }
        define(name:"eq",args:(.param,2,2)) { args,env,_ in
            return args[0].isEq(args[1]) ? env.TRUE : env.NIL
        }
        define(name:"consp",args:(.param,1,1)) { args,env,_ in
            return args[0] is Cons ? env.TRUE : env.NIL
        }
        define(name:"numberp",args:(.param,1,1)) { args,env,_ in
            return args[0] is Number ? env.TRUE : env.NIL
        }
        define(name:"atom",args:(.param,1,1)) { args,env,_ in
            return args[0] is Atom || args[0] is Number || args[0] is Str ? env.TRUE : env.NIL
        }
        define(name:"quote",args:(.param,1,1),special:true) { args,_,_ in
            return args[0]
        }
        define(name:"rplaca",args:(.param,2,2)) { args,_,_ in
            guard let c = args[0] as?  Cons else { throw LispError.value("rplaca needs cons as first value") }
            c.carValue = args[1]
            return args[1]
        }
        define(name:"rplacd",args:(.param,2,2)) { args,_,_ in
            guard let c = args[0] as?  Cons else { throw LispError.value("rplacd needs cons as first value") }
            c.cdrValue = args[1]
            return args[1]
        }
        define(name:"progn",args:(.rest,0,0)) { args,env,tail in
            return args.last ?? env.NIL
        }
        define(name:"print",args:(.rest,0,0)) { args,env,tail in
            var sp = ""
            for e in args {
                print("\(sp)\(e)",terminator: "")
                sp=" "
            }
            return args.last ?? env.NIL
        }
        define(name:"unstr",args:(.param,1,1)) { args,env,tail in
            if let s = args[0] as? Str {
                return Str(str:s.value,quoted:false)
            }
            return args[0]
        }
        define(name:"eval",args:(.param,1,1)) { args,env,tail in
            return try args[0].eval(env,nil)
        }
        define(name:"setq",args:(.rest,2,2),special:true) { args,env,_ in
            var r: Expr = env.NIL
            for i in stride(from: 0, to: args.count, by: 2) {
                if let v = args[i] as? Atom {
                    r = try args[i+1].eval(env,nil)
                    env.set(v,r)
                } else { throw LispError.syntax("setq expects atom") }
            }
            return r
        }
        define(name:"list",args:(.rest,0,0)) { args,env,tail in
            return try env.lisp.arrayToList(args)
        }
        define(name:"if",args:(.optional,2,3),special:true) { args,env,tail in
            if args.count > 2 {
                return try !args[0].eval(env,nil).isNIL() ? args[1].eval(env,tail) : args[2].eval(env,tail)
            } else {
                return try !args[0].eval(env,nil).isNIL() ? args[1].eval(env,tail) : env.NIL
            }
        }
        define(name:"or",args:(.param,2,2),special:true) { args,env,tail in
            let e = try args[0].eval(env,tail)
            if !e.isNIL() { return e }
            return try args[1].eval(env,tail)
        }
        define(name:"and",args:(.param,2,2),special:true) { args,env,tail in
            let e = try args[0].eval(env,nil)
            if !e.isNIL() { return e }
            return try args[1].eval(env,tail)
        }
        define(name:"strformat",args:(.optional,1,100)) { args,env,tail in
            let fmt = try args[0].str
            let va = args[1..<args.count].map(){ e -> any CVarArg in
                switch e.type {
                case .atom, .null: return (e as! Atom).name
                case .number: return "\(e)" //(e as! Number).val)
                case .str: return (e as! Str).value
                case .cons: return "\(e)"
                case .fun: return "\(e)"
                case .stream: return "\(e)"
                }
            }
            return Str(str:String(format: fmt.replacingOccurrences(of: "%s", with: "%@"), arguments:va))
        }
        define(name:"read",args:(.optional,0,1)) { args,env,tail in
            if args.isEmpty { return try env.lisp.readExpr(env.lisp.stdin)! }
            guard let stream = args[0] as? InputStream else { throw LispError.syntax("read wants inputstream argument") }
            return try env.lisp.readExpr(stream)!
        }
        define(name:"peekchar",args:(.param,1,1)) { args,env,tail in
            guard let stream = args[0] as? InputStream else { throw LispError.syntax("peekchar wants inputstream argument") }
            if let c = stream.peek() {
                var bb = ""
                bb.unicodeScalars.append(contentsOf: [c])
                return Str(str:bb)
            }
            return env.NIL
        }
        define(name:"skipchar",args:(.param,1,1)) { args,env,tail in
            guard let stream = args[0] as? InputStream else { throw LispError.syntax("skiphar wants inputstream argument") }
            _ = stream.next()
            return env.NIL
        }
        define(name:"flush",args:(.optional,0,1)) { args,env,tail in // TBD
            if args.isEmpty { env.lisp.stdin.flushLine(); return env.NIL }
            guard let stream = args[0] as? InputStream else { throw LispError.syntax("flush wants inputstream argument") }
            _ = stream.next()
            return env.NIL
        }
        define(name:"readfile",args:(.param,1,1)) { args,env,tail in
            guard let path = args[0] as? Str else { throw LispError.value("readfile wants string as path argument") }
            if case (false,let msg) = env.lisp.load(path.value) {
                return Str(str:msg)
            }
            return env.TRUE
        }
        define(name:"readmacro",args:(.param,2,2)) { args,env,tail in
            guard let sym = args[0] as? Str, let fun = args[1] as? Func else { throw LispError.value("readmacro wants string and function") }
            env.lisp.readMacros.updateValue(fun, forKey: sym.value)
            return sym
        }
        define(name:"defun",args:(.rest,2,100),special:true) { args,env,tail in
            guard let name = args[0] as? Atom else { throw LispError.syntax("defun wants atom as first arg") }
            guard args[1].isNIL() || args[1] is Cons else { throw LispError.syntax("defun wants nil/list as parameter arg") }
            let body = try env.lisp.arrayToList(args[2...])
            let lambda = Cons(car: env.lisp.intern(name:"lambda"),
                              cdr: Cons(car: args[1],cdr: body))
            let fun = try lambda.eval(env) as! Func
            fun.name = name.name
            fun.ftype = .fun
            name.setf(fun)
            return name
        }
        define(name:"defmacro",args:(.rest,2,100),special:true) { args,env,tail in
            guard let name = args[0] as? Atom else { throw LispError.syntax("defmacro wants atom as first arg") }
            let newArgs = args[1...].map { $0 }
            let fun = try lambda(newArgs,env)
            fun.ftype = .macro
            fun.special = true
            fun.name = name.name
            name.setf(fun)
            return name
        }
        define(name:"while",args:(.rest,1,100),special:true) { args,env,tail in
            let NIL = env.NIL
            let test = args[0]
            var res: Expr?
            while try !test.eval(env,nil).isNIL() {
                try args[1...].forEach() { res = try $0.eval(env,nil) }
            }
            return res ?? NIL
        }
        define(name:"cond",args:(.rest,1,100),special:true) { args,env,tail in
            let NIL = env.NIL
            for e in args {
                if let c = e as? Cons {
                    if try !c.carValue.eval(env,nil).isNIL() {
                        let b = c.cdrValue as! Cons
                        var r: Expr?
                        for v in b {
                            r = try v.eval(env,nil)
                        }
                        return r ?? NIL
                    }
                } else { throw LispError.syntax("Bad COND syntax") }
            }
            return NIL
        }
        define(name:"cond",args:(.rest,1,100),special:true) { args,env,tail in
            let NIL = env.NIL
            for e in args {
                if let c = e as? Cons {
                    if try !c.carValue.eval(env,nil).isNIL() {
                        let b = c.cdrValue as! Cons
                        var r: Expr?
                        for v in b {
                            r = try v.eval(env,nil)
                        }
                        return r ?? NIL
                    }
                } else { throw LispError.syntax("Bad COND syntax") }
            }
            return NIL
        }
        define(name:"catch",args:(.param,2,2),special:true) { args,env,tail in
            let tag = try args[0].eval(env,nil)
            do {
                return try args[1].eval(env,nil)
            } catch let error as LispError {
                switch error {
                case .user(_, let tt, let expr):
                    if tt.isEq(tag) { return expr } else { throw error }
                default: throw error
                }
            }
        }
        define(name:"throw",args:(.param,2,2)) { args,env,tail in
            throw LispError.user("throw",args[0] as! Atom,args[1])
        }
        define(name:"gensym",args:(.param,0,0)) { args,env,tail in
            return Atom(name:"<gensym\(Int.random(in: 10000000..<99999999))>")
        }
        define(name:"clock",args:(.param,0,0)) { args,env,tail in
            let date = Date()
            return Number(num:Int(date.timeIntervalSince1970 * 1000))
        }
        define(name:"function",args:(.param,1,1)) { args,env,tail in
            let e = args[0]
            if let c = e as? Cons, c.carValue.isEq(env.lisp.intern(name:"lambda")) {
                var i = c.makeIterator()
                var nargs = [Expr]()
                _ = i.next() // skip lambda
                while let a = i.next() { nargs.append(a) }
                return try lambda(nargs,env,tail:tail)
            }
            if let f = e as? Func {
                return f
            }
            return try e.funVal
        }
        define(name:"funcall",args:(.rest,1,1),special:true) { args,env,tail in
            let f = try args[0].eval(env,nil).funVal
            var nargs = try args[1..<args.count].map() { try f.special ? $0 : $0.eval(env,nil) }
            switch f.nargs { // Check correct number of arguments, exact, with &optionals, and with &rest
            case (.param,let min, _): if nargs.count != min { throw LispError.param("\(f) expecting \(min) args") }
            case (.optional,let min, let max): if nargs.count < min || nargs.count > max { throw LispError.param("\(f) expecting \(min)-\(max) args") }
            case (.rest,let min, _): if nargs.count < min { throw LispError.param("\(f) expecting at least \(min) args") }
            }
            env.lastFunc = f
            var res = try f.fun(nargs,env,tail)
            return res
        }
        define(name:"apply",args:(.param,2,2)) { args,env,tail in
            let f = try args[0].funVal
            if args[1].isEq(env.NIL) { return try f.fun([],env,tail) }
            guard let c = args[1] as? Cons else { throw LispError.syntax("Apply wants nil/list as second argument")}
            var nargs = c.map() { $0 }
            switch f.nargs { // Check correct number of arguments, exact, with &optionals, and with &rest
            case (.param,let min, _): if nargs.count != min { throw LispError.param("\(f) expecting \(min) args") }
            case (.optional,let min, let max): if nargs.count < min || nargs.count > max { throw LispError.param("\(f) expecting \(min)-\(max) args") }
            case (.rest,let min, _): if nargs.count < min { throw LispError.param("\(f) expecting at least \(min) args") }
            }
            env.lastFunc = f
            var res = try f.fun(nargs,env,tail)
            return res
        }
        define(name:"lambda",args:(.rest,1,100),special:true,fun:lambda)
        define(name:"fn",args:(.rest,1,100),special:true,fun:lambda)
        define(name:"nlambda",args:(.rest,1,100),special:true) { args,env,tail in
            let nl = try let_stmt(args,env,rec:true,tail:tail) as! Func
            nl.special = true
            return nl
        }
        
        define(name:"let*",args:(.rest,1,100),special:true) { args,env,tail in
            return try let_stmt(args,env,rec:true,tail:tail)
        }
        define(name:"let",args:(.rest,1,100),special:true) { args,env,tail in
            return try let_stmt(args,env,rec:false,tail:tail)
        }
    }
}
    
