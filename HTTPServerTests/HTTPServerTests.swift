//
//  HTTPServerTests.swift
//  HTTPServerTests
//
//  Created by Daniel Eggert on 03/02/2015.
//  Copyright (c) 2015 objc.io. All rights reserved.
//

import UIKit
import XCTest
import HTTPServer


class HTTPServerTests: XCTestCase {
    
    var server: SocketServer?
    var port: UInt16?
    
    override func setUp() {
        super.setUp()
        
        let q = DispatchQueue.global()
        do {
            server = try SocketServer() { channel in
                httpConnectionHandler(channel.channel, clientAddress: channel.address, queue: q) {
                    (request, clientAddress, response) in
                    print("Request from \(clientAddress)")
                    var r = HTTPResponse(statusCode: 200, statusDescription: "Ok")
                    r.bodyData = "hey".data(using: String.Encoding.utf8, allowLossyConversion: true)!
                    r.setHeaderField("Content-Length", value: "\(r.bodyData.count)")
                    r.setHeaderField("Foo", value: "Bar")
                    response(r)
                }
                print("New connection")
            }
        } catch let e {
            XCTFail("Unable to create HTTP server: \(e)")
        }
        port = server!.port
    }
    
    override func tearDown() {
        server = nil
        port = nil
        super.tearDown()
    }
    
    func URLComponentsForServer() -> URLComponents {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "localhost"
        components.port = NSNumber(value: Int32(port!) as Int32) as Int?
        return components
    }
    
    func URLForServerWithPath(_ path: String) -> URL {
        var components = URLComponentsForServer()
        components.path = path
        return components.url!
    }
    
    func testASingleRequest() {
        
        let request = URLRequest(url: URLForServerWithPath("/"))
        
        var response: URLResponse?
        do {
            let _ = try NSURLConnection.sendSynchronousRequest(request, returning: &response)
            let httpResponse = response as! HTTPURLResponse
            let headers = httpResponse.allHeaderFields as! [String:String]
            XCTAssertEqual(headers["Foo"]!, "Bar")
            XCTAssertEqual(httpResponse.statusCode, 200)
        } catch let error {
            XCTFail("Unable to get resource: \(error)")
        }
    }
    
    func testTwoRequests() {
        // Make sure both of these load without deadlocking:
        let dataA = try? Data(contentsOf: URLForServerWithPath("/"))
        XCTAssertTrue(dataA != nil)
        let dataB = try? Data(contentsOf: URLForServerWithPath("/"))
        XCTAssertTrue(dataB != nil)
    }
}
