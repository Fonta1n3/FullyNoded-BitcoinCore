//
//  MakeRPCCall.swift
//  BitSense
//
//  Created by Peter on 31/03/19.
//  Copyright © 2019 Fontaine. All rights reserved.
//

import Foundation

class MakeRPCCall {
        
    static let sharedInstance = MakeRPCCall()
    let torClient = TorClient.sharedInstance
    private var attempts = 0
    var connected:Bool = false
    var onDoneBlock : (((response: Any?, errorDesc: String?)) -> Void)?
    var activeNode:NodeStruct?
    var lastSentId:String?
    
    private init() {}
    
    func getActiveNode(completion: @escaping ((NodeStruct?) -> Void)) {
        CoreDataService.retrieveEntity(entityName: .nodes) { nodes in
            guard let nodes = nodes, nodes.count > 0 else {
                completion(nil)
                return
            }
            var activeNode: [String:Any]?
            
            for (i, node) in nodes.enumerated() {
                if let isActive = node["isActive"] as? Bool {
                    if isActive {
                        activeNode = node
                        let n = NodeStruct(dictionary: node)
                        self.activeNode = n
                        completion(n)
                        break
                    }
                }
                
                if i + 1 == nodes.count {
                    guard let active = activeNode else {
                        completion(nil)
                        return
                    }
                }
            }
        }
    }
    
    func executeRPCCommand(method: BTC_CLI_COMMAND, completion: @escaping ((response: Any?, errorDesc: String?)) -> Void) {
        attempts += 1
        if let node = self.activeNode {
            guard let encAddress = node.onionAddress,
                  let encUser = node.rpcuser,
                  let encPassword = node.rpcpassword else {
                completion((nil, "error getting encrypted node credentials"))
                return
            }
            
            let onionAddress = decryptedValue(encAddress)
            let rpcusername = decryptedValue(encUser)
            let rpcpassword = decryptedValue(encPassword)
            
            guard onionAddress != "", rpcusername != "", rpcpassword != "" else {
                completion((nil, "error decrypting node credentials"))
                return
            }
            
            var walletUrl = "http://\(rpcusername):\(rpcpassword)@\(onionAddress)"
            let ud = UserDefaults.standard
            
            if ud.object(forKey: "walletName") != nil {
                if let walletName = ud.object(forKey: "walletName") as? String {
                    let b = isWalletRPC(command: method)
                    if b {
                        walletUrl += "/wallet/" + walletName
                    }
                }
            }
            
            guard let url = URL(string: walletUrl) else {
                completion((nil, "url error"))
                return
            }
            
            var request = URLRequest(url: url)
            var timeout = 10.0
            
            switch method {
            case .gettxoutsetinfo:
                timeout = 1000.0
                
            case .importmulti, .deriveaddresses, .loadwallet:
                timeout = 60.0
                
            default:
                break
            }
            
            let loginString = String(format: "%@:%@", rpcusername, rpcpassword)
            let loginData = loginString.data(using: String.Encoding.utf8)!
            let base64LoginString = loginData.base64EncodedString()
            let id = UUID().uuidString
            
            request.timeoutInterval = timeout
            request.httpMethod = "POST"
            request.addValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
            request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
            
            let dict:[String:Any] = ["jsonrpc":"1.0","id":id,"method":method.stringValue,"params":method.paramDict]
            
            guard let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted) else {
#if DEBUG
                print("converting to jsonData failing...")
#endif
                return
            }
            
            request.httpBody = jsonData
            
#if DEBUG
            print("url = \(url)")
            print("request: \(dict)")
#endif
            
            var sesh = URLSession(configuration: .default)
            
            if onionAddress.contains("onion") {
                sesh = self.torClient.session
            }
            
            let task = sesh.dataTask(with: request as URLRequest) { [weak self] (data, response, error) in
                guard let self = self else { return }
                
                guard let urlContent = data else {
                    
                    guard let error = error else {
                        if self.attempts < 10 {
                            self.executeRPCCommand(method: method, completion: completion)
                        } else {
                            self.attempts = 0
                            completion((nil, "Unknown error, ran out of attempts"))
                        }
                        
                        return
                    }
                    
                    if self.attempts < 10 {
                        self.executeRPCCommand(method: method, completion: completion)
                    } else {
                        self.attempts = 0
                        completion((nil, error.localizedDescription))
                    }
                    
                    return
                }
                
                self.attempts = 0
                
                guard let json = try? JSONSerialization.jsonObject(with: urlContent, options: .mutableLeaves) as? NSDictionary else {
                    if let httpResponse = response as? HTTPURLResponse {
                        switch httpResponse.statusCode {
                        case 401:
                            completion((nil, "Looks like your rpc credentials are incorrect, please double check them. If you changed your rpc creds in your bitcoin.conf you need to restart your node for the changes to take effect."))
                        case 403:
                            completion((nil, "The bitcoin-cli \(method) command has not been added to your rpcwhitelist, add \(method) to your bitcoin.conf rpcwhitelsist, reboot Bitcoin Core and try again."))
                        default:
                            completion((nil, "Unable to decode the response from your node, http status code: \(httpResponse.statusCode)"))
                        }
                    } else {
                        completion((nil, "Unable to decode the response from your node..."))
                    }
                    return
                }
                
#if DEBUG
                print("json: \(json)")
#endif
                
                guard let errorCheck = json["error"] as? NSDictionary else {
                    completion((json["result"], nil))
                    return
                }
                
                guard let errorMessage = errorCheck["message"] as? String else {
                    completion((nil, "Uknown error from bitcoind"))
                    return
                }
                
                completion((nil, errorMessage))
            }
            
            task.resume()
            //}
        } else {
            completion((nil, "No active Bitcoin Core node."))
            return
        }
    }
}

extension String {
    func split(by length: Int) -> [String] {
        var startIndex = self.startIndex
        var results = [Substring]()
        
        while startIndex < self.endIndex {
            let endIndex = self.index(startIndex, offsetBy: length, limitedBy: self.endIndex) ?? self.endIndex
            results.append(self[startIndex..<endIndex])
            startIndex = endIndex
        }
        
        return results.map { String($0) }
    }
}



