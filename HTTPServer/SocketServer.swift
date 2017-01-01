//
//  SocketServer.swift
//  HTTPServer
//
//  Created by Daniel Eggert on 03/02/2015.
//  Copyright (c) 2015 objc.io. All rights reserved.
//

import Foundation
import SocketHelpers


public enum SocketError : Error {
    case noPortAvailable
}


public final class SocketServer {
    public struct Channel {
        public let channel: DispatchIO
        public let address: SocketAddress
    }
    
    public let port: UInt16
    
    /// The accept handler will be called with a suspended dispatch I/O channel and the client's SocketAddress.
    public convenience init(acceptHandler: @escaping (Channel) -> ()) throws {
        let serverSocket = try TCPSocket(domain: .inet)
        let port = try serverSocket.bindToAnyPort()
        try serverSocket.setStatusFlags(.O_NONBLOCK)
        try self.init(serverSocket: serverSocket, port: port, acceptHandler: acceptHandler)
    }
    
    fileprivate let serverSocket: TCPSocket
    fileprivate let acceptSource: DispatchSource
    
    fileprivate init(serverSocket: TCPSocket, port: UInt16, acceptHandler: @escaping (Channel) -> ()) throws {
        self.serverSocket = serverSocket
        self.port = port
        acceptSource = SocketServer.createDispatchSource(from: serverSocket, port: port, acceptHandler: acceptHandler)
        acceptSource.resume();
        try serverSocket.listen()
    }
    
    fileprivate static func createDispatchSource(from socket: TCPSocket, port: UInt16, acceptHandler: @escaping (Channel) -> ()) -> DispatchSource {
        let queueName = "server on port \(port)"
        let queue = DispatchQueue(label: queueName, attributes: DispatchQueue.Attributes.concurrent);
        let source = socket.createDispatchReadSource(with: queue)
        
        source.setEventHandler {
            source.forEachPendingConnection {
                do {
                    let clientSocket = try socket.accept()
                    let io = clientSocket.createIOChannel(with: queue)
                    let channel = Channel(channel: io, address: clientSocket.address)
                    acceptHandler(channel)
                } catch let e {
                    print("Failed to accept incoming connection: \(e)")
                }
            }
        }
        return source
    }
    
    deinit {
        acceptSource.cancel()
        ignoreAndLogErrors {
            try serverSocket.close()
        }
    }
}


private extension DispatchSource {
    func forEachPendingConnection(_ f: () -> ()) {
        let pendingConnectionCount: UInt = self.data
        for _ in 0..<pendingConnectionCount {
            f()
        }
    }
}


private extension TCPSocket {
    func bindToAnyPort() throws -> UInt16 {
        for port in UInt16(8000 + arc4random_uniform(1000))...10000 {
            do {
                try bindToPort(port)
                return port
            } catch let e as DarwinError where e.backing == POSIXError(.EADDRINUSE) {
                continue
            }
        }
        throw SocketError.noPortAvailable
    }
}
