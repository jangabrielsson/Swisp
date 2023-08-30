//
//  Parser.swift
//  Swisp
//
//  Created by Jan Gabrielsson on 2023-08-29.
//

class Parser {
    var lisp: LispState?
    
    func nextToken(_ tk: Tokenizer) -> Tokenizer.Token {
        return tk.next()
    }
    func pp(tk: Tokenizer) throws -> Expr {
        var t = nextToken(tk)
        switch t.token {
        case .NUM: return Number(num:Double(t.value) ?? 0)
        case .STR: return Str(str:t.value)
        case .SYM: return lisp!.intern(name:t.value.uppercased())
        case .QUOTE: return try Cons(car: lisp!.QUOTE!,cdr: Cons(car:pp(tk:tk), cdr: lisp!.NIL))
        case .LPAR:
            t = nextToken(tk)
            if t.token == .RPAR {
                return Lisp.NIL
            } else {
                tk.pushBack()
                let l = try Cons(car: pp(tk:tk),cdr: lisp!.NIL)
                var p = l
                while true {
                    t = nextToken(tk)
                    switch t.token {
                    case .RPAR: return l
                    case .DOT:
                        p.cdrValue = try pp(tk:tk)
                        t = nextToken(tk)
                        if t.token != .RPAR { throw LispError.parseError("Missing ')'") }
                        return l
                    case .EOF:
                        throw LispError.parseError("Missing ')'")
                    default:
                        tk.pushBack()
                        p.cdrValue = try Cons(car:pp(tk:tk), cdr:lisp!.NIL)
                        p = p.cdr as! Cons
                    }
                }
            }
        case .TOKEN: return Lisp.intern(name:t.value)
        default: throw LispError.parseError("Bad expr")
        }
    }
    
    func parse(_ stream: InputStream) throws -> Expr {
        
    }
    
    func parse(tk: Tokenizer) throws -> Expr {
        let t = tk.next()
        if t.token == .EOF {
            return Lisp.NIL
        }
        tk.pushBack()
        return try pp(tk:tk)
    }
    
    func parse(str: String) throws -> Expr {
        let tk = Tokenizer()
        try tk.tokenize(str:str)
        return try parse(tk:tk)
    }
}

