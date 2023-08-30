//
//  InputStream.swift
//  Swisp
//
//  Created by Jan Gabrielsson on 2023-08-30.
//

import Foundation

protocol InputStream {
    func nextChar() -> CType
    func isEof() -> Bool
}

typealias CType = Unicode.Scalar

class StringInputStream : InputStream {
    var str: String.UnicodeScalarView
    var s: String.Index
    var e: String.Index
    
    func nextChar() -> CType {
        let c = str[s]
        s = str.index(after:s)
        return c
    }
    
    func isEof() -> Bool {
        return s < e
    }
    init(_ str: String) {
        self.str = str.unicodeScalars
        s = str.startIndex
        e = str.endIndex

    }
}

class FileInputStream : InputStream {
    func nextChar() -> CType {
        return CType(0)
    }
    
    func isEof() -> Bool {
        return true
    }
    
    init() {
    }
}

class ConsoleInputStream : InputStream {
    var str: String.UnicodeScalarView = "".unicodeScalars
    var s: String.Index
    var e: String.Index
    
    func nextChar() -> CType {
        if s < e {
            let c = str[s]
            s = str.index(after:s)
            return c
        }
        str = readLine()!.unicodeScalars
        s = str.startIndex
        e = str.endIndex
        return nextChar()
    }
    
    func isEof() -> Bool {
        return false
    }
    
    init() {
        s = str.startIndex
        e = str.endIndex
    }
}
