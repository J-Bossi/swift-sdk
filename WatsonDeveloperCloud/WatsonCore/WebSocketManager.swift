/**
 * Copyright IBM Corporation 2015
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 **/

import Foundation
import Starscream

// TODO: Should the writeX() functions add operation to queue if connectWithToken() fails?

class WebSocketManager {

    private let authStrategy: AuthenticationStrategy
    private let operations = NSOperationQueue()
    private let socket: WebSocket
    private var isConnecting = false
    private var retries = 0
    private var maxRetries = 1

    var onText: (String -> Void)?
    var onData: (NSData -> Void)?
    var onError: (NSError -> Void)?

    init(authStrategy: AuthenticationStrategy, url: NSURL, protocols: [String]? = nil) {
        print("Initializing WebSocketManager") // TODO: debugging
        self.authStrategy = authStrategy

        operations.maxConcurrentOperationCount = 1
        operations.suspended = true

        socket = WebSocket(url: url, protocols: protocols)
        socket.onConnect = {
            print("socket did connect") // TODO: debugging
            self.operations.suspended = false
            self.isConnecting = false
            self.retries = 0
        }
        socket.onDisconnect = { error in
            print("socket did disconnect") // TODO: debugging
            print("error: \(error)") // TODO: debugging
            self.operations.suspended = true
            self.isConnecting = false
            if self.isAuthenticationFailure(error) {
                print("onDisconnect calling connectWithToken()") // TODO: debugging
                self.connectWithToken()
            } else if let error = error {
                self.onError?(error)
            }
        }
        socket.onText = { text in
            print("received message: \(text)") // TODO: debugging
            self.onText?(text)
        }
        socket.onData = { data in
            print("received data") // TODO: debugging
            self.onData?(data)
        }
        print("init calling connectWithToken()")
        connectWithToken()
    }

    func writeData(data: NSData) {
        if !socket.isConnected {
            print("writeData calling connectWithToken()") // TODO: debugging
            connectWithToken()
        }
        operations.addOperationWithBlock {
            print("executing writeData operation") // TODO: debugging
            self.socket.writeData(data)
        }
    }

    func writeString(str: String) {
        if !socket.isConnected {
            print("writeString calling connectWithToken()") // TODO: debugging
            connectWithToken()
        }
        operations.addOperationWithBlock {
            print("executing writeString operation") // TODO: debugging
            self.socket.writeString(str)
        }
    }

    func writePing(data: NSData) {
        if !socket.isConnected {
            print("writePing calling connectWithToken()") // TODO: debugging
            connectWithToken()
        }
        operations.addOperationWithBlock {
            print("executing writePing operation") // TODO: debugging
            self.socket.writePing(data)
        }
    }

    func disconnect(forceTimeout: NSTimeInterval? = nil) {
        if !operations.suspended {
            operations.waitUntilAllOperationsAreFinished()
        }
        socket.disconnect(forceTimeout: forceTimeout)
    }

    private func connectWithToken() {
        print("Connecting with token.") // TODO: debugging
        print("Retries: \(retries)") // TODO: debugging
        guard !isConnecting else {
            return
        }

        guard retries++ < maxRetries else {
            let domain = "WebSocketManager.swift"
            let code = -1
            let description = "Invalid HTTP upgrade. Please verify your credentials."
            let userInfo = [NSLocalizedDescriptionKey: description]
            let error = NSError(domain: domain, code: code, userInfo: userInfo)
            onError?(error)
            return
        }
        print("Passed guard statement...") // TODO: debugging

        if let token = authStrategy.token where retries == 0 {
            print("Using token: \(token)") // TODO: debugging
            self.socket.headers["X-Watson-Authorization-Token"] = token
            isConnecting = true
            self.socket.connect()
        } else {
            authStrategy.refreshToken { error in
                guard error == nil else {
                    if let error = error {
                        self.onError?(error)
                    }
                    return
                }
                guard let token = self.authStrategy.token else {
                    let domain = "WebSocketManager.swift"
                    let code = -1
                    let description = "Could not obtain an authentication token."
                    let userInfo = [NSLocalizedDescriptionKey: description]
                    let error = NSError(domain: domain, code: code, userInfo: userInfo)
                    self.onError?(error)
                    return
                }
                self.socket.headers["X-Watson-Authorization-Token"] = token
                self.isConnecting = true
                self.socket.connect()
            }
        }
    }

    private func isAuthenticationFailure(error: NSError?) -> Bool {
        // TODO: check for 401 error code
        return false
    }
}
