//
//  Tokenizer.swift
//  Swisp
//
//  Created by Jan Gabrielsson on 2023-08-29.
//

import Foundation

class Tokenizer {
    var stream: InputStream

    typealias CType = Unicode.Scalar
    
    enum TokenType {
        case STR
        case NUM
        case QUOTE
        case LPAR
        case RPAR
        case DOT
        case SYM
        case TOKEN
        case EOF
    }
    
    static let specToken: [String:TokenType] = [
        "(":TokenType.LPAR,
        ")":TokenType.RPAR,
        ".":TokenType.DOT,
        "'":TokenType.QUOTE,
        ">=":TokenType.SYM,
        "<=":TokenType.SYM,
    ]
    
    struct Token: CustomStringConvertible {
        let token: TokenType
        let value: String
        let line: Int
        public var description: String { return "\(token):\(value)" }
    }
    
    static func buff2str(_ buff: [CType]) -> String {
        var bb = ""
        bb.unicodeScalars.append(contentsOf: buff)
        return bb
    }
    
    static func stringTokenizer(c: CType, s: InputStream) throws -> Token {
        var buff = [CType]()
        while true {
            if s.isEof() { throw LispError.token("Unfinished string at line: \(s.line)") }
            if s.peek() == "\"" { _ = s.next(); break }
            if s.peek() == "\\" {
                _ = s.next()
                switch s.peek() {
                case "n": buff.append("\n"); _ = s.next()
                case "t": buff.append("\t"); _ = s.next()
                case "r": buff.append("\r"); _ = s.next()
                default: buff.append("\\")
                }
            } else { buff.append(s.next()) }
        }
        return Token(token:.STR,value:buff2str(buff),line:s.line)
    }
    
    static func numTokenizer(c: CType, s: InputStream) -> Token {
        var buff = [c]
        while CharacterSet.decimalDigits.contains(s.peek() ?? " ") {
            buff.append(s.next())
        }
        return Token(token:.NUM,value:buff2str(buff),line:s.line)
    }
    
    static func symbolTokenizer(c: CType, s: InputStream) -> Token {
        var buff = [c]
        var isNum = c == "-" || CharacterSet.decimalDigits.contains(c)
        while true {
            let c = s.peek() ?? " "
            if c == "_" || c == "*" || c == "-" || c == "&" || CharacterSet.alphanumerics.contains(c) {
                isNum = isNum && CharacterSet.decimalDigits.contains(c)
                buff.append(s.next())
            } else { break }
        }
        return Token(token: isNum && buff.count > 1 ? .NUM : .SYM,value:buff2str(buff),line:s.line)
    }
    
    static func charTokenizer(c: CType, s: InputStream) -> Token {
        var buff = [c]
        let p = s.peek() ?? " "
        if "><=".unicodeScalars.contains(p) {
            let tt = buff + [p]
            if Tokenizer.specToken[buff2str(tt)] != nil {
                buff.append(p); _ = s.next()
            }
        }
        let str = buff2str(buff)
        return Token(token:Tokenizer.specToken[str, default:.TOKEN],value:str,line:s.line)
    }

    typealias ParseFun = (CType, InputStream) throws -> Token
    
    static func addTokenizerFuns(tm: inout [CType:ParseFun],str:String,tf: @escaping ParseFun) {
        for c in str.unicodeScalars {
            tm[c] = tf
        }
    }
    
    static var tokenizerLookup: [CType:ParseFun] = {
        var tm: [CType:ParseFun] = ["\"" : Tokenizer.stringTokenizer]
        addTokenizerFuns(tm:&tm,str:"()[]+/,.'^`@!#><%", tf: Tokenizer.charTokenizer)
        addTokenizerFuns(tm:&tm,str:"0123456789", tf: Tokenizer.numTokenizer)
        addTokenizerFuns(tm:&tm,str:"-*&_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz", tf: Tokenizer.symbolTokenizer)
        return tm
    }()
    
    func next() throws -> Token {
        
        while (!stream.isEof()) {
            while CharacterSet.whitespacesAndNewlines.contains(stream.peek() ?? ".") { _ = stream.next() }
            if stream.isEof() { return Token(token:.EOF,value:"EOF",line:stream.line) }
            let c = stream.next()
            if (c == "\n" || c.value > 0xF700) { continue } // Newline & Keyboard arrows & friends
            if (c == ";") { stream.flushLine(); continue }
            if let tf = Tokenizer.tokenizerLookup[c] {
                return try tf(c,stream)
            } else {
                throw LispError.token("Bad token: \(c) at line:\(stream.line)")
            }
        }
        return Token(token:.EOF,value:"EOF",line:stream.line)
    }
    
    
    init(_ stream: InputStream) {
        self.stream = stream
    }
}

    
