//
//  HTTPServer.swift
//  HTTPServer
//
//  Created by Daniel Eggert on 03/02/2015.
//  Copyright (c) 2015 objc.io. All rights reserved.
//

import Foundation
import SocketHelpers



public typealias RequestHandler = (_ request: HTTPRequest, _ clientAddress: SocketAddress, _ responseHandler:(HTTPResponse?) -> ()) -> ()



/// This handler can be passed to SocketServer.withAcceptHandler to create an HTTP server.
public func httpConnectionHandler(channel: DispatchIO, clientAddress: SocketAddress, queue: DispatchQueue, handler: @escaping RequestHandler) -> () {
    channel.setLimit(lowWater: 1)
    // high water mark defaults to SIZE_MAX
    channel.setInterval(interval: .milliseconds(10), flags: .strictInterval)

    var accumulated = DispatchData.empty
    var request = RequestInProgress.none
    let OperationCancelledError = Int32(89)
    
    channel.read(offset: 0, length: Int.max, queue: queue) {
        (done, data: DispatchData?, error) in
        if (error != 0 && error != OperationCancelledError) {
            print("Error on channel: \(String(cString: strerror(error))) (\(error))")
        }
        // Append the data and update the request:
        if let d = data {
            accumulated.append(d)
            (request, accumulated) = request.consume(accumulated)
        }
        switch request {
        case let .complete(completeRequest, _):
            handler(HTTPRequest(message: completeRequest), clientAddress, { (maybeResponse) -> () in
                if let response = maybeResponse {
                    channel.write(offset: 0, data: response.serializedData, queue: queue) {
                        (done, data, error) in
                        if error != 0 || done {
                            channel.close(flags: .stop)
                        }
                    }
                } else {
                    channel.close(flags: [])
                }
            })
        case .error:
            channel.close(flags: .stop)
        default:
            break
        }
        if (done) {
            channel.close(flags: [])
        }
    }
}



//MARK:
//MARK: Private
//MARK:


private enum RequestInProgress {
    case none
    case error
    case incompleteHeader
    case incompleteMessage(CFHTTPMessage, Int)
    case complete(CFHTTPMessage, Int)
    
    static let headerEndData = Data(bytes: UnsafePointer<UInt8>("\r\n\r\n"), count: 4)
    
    func consume(_ data: DispatchData) -> (RequestInProgress, DispatchData) {
        switch self {
        case .error:
            return (.error, data)
        case .none, .incompleteHeader:
            let d = data.withUnsafeBytes { bytes in
                Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: bytes), count: data.count, deallocator: .none)
            }
            let fullRange = Range(uncheckedBounds: (lower: 0, upper: d.count))
            guard let headerEndRange = d.range(of: RequestInProgress.headerEndData, options: [], in: fullRange) else {
                return (.incompleteHeader, data)
            }
            let end = Int(headerEndRange.lowerBound + 4)
            let (header, body) = data.split(at: end)
            let message = CFHTTPMessageCreateEmpty(nil, true).takeRetainedValue()
            message.append(header)
            guard CFHTTPMessageIsHeaderComplete(message) else {
                return (.error, data)
            }
            let contentLength = message.contentLength
            if contentLength <= body.count {
                let (content, remainder) = body.split(at: contentLength)
                message.append(content) // CFHTTPMessageSetBody() ?
                return (.complete(message, contentLength), remainder)
            }
            return (.incompleteMessage(message, contentLength), body)
        case let .incompleteMessage(message, contentLength):
            if contentLength <= data.count {
                let (content, remainder) = data.split(at: contentLength)
                message.append(content) // CFHTTPMessageSetBody() ?
                return (.complete(message, contentLength), remainder)
            }
            return (.incompleteMessage(message, contentLength), data)
        case let .complete(message, contentLength):
            return (.complete(message, contentLength), data)
        }
    }
}

