//
//  ClientSocket.swift
//  HTTPServer
//
//  Created by Daniel Eggert on 07/12/2015.
//  Copyright © 2015 Wire. All rights reserved.
//

import Foundation
import SocketHelpers



public struct SocketAddress {
    /// Wraps a `sockaddr`, but could have more data than `sizeof(sockaddr)`
    let addressData: Data
}



/// A socket that connects to a client, i.e. a program that connected to us.
struct ClientSocket {
    let address: SocketAddress
    fileprivate let backingSocket: CInt
    init(address: SocketAddress, backingSocket: CInt) {
        self.address = address
        self.backingSocket = backingSocket
    }
}


extension ClientSocket {
    /// Creates a dispatch I/O channel associated with the socket.
    func createIOChannelWithQueue(_ queue: DispatchQueue) -> DispatchIO {
        return DispatchIO(__type: DispatchIO.StreamType.stream.rawValue, fd: backingSocket, queue: queue) {
            error in
            let nsError = NSError(domain: POSIXError.errorDomain, code: Int(error), userInfo: nil)
            let e = POSIXError(_nsError: nsError)
            print("Error on socket: \(e)")
        }
    }
}


extension SocketAddress : CustomStringConvertible {
    public var description: String {
        if let addr = inAddrDescription, let port = inPortDescription {
            switch inFamily {
            case sa_family_t(AF_INET6):
                return "[" + addr + "]:" + port
            case sa_family_t(AF_INET):
                return addr + ":" + port
            default:
                break
            }
        }
        return "<unknown>"
    }
}

extension SocketAddress {
    fileprivate var inFamily: sa_family_t {
        let pointer = (addressData as NSData).bytes.bindMemory(to: sockaddr_in.self, capacity: addressData.count)
        return pointer.pointee.sin_family
    }
    fileprivate var inAddrDescription: String? {
        let pointer = (addressData as NSData).bytes.bindMemory(to: sockaddr_in.self, capacity: addressData.count)
        switch inFamily {
        case sa_family_t(AF_INET6):
            fallthrough
        case sa_family_t(AF_INET):
            let data = NSMutableData(length: Int(INET6_ADDRSTRLEN))!
            let inAddr = (UnsafeRawPointer(pointer) + offsetOf__sin_addr__in__sockaddr_in())
            let dst = data.mutableBytes.assumingMemoryBound(to: Int8.self)
            if inet_ntop(AF_INET, inAddr, dst, socklen_t(data.length)) != nil {
                return (NSString(data: data as Data, encoding: String.Encoding.utf8.rawValue)! as String)                }
            return nil
        default:
            return nil
        }
    }
    fileprivate var inPortDescription: String? {
        let pointer = (addressData as NSData).bytes.bindMemory(to: sockaddr_in.self, capacity: addressData.count)
        switch inFamily {
        case sa_family_t(AF_INET6):
            fallthrough
        case sa_family_t(AF_INET):
            return "\(CFSwapInt16BigToHost(UInt16(pointer.pointee.sin_port)))"
        default:
            return nil
        }
    }
}
