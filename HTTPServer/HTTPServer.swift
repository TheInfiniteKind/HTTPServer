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
public func httpConnectionHandler(_ channel: DispatchIO, clientAddress: SocketAddress, queue: DispatchQueue, handler: @escaping RequestHandler) -> () {
    //dispatch_io_set_low_water(channel, 1);
    // high water mark defaults to SIZE_MAX
    channel.setInterval(interval: .milliseconds(10), flags: .strictInterval)

    var accumulated: DispatchData?
    
    var request = RequestInProgress.none
    
    let OperationCancelledError = Int32(89)
    
    channel.read(offset: 0, length: Int.max, queue: queue) {
        (done, data: DispatchData?, error) in
        if (error != 0 && error != OperationCancelledError) {
            print("Error on channel: \(String(cString: strerror(error))) (\(error))")
        }
        // Append the data and update the request:
        if let d = data {
            if accumulated == nil {
                accumulated = d
            } else {
                accumulated!.append(d)
            }
            let r = request.consumeData(accumulated!)
            request = r.request
            accumulated = r.remainder
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



private func splitData(_ data: DispatchData, location: Int) -> (DispatchData, DispatchData) {
    let head = data.subdata(in: 0 ..< location)
    let tail = data.subdata(in: location ..< data.count)
    return (head, tail)
}

private struct RequestInProgressAndRemainder {
    let request: RequestInProgress
    let remainder: DispatchData
    init(_ r: RequestInProgress, _ d: DispatchData) {
        request = r
        remainder = d
    }
}

private enum RequestInProgress {
    case none
    case error
    case incompleteHeader
    case incompleteMessage(CFHTTPMessage, Int)
    case complete(CFHTTPMessage, Int)
    
    func consumeData(_ data: DispatchData) -> RequestInProgressAndRemainder {
        switch self {
        case .error:
            return RequestInProgressAndRemainder(.error, data)
        case .none:
            fallthrough
        case .incompleteHeader:
            let d = data.withUnsafeBytes { bytes in
                return Data(bytes: UnsafeRawPointer(bytes), count: data.count)
            }
//            let d = data as! Data
            guard let r = d.range(of: Data(bytes: UnsafePointer<UInt8>("\r\n\r\n"), count: 4), options: [], in: Range(uncheckedBounds: (lower: 0, upper: d.count)))
            else {
                return RequestInProgressAndRemainder(.incompleteHeader, data)
            }
            let end = Int(r.lowerBound + 4)
            let (header, tail) = splitData(data, location: end)
            let message = CFHTTPMessageCreateEmpty(nil, true).takeRetainedValue()
            message.appendDispatchData(header)
            if !CFHTTPMessageIsHeaderComplete(message) {
                return RequestInProgressAndRemainder(.error, data)
            } else {
                let bodyLength = message.messsageBodyLength()
                if bodyLength <= tail.count {
                    let (head, tail2) = splitData(tail, location: bodyLength)
                    message.appendDispatchData(head) // CFHTTPMessageSetBody() ?
                    return RequestInProgressAndRemainder(.complete(message, bodyLength), tail2)
                }
                return RequestInProgressAndRemainder(.incompleteMessage(message, bodyLength), tail)
            }
        case let .incompleteMessage(message, bodyLength):
            if bodyLength <= data.count {
                let (head, tail) = splitData(data, location: bodyLength)
                message.appendDispatchData(head) // CFHTTPMessageSetBody() ?
                return RequestInProgressAndRemainder(.complete(message, bodyLength), tail)
            }
            return RequestInProgressAndRemainder(.incompleteMessage(message, bodyLength), data)
        case let .complete(message, bodyLength):
            return RequestInProgressAndRemainder(.complete(message, bodyLength), data)
        }
    }
}

