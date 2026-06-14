import Foundation

// MARK: - CPS Types

public typealias Cont = (SExpr) -> Step

public enum Step {
    case value(SExpr, Cont)
    case eval(SExpr, Frame, Cont)
    case apply(SExpr, [SExpr], Cont)
    case error(String)
    case done(SExpr)
}

// MARK: - Trampoline

public func trampoline(_ initial: Step) throws -> SExpr {
    var step = initial
    // Track last closure frame for tail-call optimization
    var tailFrame: Frame? = nil
    var tailClosureEnv: Frame? = nil

    while true {
        switch step {
        case .done(let v):
            return v
        case .error(let msg):
            throw LispError(msg)
        case .value(let v, let k):
            tailFrame = nil; tailClosureEnv = nil
            step = k(v)
        case .eval(let expr, let env, let k):
            tailFrame = nil; tailClosureEnv = nil
            step = eval(expr, env, k)
        case .apply(let fn, let args, let k):
            // Self-tail-call optimization: same closure → reuse env frame
            if let frame = tailFrame, let prevClosureEnv = tailClosureEnv {
                if case .closure(let params, let rest, let body, let closureEnv) = fn,
                   closureEnv === prevClosureEnv {
                    frame.bindings.removeAll()
                    if let r = rest {
                        guard args.count >= params.count else {
                            throw LispError("arity mismatch: expected at least \(params.count) args, got \(args.count)")
                        }
                        for (p, a) in zip(params, args) { frame.bindings[p] = a }
                        var restList: SExpr = .null
                        for arg in args[params.count...].reversed() { restList = .cons(arg, restList) }
                        frame.bindings[r] = restList
                    } else {
                        guard params.count == args.count else {
                            throw LispError("arity mismatch: expected \(params.count) args, got \(args.count)")
                        }
                        for (p, a) in zip(params, args) { frame.bindings[p] = a }
                    }
                    step = eval(body, frame, k)
                    continue
                }
            }
            // Normal apply
            step = apply(fn, args, k)
            // Save frame if this is a closure application (for tail-call detection)
            if case .closure(_, _, _, let closureEnv) = fn,
               case .eval(_, let env, _) = step {
                tailFrame = env
                tailClosureEnv = closureEnv
            } else {
                tailFrame = nil; tailClosureEnv = nil
            }
        }
    }
}

// MARK: - Eval

public func eval(_ expr: SExpr, _ env: Frame, _ k: @escaping Cont) -> Step {
    switch expr {
    case .null, .number, .string, .boolean, .builtin, .closure, .macro:
        return .value(expr, k)

    case .symbol(let name):
        guard let val = env.lookup(name) else {
            return .error("unbound symbol: \(name)")
        }
        return .value(val, k)

    case .cons(let car, let cdr):
        if case .symbol(let op) = car {
            switch op {
            case "quote": return evalQuote(cdr, env, k)
            case "if": return evalIf(cdr, env, k)
            case "lambda": return evalLambda(cdr, env, k)
            case "define": return evalDefine(cdr, env, k)
            case "define-macro": return evalDefineMacro(cdr, env, k)
            case "set!": return evalSet(cdr, env, k)
            case "setq": return evalSetq(cdr, env, k)
            case "quasiquote": return evalQuasiquote(cdr, env, k)
            case "begin": return evalBegin(cdr, env, k)
            case "require": return evalRequire(cdr, env, k)
            default: break
            }
        }
        return evalApp(expr, env, k)
    }
}

// MARK: - Special Forms

func evalQuote(_ cdr: SExpr, _ env: Frame, _ k: @escaping Cont) -> Step {
    guard case .cons(let quoted, .null) = cdr else {
        return .error("quote: invalid form")
    }
    return .value(quoted, k)
}

func evalIf(_ cdr: SExpr, _ env: Frame, _ k: @escaping Cont) -> Step {
    guard case .cons(let test, .cons(let then, let elseCdr)) = cdr else {
        return .error("if: invalid form")
    }
    return eval(test, env) { testVal in
        if isTruthy(testVal) {
            return eval(then, env, k)
        }
        if case .cons(let else_, .null) = elseCdr {
            return eval(else_, env, k)
        }
        return .value(.null, k)
    }
}

func evalLambda(_ cdr: SExpr, _ env: Frame, _ k: @escaping Cont) -> Step {
    guard case .cons(let params, let bodyForms) = cdr else {
        return .error("lambda: invalid form")
    }

    var paramNames: [String] = []
    var restParam: String? = nil
    var rest = params
    while case .cons(let car, let cdr) = rest {
        guard case .symbol(let name) = car else {
            return .error("lambda: invalid parameter")
        }
        paramNames.append(name)
        rest = cdr
    }
    if case .symbol(let name) = rest {
        restParam = name
    } else if case .null = rest {
        // normal
    } else {
        return .error("lambda: invalid parameter list")
    }

    let body: SExpr
    if case .cons(let single, .null) = bodyForms {
        body = single
    } else {
        body = .cons(.symbol("begin"), bodyForms)
    }
    return .value(.closure(paramNames, restParam, body, env), k)
}

func evalDefine(_ cdr: SExpr, _ env: Frame, _ k: @escaping Cont) -> Step {
    guard case .cons(let nameExpr, let rest) = cdr else {
        return .error("define: invalid form")
    }

    switch nameExpr {
    case .symbol(let name):
        guard case .cons(let valExpr, .null) = rest else {
            return .error("define: invalid form")
        }
        return eval(valExpr, env) { val in
            env.bindings[name] = val
            return .value(.symbol(name), k)
        }

    case .cons(let sym, let params):
        guard case .symbol(let name) = sym else {
            return .error("define: invalid form")
        }
        let lambdaForm: SExpr = .cons(.symbol("lambda"), .cons(params, rest))
        return eval(lambdaForm, env) { val in
            env.bindings[name] = val
            return .value(.symbol(name), k)
        }

    default:
        return .error("define: unexpected form")
    }
}

func evalBegin(_ cdr: SExpr, _ env: Frame, _ k: @escaping Cont) -> Step {
    var exprs: [SExpr] = []
    var rest = cdr
    while case .cons(let car, let cdr) = rest {
        exprs.append(car)
        rest = cdr
    }
    return evalSeq(exprs, env, k)
}

func evalSeq(_ exprs: [SExpr], _ env: Frame, _ k: @escaping Cont) -> Step {
    guard !exprs.isEmpty else { return .value(.null, k) }
    if exprs.count == 1 { return eval(exprs[0], env, k) }
    return eval(exprs[0], env) { _ in
        evalSeq(Array(exprs.dropFirst()), env, k)
    }
}

// MARK: - Macros

func evalDefineMacro(_ cdr: SExpr, _ env: Frame, _ k: @escaping Cont) -> Step {
    guard case .cons(let nameExpr, let rest) = cdr else {
        return .error("define-macro: invalid form")
    }

    if case .cons(let sym, let params) = nameExpr {
        guard case .symbol(let name) = sym else {
            return .error("define-macro: invalid name")
        }
        var paramNames: [String] = []
        var pRest = params
        while case .cons(let car, let cdr) = pRest {
            guard case .symbol(let pName) = car else {
                return .error("define-macro: invalid parameter")
            }
            paramNames.append(pName)
            pRest = cdr
        }
        guard case .null = pRest else {
            return .error("define-macro: invalid parameter list")
        }
        let body: SExpr
        if case .cons(let single, .null) = rest {
            body = single
        } else {
            body = .cons(.symbol("begin"), rest)
        }
        env.bindings[name] = .macro(MacroProc(params: paramNames, body: body, env: env))
        return .value(.symbol(name), k)
    }

    guard case .symbol(let name) = nameExpr else {
        return .error("define-macro: name must be a symbol")
    }
    guard case .cons(let params, let bodyForms) = rest else {
        return .error("define-macro: invalid form")
    }

    var paramNames: [String] = []
    var pRest = params
    while case .cons(let car, let cdr) = pRest {
        guard case .symbol(let pName) = car else {
            return .error("define-macro: invalid parameter")
        }
        paramNames.append(pName)
        pRest = cdr
    }
    guard case .null = pRest else {
        return .error("define-macro: invalid parameter list")
    }

    let body: SExpr
    if case .cons(let single, .null) = bodyForms {
        body = single
    } else {
        body = .cons(.symbol("begin"), bodyForms)
    }

    env.bindings[name] = .macro(MacroProc(params: paramNames, body: body, env: env))
    return .value(.symbol(name), k)
}

// MARK: - Mutation

func evalSet(_ cdr: SExpr, _ env: Frame, _ k: @escaping Cont) -> Step {
    guard case .cons(let nameExpr, .cons(let valExpr, .null)) = cdr else {
        return .error("set!: invalid form")
    }
    guard case .symbol(let name) = nameExpr else {
        return .error("set!: first argument must be a symbol")
    }
    return eval(valExpr, env) { val in
        guard let frame = findFrame(named: name, in: env) else {
            return .error("set!: unbound symbol \(name)")
        }
        frame.bindings[name] = val
        return .value(val, k)
    }
}

func findFrame(named name: String, in env: Frame?) -> Frame? {
    var current = env
    while let frame = current {
        if frame.bindings[name] != nil { return frame }
        current = frame.parent
    }
    return nil
}

func evalSetq(_ cdr: SExpr, _ env: Frame, _ k: @escaping Cont) -> Step {
    evalSetqPairs(cdr, env, k)
}

func evalSetqPairs(_ cdr: SExpr, _ env: Frame, _ k: @escaping Cont) -> Step {
    guard case .cons(let nameExpr, let rest) = cdr else {
        return .value(.null, k)
    }
    guard case .symbol(let name) = nameExpr else {
        return .error("setq: expected a symbol")
    }
    guard case .cons(let valExpr, let more) = rest else {
        return .error("setq: missing value for \(name)")
    }
    return eval(valExpr, env) { val in
        if let frame = findFrame(named: name, in: env) {
            frame.bindings[name] = val
        } else {
            env.bindings[name] = val
        }
        if case .null = more {
            return .value(val, k)
        }
        return evalSetqPairs(more, env, k)
    }
}

// MARK: - Quasiquote

func evalQuasiquote(_ cdr: SExpr, _ env: Frame, _ k: @escaping Cont) -> Step {
    guard case .cons(let expr, .null) = cdr else {
        return .error("quasiquote: invalid form")
    }
    return expandQQ(expr, env, k)
}

func expandQQ(_ expr: SExpr, _ env: Frame, _ k: @escaping Cont) -> Step {
    switch expr {
    case .cons(.symbol("unquote"), .cons(let inner, .null)):
        return eval(inner, env, k)
    case .cons(.symbol("unquote-splicing"), .cons(let inner, .null)):
        return eval(inner, env, k)
    case .cons(let car, let cdr):
        return expandQQCons(car, cdr, env, k)
    default:
        return .value(expr, k)
    }
}

func expandQQCons(_ car: SExpr, _ cdr: SExpr, _ env: Frame, _ k: @escaping Cont) -> Step {
    if case .cons(.symbol("unquote-splicing"), .cons(let inner, .null)) = car {
        return eval(inner, env) { spliceVal in
            expandQQ(cdr, env) { cdrVal in
                var result = cdrVal
                var elements: [SExpr] = []
                var current = spliceVal
                while case .cons(let el, let rest) = current {
                    elements.append(el)
                    current = rest
                }
                for el in elements.reversed() {
                    result = .cons(el, result)
                }
                return .value(result, k)
            }
        }
    }
    return expandQQ(car, env) { carVal in
        expandQQ(cdr, env) { cdrVal in
            .value(.cons(carVal, cdrVal), k)
        }
    }
}

// MARK: - Application

func evalApp(_ expr: SExpr, _ env: Frame, _ k: @escaping Cont) -> Step {
    let list = flattenList(expr)
    return eval(list[0], env) { opVal in
        switch opVal {
        case .macro:
            return applyMacro(opVal, Array(list.dropFirst()), env, k)
        default:
            return evalArgs(Array(list.dropFirst()), env, [], opVal, k)
        }
    }
}

func evalArgs(_ exprs: [SExpr], _ env: Frame, _ acc: [SExpr], _ op: SExpr, _ k: @escaping Cont) -> Step {
    guard !exprs.isEmpty else {
        return .apply(op, acc, k)
    }
    return eval(exprs[0], env) { val in
        evalArgs(Array(exprs.dropFirst()), env, acc + [val], op, k)
    }
}

public func apply(_ fn: SExpr, _ args: [SExpr], _ k: @escaping Cont) -> Step {
    switch fn {
    case .builtin(let builtin):
        do {
            let result = try builtin.fn(args)
            return .value(result, k)
        } catch let e as LispError {
            return .error(e.message)
        } catch {
            return .error("\(error)")
        }

    case .closure(let params, let restParam, let body, let closureEnv):
        if let rest = restParam {
            guard args.count >= params.count else {
                return .error("arity mismatch: expected at least \(params.count) args, got \(args.count)")
            }
            var bindings: [String: SExpr] = [:]
            for (p, a) in zip(params, args) {
                bindings[p] = a
            }
            var restList: SExpr = .null
            for arg in args[params.count...].reversed() {
                restList = .cons(arg, restList)
            }
            bindings[rest] = restList
            let newEnv = Frame(bindings, parent: closureEnv)
            return eval(body, newEnv, k)
        } else {
            guard params.count == args.count else {
                return .error("arity mismatch: expected \(params.count) args, got \(args.count)")
            }
            var bindings: [String: SExpr] = [:]
            for (p, a) in zip(params, args) {
                bindings[p] = a
            }
            let newEnv = Frame(bindings, parent: closureEnv)
            return eval(body, newEnv, k)
        }

    default:
        return .error("cannot apply: \(fn)")
    }
}

public func applyMacro(_ fn: SExpr, _ rawArgs: [SExpr], _ callerEnv: Frame, _ k: @escaping Cont) -> Step {
    guard case .macro(let mp) = fn else {
        return .error("not a macro")
    }
    guard mp.params.count == rawArgs.count else {
        return .error("macro arity mismatch: expected \(mp.params.count), got \(rawArgs.count)")
    }

    if let cached = mp.cachedExpansion(for: rawArgs) {
        return .eval(cached, callerEnv, k)
    }

    var bindings: [String: SExpr] = [:]
    for (p, a) in zip(mp.params, rawArgs) {
        bindings[p] = a
    }
    let newEnv = Frame(bindings, parent: mp.env)
    return eval(mp.body, newEnv) { expansion in
        mp.storeExpansion(rawArgs, expansion)
        return .eval(expansion, callerEnv, k)
    }
}

// MARK: - Require / Provide

func evalRequire(_ cdr: SExpr, _ env: Frame, _ k: @escaping Cont) -> Step {
    guard case .cons(let featureExpr, let rest) = cdr else {
        return .error("require: invalid form")
    }

    return eval(featureExpr, env) { featureVal in
        guard case .symbol(let featureName) = featureVal else {
            return .error("require: feature must be a symbol")
        }

        if providedFeatures.contains(featureName) {
            return .value(.boolean(true), k)
        }

        if case .cons(let pathExpr, .null) = rest {
            return eval(pathExpr, env) { pathVal in
                guard case .string(let path) = pathVal else {
                    return .error("require: path must be a string")
                }
                return loadFile(path, env, k)
            }
        }
        if let foundPath = resourcePath(for: featureName) {
            return loadFile(foundPath, env, k)
        }
        return .error("require: could not find '\(featureName).lisp'")
    }
}

func loadFile(_ path: String, _ env: Frame, _ k: @escaping Cont) -> Step {
    do {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        var tokenizer = Tokenizer(input: content)
        let tokens = try tokenizer.tokenize()
        var parser = Parser(tokens: tokens)
        let exprs = try parser.parseAll()
        _ = evalAll(exprs, env: env)
        return .value(.boolean(true), k)
    } catch {
        return .error("require: could not load '\(path)': \(error)")
    }
}

// MARK: - Helpers

public func isTruthy(_ expr: SExpr) -> Bool {
    if case .boolean(false) = expr { return false }
    return true
}

public func flattenList(_ expr: SExpr) -> [SExpr] {
    var result: [SExpr] = []
    var current = expr
    while case .cons(let car, let cdr) = current {
        result.append(car)
        current = cdr
    }
    return result
}

public func evalAll(_ exprs: [SExpr], env: Frame) -> [SExpr] {
    var results: [SExpr] = []
    for expr in exprs {
        let step = eval(expr, env) { val in .done(val) }
        guard let result = try? trampoline(step) else {
            results.append(.null)
            continue
        }
        results.append(result)
    }
    return results
}
