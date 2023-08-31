//
//  InputStream.swift
//  Swisp
//
//  Created by Jan Gabrielsson on 2023-08-30.
//

import Foundation

protocol InputStream {
    func next() -> CType
    func peek() -> CType?
    func flushLine()
    func isEof() -> Bool
}

typealias CType = Unicode.Scalar

class StringInputStream : InputStream {
    var lines: [String.UnicodeScalarView]
    var s: String.Index
    var e: String.Index
    
    private func read() {
        _ = lines.removeFirst()
        if !isEof() {
            s = lines.first!.startIndex
            e = lines.first!.endIndex
        }
    }
    
    func next() -> CType {
        let c = lines.first![s]
        s = lines.first!.index(after:s)
        return c
    }
    
    func peek() -> CType? {
        if isEof() { return nil }
        if s >= e { read() }
        if isEof() { return nil }
        return lines.first![s]
    }

    func flushLine() {
        read()
    }
    
    func isEof() -> Bool {
        return lines.isEmpty
    }
    
    init(_ str: String) {
        lines = str.split(whereSeparator: \.isNewline).map{ String($0).unicodeScalars }
        s = lines.first!.startIndex
        e = lines.first!.endIndex

    }
}

class FileInputStream : InputStream { // ToDo
    func next() -> CType {
        return CType(0)
    }

    func flushLine() {
    }
    
    func peek() -> CType? {
        return isEof() ? nil : CType(0)
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
    
    private func read() {
        str = readLine(strippingNewline:false)!.unicodeScalars
        s = str.startIndex
        e = str.endIndex
    }
    
    func flushLine() {
        read()
    }
    
    func next() -> CType {
        if s < e {
            let c = str[s]
            s = str.index(after:s)
            return c
        }
        read()
        return next()
    }
    
    func peek() -> CType? {
        return isEof() ? nil : str[s]
    }
    
    func isEof() -> Bool {
        if s >= e { read() }
        return s >= e
    }
    
    init() {
        s = str.startIndex
        e = str.endIndex
    }
}
