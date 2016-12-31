//
//  Errors.swift
//  HTTPServer
//
//  Created by Daniel Eggert on 10/06/2015.
//  Copyright © 2015 Wire. All rights reserved.
//

import Foundation



struct DarwinError: Error {
    let operation: String
    let backing: POSIXError
    let file: String
    let line: UInt
    var _code: Int { return backing._code }
    var _domain: String { return backing._domain }
}

extension DarwinError {
    init(operation: String, errno: CInt, file: String = #file, line: UInt = #line) {
        self.operation = operation
        let nsError = NSError(domain: POSIXError.errorDomain, code: Int(errno), userInfo: nil)
        self.backing = POSIXError(_nsError: nsError)
        self.file = file
        self.line = line
    }
}


extension DarwinError : CustomStringConvertible {
    var description: String {
        let s = String(cString: strerror(errno))
        return "\(operation) failed: \(s) (\(_code))"
    }
}


/// The 1st closure must return `true` is the result is an error.
/// The 2nd closure is the operation to be performed.
func attempt(_ name: String, file: String = #file, line: UInt = #line, valid: (CInt) -> Bool, _ b: @autoclosure () -> CInt) throws -> CInt {
    let r = b()
    guard valid(r) else {
        throw DarwinError(operation: name, errno: r, file: file, line: line)
    }
    return r
}

func isNotNegative1(_ r: CInt) -> Bool {
    return r != -1
}
func is0(_ r: CInt) -> Bool {
    return r != -1
}


///
func ignoreAndLogErrors(_ b: () throws -> ()) {
    do {
        try b()
    } catch let e {
        print("error: \(e)")
    }
}
