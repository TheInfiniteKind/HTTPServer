//
//  ClientSocket.swift
//  HTTPServer
//
//  Created by Daniel Eggert on 07/12/2015.
//  Copyright © 2015 Wire. All rights reserved.
//

import Foundation
import SocketHelpers


final class ClientSocket {
    let address: sockaddr_in
    fileprivate let backingSocket: CInt
    
    init(address: sockaddr_in, backingSocket: CInt) {
        self.address = address
        self.backingSocket = backingSocket
    }

    func createIOChannel(with queue: DispatchQueue) -> DispatchIO {
        return DispatchIO(type: .stream, fileDescriptor: backingSocket, queue: queue) { error in
            print("Error on socket: \(error)")
        }
    }
}


extension sockaddr_in: CustomStringConvertible {
    public var description: String {
        if let addr = inAddrDescription, let port = inPortDescription {
            switch sin_family {
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

    fileprivate var inAddrDescription: String? {
        guard [sa_family_t(AF_INET6), sa_family_t(AF_INET)].contains(sin_family) else { return nil }
        var descriptionData = Data(count: Int(INET6_ADDRSTRLEN))
        let result = descriptionData.withUnsafeMutableBytes { (descriptionPtr: UnsafeMutablePointer<Int8>) -> UnsafePointer<Int8>? in
            var addr = sin_addr
            return withUnsafePointer(to: &addr) { (addrPtr: UnsafePointer<in_addr>) in
                return inet_ntop(AF_INET, addrPtr, descriptionPtr, socklen_t(descriptionData.count))
            }
        }
        guard result != nil else { return nil }
        return String(data: descriptionData, encoding: .utf8)
    }
    
    fileprivate var inPortDescription: String? {
        switch sin_family {
        case sa_family_t(AF_INET6), sa_family_t(AF_INET):
            return "\(CFSwapInt16BigToHost(UInt16(sin_port)))"
        default:
            return nil
        }
    }
}
