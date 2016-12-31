//
//  HTTPMessage.swift
//  HTTPServer
//
//  Created by Daniel Eggert on 07/12/2015.
//  Copyright © 2015 Wire. All rights reserved.
//

import Foundation



/// This is a HTTP request that a client has sent us.
public struct HTTPRequest {
    fileprivate let message: CFHTTPMessage
    
    init(message m: CFHTTPMessage) {
        message = m
        assert(CFHTTPMessageIsRequest(message), "Message is a response, not a request.")
    }
    
    public var bodyData: Data {
        return CFHTTPMessageCopyBody(message)?.takeRetainedValue() as Data? ?? Data()
    }
    
    public var method: String {
        return CFHTTPMessageCopyRequestMethod(message)!.takeRetainedValue() as String
    }
    
    public var URL: Foundation.URL {
        return CFHTTPMessageCopyRequestURL(message)!.takeRetainedValue() as URL
    }
    
    public var allHeaderFields: [String:String] {
        if let fields = CFHTTPMessageCopyAllHeaderFields(message)?.takeRetainedValue() as? NSDictionary {
            if let f = fields as? [String:String] {
                return f
            }
        }
        return [:]
    }
    
    public func headerField(_ fieldName: String) -> String? {
        return CFHTTPMessageCopyHeaderFieldValue(message, fieldName as CFString)?.takeRetainedValue() as? String
    }
}

/// This is a HTTP response we'll be sending back to the client.
public struct HTTPResponse {
    fileprivate var message: Message
    public init(statusCode: Int, statusDescription: String?) {
        let status  = statusDescription ?? statusCode.defaultHTTPStatusDescription ?? "Unknown"
        message = Message(message: CFHTTPMessageCreateResponse(kCFAllocatorDefault, CFIndex(statusCode), status as CFString?, kCFHTTPVersion1_1).takeRetainedValue())
        // We don't support keep-alive
        CFHTTPMessageSetHeaderFieldValue(message.backing, "Connection" as CFString, "close" as CFString?)
    }
    
    public var bodyData: Data {
        get {
            return CFHTTPMessageCopyBody(message.backing)?.takeRetainedValue() as Data? ?? Data()
        }
        set(data) {
            ensureUnique()
            CFHTTPMessageSetBody(message.backing, data as CFData)
        }
    }
    
    public mutating func setHeaderField(_ fieldName: String, value: String?) {
        ensureUnique()
        if let v = value {
            CFHTTPMessageSetHeaderFieldValue(message.backing, fieldName as CFString, v as CFString?)
        } else {
            CFHTTPMessageSetHeaderFieldValue(message.backing, fieldName as CFString, nil)
        }
    }
}

extension HTTPResponse : CustomStringConvertible {
    public var description: String {
        return ""
//        return String(data: message.backing.serialized() as! Data, encoding: String.Encoding.utf8) ?? ""
    }
}



extension HTTPResponse {
    var serializedData: DispatchData {
        return message.backing.serialized()
    }
    
    fileprivate mutating func ensureUnique() {
        if !isKnownUniquelyReferenced(&message) {
            message = message.copy()
        }
    }
}

extension HTTPResponse {
    fileprivate class Message {
        let backing: CFHTTPMessage
        init(message m: CFHTTPMessage) {
            backing = m
        }
        func copy() -> Message {
            return Message(message: CFHTTPMessageCreateCopy(kCFAllocatorDefault, backing).takeRetainedValue())
        }
    }
}


extension CFHTTPMessage {
    func messsageBodyLength() -> Int {
        // https://tools.ietf.org/html/rfc2616 section 4.4 "Message Length"
        let contentLenght = CFHTTPMessageCopyHeaderFieldValue(self, "Content-Length" as CFString)?.takeRetainedValue() as? NSString
        let transferEncoding = CFHTTPMessageCopyHeaderFieldValue(self, "Transfer-Encoding" as CFString)?.takeRetainedValue() as? String
        guard let l = contentLenght, transferEncoding != nil else { return 0 }
        return Int(l.integerValue)
    }
    func appendDispatchData(_ data: DispatchData) {
        data.enumerateBytes(block: { buffer, idx, stop in
            if let base = buffer.baseAddress {
                CFHTTPMessageAppendBytes(self, base, CFIndex(buffer.count))
            }
            stop = false
        })
    }
    func serialized() -> DispatchData {
        let data = CFHTTPMessageCopySerializedMessage(self)!.takeRetainedValue() as NSData
        let uint8Ptr = data.bytes.assumingMemoryBound(to: UInt8.self)
        let gcdData = DispatchData(bytesNoCopy: UnsafeBufferPointer(start: uint8Ptr, count: data.length), deallocator: .custom(DispatchQueue.global(), {
            _ = Unmanaged.passUnretained(data)
            return
        }))
        return gcdData
    }
}
