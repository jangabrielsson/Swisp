import BigInt
import Foundation

// MARK: - Feature Registry

var providedFeatures: Set<String> = []

// MARK: - Resource Loading

public func resourcePath(for name: String) -> String? {
    if let path = Bundle.module.path(forResource: name, ofType: "lisp") {
        return path
    }
    let cwd = FileManager.default.currentDirectoryPath
    let fallback = "\(cwd)/\(name).lisp"
    if FileManager.default.fileExists(atPath: fallback) {
        return fallback
    }
    return nil
}

// MARK: - Number Arithmetic

func toDouble(_ expr: SExpr) -> Double {
    switch expr {
    case .number(.integer(let n)): return Double(n)
    case .number(.bigInt(let n)): return Double(n)
    case .number(.float(let n)): return n
    default: fatalError("expected number, got \(expr)")
    }
}

func toNumber(_ expr: SExpr) throws -> Number {
    guard case .number(let n) = expr else { throw LispError("expected number, got \(expr)") }
    return n
}

func fromDouble(_ d: Double) -> Number {
    if d == d.rounded() && d.isFinite, let intVal = Int(exactly: d) {
        return .integer(intVal)
    }
    return .float(d)
}

func addNumbers(_ a: Number, _ b: Number) -> Number {
    switch (a, b) {
    case (.integer(let x), .integer(let y)):
        let (result, overflow) = x.addingReportingOverflow(y)
        if !overflow { return .integer(result) }
        return .bigInt(BigInt(x) + BigInt(y))
    case (.integer(let x), .bigInt(let y)):
        return .bigInt(BigInt(x) + y)
    case (.bigInt(let x), .integer(let y)):
        return .bigInt(x + BigInt(y))
    case (.bigInt(let x), .bigInt(let y)):
        return .bigInt(x + y)
    default:
        return fromDouble(toDouble(.number(a)) + toDouble(.number(b)))
    }
}

func subNumbers(_ a: Number, _ b: Number) -> Number {
    switch (a, b) {
    case (.integer(let x), .integer(let y)):
        let (result, overflow) = x.subtractingReportingOverflow(y)
        if !overflow { return .integer(result) }
        return .bigInt(BigInt(x) - BigInt(y))
    case (.integer(let x), .bigInt(let y)):
        return .bigInt(BigInt(x) - y)
    case (.bigInt(let x), .integer(let y)):
        return .bigInt(x - BigInt(y))
    case (.bigInt(let x), .bigInt(let y)):
        return .bigInt(x - y)
    default:
        return fromDouble(toDouble(.number(a)) - toDouble(.number(b)))
    }
}

func mulNumbers(_ a: Number, _ b: Number) -> Number {
    switch (a, b) {
    case (.integer(let x), .integer(let y)):
        let (result, overflow) = x.multipliedReportingOverflow(by: y)
        if !overflow { return .integer(result) }
        return .bigInt(BigInt(x) * BigInt(y))
    case (.integer(let x), .bigInt(let y)):
        return .bigInt(BigInt(x) * y)
    case (.bigInt(let x), .integer(let y)):
        return .bigInt(x * BigInt(y))
    case (.bigInt(let x), .bigInt(let y)):
        return .bigInt(x * y)
    default:
        return fromDouble(toDouble(.number(a)) * toDouble(.number(b)))
    }
}

func divNumbers(_ a: Number, _ b: Number) -> Number {
    return fromDouble(toDouble(.number(a)) / toDouble(.number(b)))
}

// MARK: - Number Comparison

enum NumberOrder {
    case lt, eq, gt
}

func compareNumbers(_ a: Number, _ b: Number) -> NumberOrder {
    switch (a, b) {
    case (.integer(let x), .integer(let y)):
        if x < y { return .lt }; if x > y { return .gt }; return .eq
    case (.integer(let x), .bigInt(let y)):
        let bx = BigInt(x)
        if bx < y { return .lt }; if bx > y { return .gt }; return .eq
    case (.bigInt(let x), .integer(let y)):
        let by = BigInt(y)
        if x < by { return .lt }; if x > by { return .gt }; return .eq
    case (.bigInt(let x), .bigInt(let y)):
        if x < y { return .lt }; if x > y { return .gt }; return .eq
    default:
        let da = toDouble(.number(a)), db = toDouble(.number(b))
        if da < db { return .lt }; if da > db { return .gt }; return .eq
    }
}

// MARK: - Equality

/// Identity comparison: eq? uses pointer identity for cons cells,
/// value comparison for everything else.
func isEq(_ a: SExpr, _ b: SExpr) -> Bool {
    switch (a, b) {
    case (.cons, .cons):
        return unsafeBitCast(a, to: UnsafeRawPointer.self)
            == unsafeBitCast(b, to: UnsafeRawPointer.self)
    default:
        return a == b
    }
}

// MARK: - Global Environment

public func makeGlobalEnvironment() -> Frame {
    let env = Frame()

    // MARK: - Arithmetic

    env.bindings["+"] = .builtin(Builtin("+") { args in
        guard !args.isEmpty else { return .number(.integer(0)) }
        let nums = try args.map(toNumber)
        return .number(nums.dropFirst().reduce(nums[0], addNumbers))
    })
    env.bindings["-"] = .builtin(Builtin("-") { args in
        guard !args.isEmpty else { throw LispError("-: requires at least one arg") }
        let nums = try args.map(toNumber)
        if args.count == 1 { return .number(subNumbers(.integer(0), nums[0])) }
        return .number(nums.dropFirst().reduce(nums[0], subNumbers))
    })
    env.bindings["*"] = .builtin(Builtin("*") { args in
        guard !args.isEmpty else { return .number(.integer(1)) }
        let nums = try args.map(toNumber)
        return .number(nums.dropFirst().reduce(nums[0], mulNumbers))
    })
    env.bindings["/"] = .builtin(Builtin("/") { args in
        guard !args.isEmpty else { throw LispError("/: requires at least one arg") }
        let nums = try args.map(toNumber)
        if args.count == 1 { return .number(divNumbers(.integer(1), nums[0])) }
        return .number(nums.dropFirst().reduce(nums[0], divNumbers))
    })

    // MARK: - Comparison

    let checkedCmp: (String, @escaping (Number, Number) -> Bool) -> Builtin = { name, op in
        Builtin(name) { args in
            guard args.count >= 2 else { throw LispError("\(name): requires at least two args") }
            let nums = try args.map(toNumber)
            for i in 0 ..< nums.count - 1 {
                if !op(nums[i], nums[i + 1]) { return .boolean(false) }
            }
            return .boolean(true)
        }
    }
    env.bindings["="] = .builtin(checkedCmp("=") { compareNumbers($0, $1) == .eq })
    env.bindings["<"] = .builtin(checkedCmp("<") { compareNumbers($0, $1) == .lt })
    env.bindings[">"] = .builtin(checkedCmp(">") { compareNumbers($0, $1) == .gt })
    env.bindings["<="] = .builtin(checkedCmp("<=") {
        let c = compareNumbers($0, $1); return c == .lt || c == .eq
    })
    env.bindings[">="] = .builtin(checkedCmp(">=") {
        let c = compareNumbers($0, $1); return c == .gt || c == .eq
    })

    // MARK: - List operations

    env.bindings["cons"] = .builtin(Builtin("cons") { args in
        guard args.count == 2 else { throw LispError("cons: requires exactly two args") }
        return .cons(args[0], args[1])
    })
    env.bindings["car"] = .builtin(Builtin("car") { args in
        guard args.count == 1, case .cons(let car, _) = args[0] else {
            throw LispError("car: expected a pair")
        }
        return car
    })
    env.bindings["cdr"] = .builtin(Builtin("cdr") { args in
        guard args.count == 1, case .cons(_, let cdr) = args[0] else {
            throw LispError("cdr: expected a pair")
        }
        return cdr
    })
    env.bindings["null?"] = .builtin(Builtin("null?") { args in
        guard args.count == 1 else { throw LispError("null?: requires exactly one arg") }
        if case .null = args[0] { return .boolean(true) }
        return .boolean(false)
    })
    env.bindings["list"] = .builtin(Builtin("list") { args in
        var result: SExpr = .null
        for arg in args.reversed() {
            result = .cons(arg, result)
        }
        return result
    })
    env.bindings["eq?"] = .builtin(Builtin("eq?") { args in
        guard args.count == 2 else { throw LispError("eq?: requires exactly two args") }
        return .boolean(isEq(args[0], args[1]))
    })

    env.bindings["equal?"] = .builtin(Builtin("equal?") { args in
        guard args.count == 2 else { throw LispError("equal?: requires exactly two args") }
        return .boolean(args[0] == args[1])
    })

    env.bindings["apply"] = .builtin(Builtin("apply") { args in
        guard args.count >= 2 else { throw LispError("apply: requires at least 2 args") }
        let fn = args[0]
        var callArgs: [SExpr] = []
        if args.count > 2 {
            callArgs = Array(args[1..<args.count - 1])
        }
        var current = args.last!
        while case .cons(let car, let cdr) = current {
            callArgs.append(car)
            current = cdr
        }
        let step = apply(fn, callArgs) { val in .done(val) }
        return try trampoline(step)
    })
    env.bindings["funcall"] = .builtin(Builtin("funcall") { args in
        guard args.count >= 1 else { throw LispError("funcall: requires at least 1 arg") }
        let fn = args[0]
        let callArgs = Array(args.dropFirst())
        let step = apply(fn, callArgs) { val in .done(val) }
        return try trampoline(step)
    })

    // MARK: - Feature management

    env.bindings["provide"] = .builtin(Builtin("provide") { args in
        guard args.count == 1, case .symbol(let name) = args[0] else {
            throw LispError("provide: expected a symbol")
        }
        providedFeatures.insert(name)
        return .boolean(true)
    })

    // MARK: - Reader

    env.bindings["read"] = .builtin(Builtin("read") { args in
        guard currentReader != nil else {
            throw LispError("read: no input source")
        }
        if let result = try readOne() {
            return result
        }
        return .null
    })
    env.bindings["read-char"] = .builtin(Builtin("read-char") { args in
        guard let reader = currentReader else {
            throw LispError("read-char: no input source")
        }
        guard let c = reader.readChar() else {
            return .null
        }
        return .string(String(c))
    })
    env.bindings["peek-char"] = .builtin(Builtin("peek-char") { args in
        guard let reader = currentReader else {
            throw LispError("peek-char: no input source")
        }
        guard let c = reader.peekChar() else {
            return .null
        }
        return .string(String(c))
    })
    env.bindings["set-reader-macro-char"] = .builtin(Builtin("set-reader-macro-char") { args in
        guard args.count == 2,
              case .string(let charStr) = args[0],
              charStr.count == 1 else {
            throw LispError("set-reader-macro-char: expected a character string and a function")
        }
        let c = charStr[charStr.startIndex]
        readerDispatchTable[c] = args[1]
        return .boolean(true)
    })

    // MARK: - Predicates

    let typePred: (String, @escaping (SExpr) -> Bool) -> Builtin = { name, pred in
        Builtin(name) { args in
            guard args.count == 1 else { throw LispError("\(name): requires exactly one arg") }
            return .boolean(pred(args[0]))
        }
    }
    env.bindings["number?"] = .builtin(typePred("number?") {
        if case .number = $0 { return true }; return false
    })
    env.bindings["symbol?"] = .builtin(typePred("symbol?") {
        if case .symbol = $0 { return true }; return false
    })
    env.bindings["string?"] = .builtin(typePred("string?") {
        if case .string = $0 { return true }; return false
    })
    env.bindings["boolean?"] = .builtin(typePred("boolean?") {
        if case .boolean = $0 { return true }; return false
    })
    env.bindings["pair?"] = .builtin(typePred("pair?") {
        if case .cons = $0 { return true }; return false
    })

    // MARK: - I/O

    env.bindings["display"] = .builtin(Builtin("display") { args in
        guard args.count == 1 else { throw LispError("display: requires exactly one arg") }
        print(args[0].description, terminator: "")
        return .null
    })
    env.bindings["newline"] = .builtin(Builtin("newline") { _ in
        print()
        return .null
    })
    env.bindings["print"] = .builtin(Builtin("print") { args in
        guard args.count == 1 else { throw LispError("print: requires exactly one arg") }
        print(args[0].description)
        return .null
    })
    env.bindings["error"] = .builtin(Builtin("error") { args in
        let msg = args.map(\.description).joined(separator: " ")
        throw LispError("Error: \(msg)")
    })

    return env
}
