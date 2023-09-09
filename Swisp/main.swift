//
//  main.swift
//  Swisp
//
//  Created by Jan Gabrielsson on 2023-08-29.
//

import Foundation

print("Swisp v0.1")

let Lisp = LispRuntime()
//Lisp.logger.setFlag(.call,true)
//Lisp.logger.setFlag(.debug,true)    // not used
//Lisp.logger.setFlag(.trace,true)    // not used
//Lisp.logger.setFlag(.warning,true)  // not used
//Lisp.logger.setFlag(.error,true)    // not used
//Lisp.logger.setFlag(.macroexpand,true)
//Lisp.logger.setFlag(.call,true)
//Lisp.logger.setFlag(.callreturn,true)
Lisp.logger.setFlag(.tailcall,true)
//Lisp.logger.setFlag(.readmacro,true)

var input = ConsoleInputStream()
    
while true {
    print("Swisp>", terminator: "")
    do {
        let expr = try Lisp.read(input)
        try print(">\(Lisp.eval(expr))")
    } catch {
        print("Error: \(error)")
        input = ConsoleInputStream()
    }
}
