//
//  TCPSocket.swift
//  HTTPServer
//
//  Created by Daniel Eggert on 06/12/2015.
//  Copyright © 2015 Wire. All rights reserved.
//

import Foundation
import SocketHelpers



final class TCPSocket {
    enum Domain {
        case inet
        case inet6
    }
    
    fileprivate let domain: Domain
    fileprivate let backingSocket: CInt
    
    init(domain: Domain) throws {
        self.domain = domain
        self.backingSocket = try DarwinCall.attempt(name: "socket(2)",  valid: .notMinusOne, call: socket(domain.rawValue, SOCK_STREAM, IPPROTO_TCP))
    }
}

extension TCPSocket {
    func close() throws {
        _ = try DarwinCall.attempt(name: "close(2)", valid: .zero, call: Darwin.close(backingSocket))
    }
    
    func listen(maxPendingConnections: CInt = SOMAXCONN) throws {
        _ = try DarwinCall.attempt(name: "listen(2)", valid: .zero, call: Darwin.listen(backingSocket, maxPendingConnections))
    }

    func accept() throws -> ClientSocket {
        // The address has the type `sockaddr`, but could have more data than `sizeof(sockaddr)`. Hence we put it inside a Data instance.
        var addressData = Data(capacity: Int(SOCK_MAXADDRLEN))
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let socket: CInt = try addressData.withUnsafeMutableBytes { (bytes: UnsafeMutablePointer<sockaddr>) in
            return try DarwinCall.attempt(name: "accept(2)", valid: .notMinusOne, call: Darwin.accept(backingSocket, bytes, &length))
        }
        addressData.count = Int(length)
        let address = SocketAddress(data: addressData)
        return ClientSocket(address: address, backingSocket: socket)
    }

    func createDispatchReadSource(with queue: DispatchQueue) -> DispatchSource {
        return DispatchSource.makeReadSource(fileDescriptor: backingSocket, queue: queue) as! DispatchSource
    }
    
    func bind(to port: UInt16) throws {
        try withUnsafeAnySockAddr(port: port) { addr in
            _ = try DarwinCall.attempt(name: "bind(2)", valid: .zero, call: Darwin.bind(backingSocket, addr, socklen_t(MemoryLayout<sockaddr>.size)))
        }
    }
}

extension TCPSocket {
    struct StatusFlag : OptionSet {
        let rawValue: CInt
        static let O_NONBLOCK = StatusFlag(rawValue: 0x0004)
        static let O_APPEND = StatusFlag(rawValue: 0x0008)
        static let O_ASYNC = StatusFlag(rawValue: 0x0040)
    }
    
    /// Set the socket status flags.
    /// Uses `fnctl(2)` with `F_SETFL`.
    func setStatusFlags(_ flag: StatusFlag) throws {
        _ = try DarwinCall.attempt(name: "fcntl(2)", valid: .notMinusOne, call: SocketHelper_fcntl_setFlags(backingSocket, flag.rawValue))
    }
    
    /// Get the socket status flags.
    /// Uses `fnctl(2)` with `F_GETFL`.
    func getStatusFlags(_ flag: StatusFlag) -> StatusFlag {
        return StatusFlag(rawValue: SocketHelper_fcntl_getFlags(backingSocket))
    }
}


extension TCPSocket.Domain {
    fileprivate var rawValue: CInt {
        switch self {
        case .inet: return PF_INET
        case .inet6: return PF_INET6
        }
    }
    
    fileprivate var addressFamily: sa_family_t {
        switch self {
        case .inet: return sa_family_t(AF_INET)
        case .inet6: return sa_family_t(AF_INET6)
        }
    }
}


private let INADDR_ANY = in_addr(s_addr: in_addr_t(0))

extension TCPSocket {
    fileprivate func withUnsafeAnySockAddr(port: UInt16, block: (UnsafePointer<sockaddr>) throws -> ()) rethrows {
        let portN = in_port_t(CFSwapInt16HostToBig(port))
        let addr = UnsafeMutablePointer<sockaddr_in>.allocate(capacity: 1)
        addr.initialize(to: sockaddr_in(sin_len: 0, sin_family: domain.addressFamily, sin_port: portN, sin_addr: INADDR_ANY, sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)))
        defer { addr.deinitialize() }
        let sockaddr_inPtr = UnsafePointer(addr)
        try sockaddr_inPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
            try block(sockaddrPtr)
        }
    }
}
