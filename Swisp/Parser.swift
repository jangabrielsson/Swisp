//
//  Parser.swift
//  Swisp
//
//  Created by Jan Gabrielsson on 2023-08-29.
//

class Parser {
    typealias Token = Tokenizer.Token
    
    var lisp: LispState?
    var pushbackToken: Token?
    var lastToken: Token?
    
    func nextToken(_ tk: Tokenizer) throws -> Token {
        if let token = pushbackToken {
            pushbackToken = nil
            return token
        }
        lastToken = try tk.next()
        return lastToken!
    }
    
    func pushback() { pushbackToken = lastToken }
    
    func pp(tk: Tokenizer) throws -> Expr {
        var t = try nextToken(tk)
        switch t.token {
        case .NUM: return Number(num:Double(t.value) ?? 0)
        case .STR: return Str(str:t.value)
        case .SYM:
            if lisp!.readMacros[t.value] != nil {
                let fun = lisp!.readMacros[t.value]!.fun
                let env = Env(lisp!)
                env.currInput = tk.stream
                return try fun([],env)
            }
            return lisp!.intern(name:t.value.uppercased())
        case .QUOTE: return try Cons(car: lisp!.QUOTE!,cdr: Cons(car:pp(tk:tk), cdr: lisp!.NIL))
        case .LPAR:
            t = try nextToken(tk)
            if t.token == .RPAR {
                return lisp!.NIL
            } else {
                pushback()
                let l = try Cons(car: pp(tk:tk),cdr: lisp!.NIL)
                var p = l
                while true {
                    t = try nextToken(tk)
                    switch t.token {
                    case .RPAR: return l
                    case .DOT:
                        p.cdrValue = try pp(tk:tk)
                        t = try nextToken(tk)
                        if t.token != .RPAR { throw LispError.parseError("Missing ')' at line: \(t.line)") }
                        return l
                    case .EOF:
                        throw LispError.parseError("Missing ')' at .line: \(t.line)")
                    default:
                        pushback()
                        p.cdrValue = try Cons(car:pp(tk:tk), cdr:lisp!.NIL)
                        p = p.cdr as! Cons
                    }
                }
            }
        case .TOKEN:
            if lisp!.readMacros[t.value] != nil {
                let fun = lisp!.readMacros[t.value]!.fun
                let env = Env(lisp!)
                env.currInput = tk.stream
                return try fun([],env)
            }
            return lisp!.intern(name:t.value)
        default: throw LispError.parseError("Bad expr at line: \(t.line)")
        }
    }
    
    func readExpr(_ stream: InputStream) throws -> Expr {
        let tk = Tokenizer(stream)
        let t = try nextToken(tk)
        if t.token == Tokenizer.TokenType.EOF {
            return lisp!.NIL
        }
        pushback()
        return try pp(tk:tk)
    }
}

