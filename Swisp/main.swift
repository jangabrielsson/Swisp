//
//  main.swift
//  Swisp
//
//  Created by Jan Gabrielsson on 2023-08-29.
//

import Foundation

print("Hello, World!")

//let tk = Tokenizer()
//do {
//    try tk.tokenize(str:"(999 \"hh jj uu\" . goo _goo_kj 77)")
//} catch {
//   print("\(error)")
//}
//
//print(tk.tokens)
//
//let pp = Parser()
//let tt = Tokenizer()
//try tt.tokenize(str:"(a 99 ( 8 9)  c . d)")
//let expr = try pp.parse(tk:tt)
//print(expr)

let Lisp = LispState()

while true {
    print("Swisp>", terminator: "")
    if let str = readLine() {
        do {
            let expr = try Lisp.parse(str)
            try print(">\(Lisp.eval(expr))")
        } catch {
            print("Error: \(error)")
        }
    }
}

