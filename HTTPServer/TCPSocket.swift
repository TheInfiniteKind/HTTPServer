//
//  TCPSocket.swift
//  HTTPServer
//
//  Created by Daniel Eggert on 06/12/2015.
//  Copyright © 2015 Wire. All rights reserved.
//

import Foundation
import SocketHelpers



struct TCPSocket {
    enum Domain {
        case inet
        case inet6
    }
    fileprivate let domain: Domain
    fileprivate let backingSocket: CInt
    init(domain d: Domain) throws {
        domain = d
        backingSocket = try attempt("socket(2)",  valid: isNotNegative1, socket(d.rawValue, SOCK_STREAM, IPPROTO_TCP))
    }
}

extension TCPSocket {
    /// Close the socket.
    func close() throws {
        _ = try attempt("close(2)", valid: is0, Darwin.close(backingSocket))
    }
    /// Listen for connections.
    /// Start accepting incoming connections and set the queue limit for incoming connections.
    func listen(_ backlog: CInt = SOMAXCONN) throws {
        _ = try attempt("listen(2)", valid: is0, Darwin.listen(backingSocket, backlog))
    }
}

extension TCPSocket {
    /// Accept a connection.
    /// Retruns the resulting client socket.
    func accept() throws -> ClientSocket {
        // The address has the type `sockaddr`, but could have more data than `sizeof(sockaddr)`. Hence we put it inside an NSData instance.
        let addressData = NSMutableData(length: Int(SOCK_MAXADDRLEN))!
        let p = UnsafeMutablePointer<sockaddr>(mutating: addressData.bytes.bindMemory(to: sockaddr.self, capacity: addressData.length))
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let socket = try attempt("accept(2)", valid: isNotNegative1, Darwin.accept(backingSocket, p, &length))
        addressData.length = Int(length)
        let address = SocketAddress(addressData: addressData as Data)
        return ClientSocket(address: address, backingSocket: socket)
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
        _ = try attempt("fcntl(2)", valid: isNotNegative1, SocketHelper_fcntl_setFlags(backingSocket, flag.rawValue))
    }
    /// Get the socket status flags.
    /// Uses `fnctl(2)` with `F_GETFL`.
    func getStatusFlags(_ flag: StatusFlag) -> StatusFlag {
        return StatusFlag(rawValue: SocketHelper_fcntl_getFlags(backingSocket))
    }
}

extension TCPSocket {
    func createDispatchReadSourceWithQueue(_ queue: DispatchQueue) -> DispatchSource {
        return DispatchSource.makeReadSource(fileDescriptor: backingSocket, queue: queue) /*Migrator FIXME: Use DispatchSourceRead to avoid the cast*/ as! DispatchSource
    }
}

//extension TCPSocket.StatusFlag {
//    init?(rawValue: Self.RawValue) {
//        switch
//    }
//}


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
    fileprivate func withUnsafeAnySockAddrWithPort(_ port: UInt16, block: (UnsafePointer<sockaddr>) throws -> ()) rethrows {
        let portN = in_port_t(CFSwapInt16HostToBig(port))
        let addr = UnsafeMutablePointer<sockaddr_in>.allocate(capacity: 1)
        addr.initialize(to: sockaddr_in(sin_len: 0, sin_family: domain.addressFamily, sin_port: portN, sin_addr: INADDR_ANY, sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)))
        defer { addr.deinitialize() }
        let sockaddr_inPtr = UnsafePointer(addr)
        try sockaddr_inPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
            try block(sockaddrPtr)
        }
    }
    func bindToPort(_ port: UInt16) throws {
        try withUnsafeAnySockAddrWithPort(port) { addr in
            _ = try attempt("bind(2)", valid: is0, bind(backingSocket, addr, socklen_t(MemoryLayout<sockaddr>.size)))
        }
    }
}
