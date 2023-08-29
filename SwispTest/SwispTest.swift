//
//  SwispTest.swift
//  SwispTest
//
//  Created by Jan Gabrielsson on 2023-08-30.
//

import XCTest
import Swisp
import UnitTestingSwisp

final class SwispTest: XCTestCase {
    let Lisp = LispState()
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testEq() throws {
        XCTAssert(try Lisp.eq(Lisp.NIL,Lisp.NIL))
        XCTAssert(try Lisp.eq(Lisp.TRUE,Lisp.TRUE))
        XCTAssert(try Lisp.eq(Lisp.eval("'foo"),Lisp.eval("'FOO")))
        XCTAssert(try Lisp.eq(Lisp.eval("55"),Lisp.eval("55")))
        XCTAssert(try Lisp.eq(Lisp.eval("\"55\""),Lisp.eval("\"55\"")))
    }

    func testEqual() throws {
        XCTAssert(try Lisp.equal(Lisp.NIL,Lisp.NIL))
        XCTAssert(try Lisp.equal(Lisp.eval("'(a b c)"),Lisp.eval("'(a b c)")))
        XCTAssert(try !Lisp.equal(Lisp.eval("'(a e c)"),Lisp.eval("'(a b c)")))
    }
    
    func testArith() throws {
        XCTAssert(try Lisp.eval("(add 42 42)").num == 84.0)
        XCTAssert(try Lisp.eval("(sub 42 41)").num == 1)
        XCTAssert(try Lisp.eval("(mul 42 10)").num == 420)
        XCTAssert(try Lisp.eval("(div 42 2)").num == 21)
    }
    
    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        measure {
            // Put the code you want to measure the time of here.
        }
    }

}
