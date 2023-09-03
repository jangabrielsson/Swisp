//
//  main.swift
//  Swisp
//
//  Created by Jan Gabrielsson on 2023-08-29.
//

import Foundation

print("Swisp v0.1")

let Lisp = LispState(trace:true)

var input = ConsoleInputStream()
    
while true {
    print("Swisp>", terminator: "")
    do {
        let expr = try Lisp.read(input)
        //try print("<\(expr)")
        try print(">\(Lisp.eval(expr))")
    } catch {
        print("Error: \(error)")
        input = ConsoleInputStream()
    }
}


