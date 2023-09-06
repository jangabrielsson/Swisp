//
//  InputStream.swift
//  Swisp
//
//  Created by Jan Gabrielsson on 2023-08-30.
//

import Foundation

protocol InputStream : Expr {
    func next() -> CType
    func peek() -> CType?
    func flushLine()
    func isEof() -> Bool
    var line: Int { get }
}

typealias CType = Unicode.Scalar

class StringInputStream : InputStream {
    let type: DataType = .stream
    var lines: [String.UnicodeScalarView]
    var s: String.Index
    var e: String.Index
    var line: Int
    
    private func read() {
        _ = lines.removeFirst()
        if !isEof() {
            line += 1
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
    
    public var description: String { return "<StringInputStream:\(ObjectIdentifier(self))>" }
    
    init(_ str: String) {
        lines = str.components(separatedBy: CharacterSet.newlines).map{ (String($0)+"\n").unicodeScalars }
        s = lines.first!.startIndex
        e = lines.first!.endIndex
        line = 1
    }
}

class FileInputStream : InputStream {
    let type: DataType = .stream
    let path: String
    var line: Int
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
    
    public var description: String { return "<FileInputStream:\(path)>" }
    init(_ path: String) {
        self.path = path
        line = 1
    }
}

class ConsoleInputStream : InputStream {
    let type: DataType = .stream
    var str: String.UnicodeScalarView = "".unicodeScalars
    var s: String.Index
    var e: String.Index
    var line: Int = 1
    
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
    
    public var description: String { return "<ConsoleInputStream:\(ObjectIdentifier(self))>" }
    init() {
        s = str.startIndex
        e = str.endIndex
    }
}
