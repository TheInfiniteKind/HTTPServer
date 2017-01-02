//
//  Errors.swift
//  HTTPServer
//
//  Created by Daniel Eggert on 10/06/2015.
//  Copyright © 2015 Wire. All rights reserved.
//

import Foundation


struct DarwinCall {
    enum Valid {
        case notMinusOne
        case zero
    }
    
    struct Error: Swift.Error {
        let operation: String
        let backing: POSIXError
        let file: String
        let line: UInt
        var _code: Int { return backing._code }
        var _domain: String { return backing._domain }

        init(operation: String, errno: CInt, file: String = #file, line: UInt = #line) {
            self.operation = operation
            let nsError = NSError(domain: POSIXError.errorDomain, code: Int(errno), userInfo: nil)
            self.backing = POSIXError(_nsError: nsError)
            self.file = file
            self.line = line
        }
    }
    
    static func attempt(name: String, file: String = #file, line: UInt = #line, valid: Valid, call: @autoclosure () -> CInt) throws -> CInt {
        return try attempt(name: name, file: file, line: line, valid: valid.predicate, call: call)
    }
    
    /// The 1st closure must return `true` is the result is an error.
    /// The 2nd closure is the operation to be performed.
    fileprivate static func attempt(name: String, file: String = #file, line: UInt = #line, valid: (CInt) -> Bool, call: @autoclosure () -> CInt) throws -> CInt {
        let result = call()
        guard valid(result) else {
            throw DarwinCall.Error(operation: name, errno: result, file: file, line: line)
        }
        return result
    }
}


extension DarwinCall.Valid {
    fileprivate var predicate: (CInt) -> Bool {
        switch self {
        case .notMinusOne: return { $0 != -1 }
        case .zero: return { $0 == 0 }
        }
    }
}

extension DarwinCall.Error: CustomStringConvertible {
    var description: String {
        let s = String(cString: strerror(errno))
        return "\(operation) failed: \(s) (\(_code))"
    }
}


