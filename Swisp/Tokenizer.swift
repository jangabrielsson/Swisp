//
//  Tokenizer.swift
//  Swisp
//
//  Created by Jan Gabrielsson on 2023-08-29.
//

import Foundation

class Tokenizer {
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
    
    static let specToken: [CType:TokenType] = [
        "(":TokenType.LPAR,
        ")":TokenType.RPAR,
        ".":TokenType.DOT,
        "'":TokenType.QUOTE,
    ]
    
    struct Token: CustomStringConvertible {
        let token: TokenType
        let value: String
        public var description: String { return "\(token):\(value)" }
    }
    
    var tokens = [Token]()
    var tokenPtr = 0
    
    class TState {
        var buff: [CType] = []
        var tokens: [Token] = []
        var tf: ((_ c:Unicode.Scalar?, _ s:TState) throws -> Bool)?
        func buffToStr() -> String {
            var bb = ""
            bb.unicodeScalars.append(contentsOf: buff)
            return bb
        }
        func push(t: TokenType) {
            tokens.append(Token(token:t,value:buffToStr()))
            buff = []
            tf = nil
        }
        func push(t: TokenType, v: String) {
            tokens.append(Token(token:t,value:v))
            buff = []
            tf = nil
        }
    }
    
    static func stringTokenizer(c: CType?, s: TState) throws -> Bool {
        guard let c else {
            throw LispError.tokenError("Unfinished string")
        }
        if c == "\"" && s.buff.count > 0 {
            s.buff.append(c)
            s.push(t:.STR,v:String(s.buffToStr().dropFirst()))
        } else {
            s.buff.append(c)
        }
        return true
    }
    
    static func numTokenizer(c: CType?, s: TState) -> Bool {
        guard let c,c != " " else {
            s.push(t:.NUM)
            return false
        }
        if CharacterSet.decimalDigits.contains(c) {
            s.buff.append(c)
            return true
        } else {
            s.push(t:.NUM)
            return false
        }
    }
    
    static func symbolTokenizer(c: CType?, s: TState) -> Bool {
        guard let c,c != " " else {
            s.push(t:.SYM)
            return false
        }
        if c == "_" || c == "*" || c == "-" || c == "&" || CharacterSet.letters.contains(c) {
            s.buff.append(c)
            return true
        } else {
            s.push(t:.SYM)
            return false
        }
    }
    
    static func charTokenizer(c: CType?, s: TState) -> Bool {
        guard let c else {
            return false
        }
        s.push(t:Tokenizer.specToken[c, default:.TOKEN],v:String(c))
        return true
    }
    
    typealias ParseFun = (CType?, TState) throws -> Bool

    
    static func addTokenizerFuns(tm: inout [CType:ParseFun],str:String,tf: @escaping (CType?, TState) throws -> Bool) {
        for c in str.unicodeScalars {
            tm[c] = tf
        }
    }
    
    static var tokenizerLookup: [CType:ParseFun] = {
        var tm: [CType:ParseFun] = ["\"" : Tokenizer.stringTokenizer]
        addTokenizerFuns(tm:&tm,str:"()[]+/,.'", tf: Tokenizer.charTokenizer)
        addTokenizerFuns(tm:&tm,str:"0123456789", tf: Tokenizer.numTokenizer)
        addTokenizerFuns(tm:&tm,str:"-*&_ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvxyz", tf: Tokenizer.symbolTokenizer)
        return tm
    }()
    
    func tokenize(str: String) throws {
        let state = TState()
        let s = str.unicodeScalars
        for c in s {
            if (c.value > 0xF700) { continue } // Keyboard arrows & friends
            if let tf = state.tf {
                if try tf(c,state) { continue }
            }
            if c == " " { continue }
            if let tf = Tokenizer.tokenizerLookup[c] {
                state.tf = tf
                _ = try tf(c,state)
            } else {
                throw LispError.tokenError("Bad token: \(c)")
            }
        }
        if let tf = state.tf {
            _ = try tf(nil,state)
        }
        tokens = state.tokens
        tokenPtr = -1
    }

    func next() -> Token {
        tokenPtr += 1
        return tokens.count > tokenPtr ? tokens[tokenPtr] : Token(token:TokenType.EOF,value:"")
    }
    
    func pushBack() {
        tokenPtr -= 1
    }
    
    init() {
    }
}

    
