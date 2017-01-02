//
//  ClientSocket.swift
//  HTTPServer
//
//  Created by Daniel Eggert on 07/12/2015.
//  Copyright © 2015 Wire. All rights reserved.
//

import Foundation
import SocketHelpers


/// A socket that connects to a client, i.e. a program that connected to us.
final class ClientSocket {
    let address: SocketAddress
    fileprivate let backingSocket: CInt
    
    init(address: SocketAddress, backingSocket: CInt) {
        self.address = address
        self.backingSocket = backingSocket
    }

    func createIOChannel(with queue: DispatchQueue) -> DispatchIO {
        return DispatchIO(type: .stream, fileDescriptor: backingSocket, queue: queue) { error in
            print("Error on socket: \(error)")
        }
    }
}


public struct SocketAddress {
    /// Wraps a `sockaddr`, but could have more data than `sizeof(sockaddr)`
    let data: Data
    
    var address: sockaddr_in {
        return data.withUnsafeBytes { (bytes: UnsafePointer<sockaddr_in>) in bytes.pointee }
    }
}


extension SocketAddress : CustomStringConvertible {
    public var description: String {
        if let addr = inAddrDescription, let port = inPortDescription {
            switch address.sin_family {
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
    fileprivate var inAddrDescription: String? {
        return data.withUnsafeBytes { (dataPtr: UnsafePointer<sockaddr_in>) in
            guard [sa_family_t(AF_INET6), sa_family_t(AF_INET)].contains(address.sin_family) else { return nil }
            var descriptionData = Data(count: Int(INET6_ADDRSTRLEN))
            let inAddr = UnsafeRawPointer(dataPtr) + offsetOf__sin_addr__in__sockaddr_in()
            let result = descriptionData.withUnsafeMutableBytes { (descriptionPtr: UnsafeMutablePointer<Int8>) in
                inet_ntop(AF_INET, inAddr, descriptionPtr, socklen_t(descriptionData.count))
            }
            guard result != nil else { return nil }
            return String(data: descriptionData, encoding: .utf8)
        }
    }
    
    fileprivate var inPortDescription: String? {
        switch address.sin_family {
        case sa_family_t(AF_INET6), sa_family_t(AF_INET):
            return "\(CFSwapInt16BigToHost(UInt16(address.sin_port)))"
        default:
            return nil
        }
    }
}
