//
//  NodeLogic.swift
//  BitSense
//
//  Created by Peter on 26/08/19.
//  Copyright © 2019 Fontaine. All rights reserved.
//

import Foundation

class NodeLogic {
    
    static let dateFormatter = DateFormatter()
    static var walletDisabled = Bool()
    
    class func loadBalances(completion: @escaping ((response: [String:Any]?, errorMessage: String?)) -> Void) {
        if walletDisabled {
            var dictToReturn:[String:Any] = [:]
            dictToReturn["unconfirmedBalance"] = "disabled"
            dictToReturn["onchainBalance"] = "disabled"
            completion((dictToReturn, nil))
        }
    }
    
    class func getPeerInfo(completion: @escaping ((response: [String:Any]?, errorMessage: String?)) -> Void) {
        Reducer.sharedInstance.makeCommand(command: .getpeerinfo) { (response, errorMessage) in
            if let peerInfo = response as? NSArray {
                parsePeerInfo(peerInfo: peerInfo, completion: completion)
            } else {
                 completion((nil, errorMessage ?? ""))
            }
        }
    }
    
    class func getNetworkInfo(completion: @escaping ((response: [String:Any]?, errorMessage: String?)) -> Void) {
        Reducer.sharedInstance.makeCommand(command: .getnetworkinfo) { (response, errorMessage) in
            if let networkInfo = response as? [String:Any] {
                parseNetworkInfo(networkInfo: networkInfo, completion: completion)
            } else {
                completion((nil, errorMessage ?? ""))
            }
        }
    }
    
    class func getMiningInfo(completion: @escaping ((response: [String:Any]?, errorMessage: String?)) -> Void) {
        Reducer.sharedInstance.makeCommand(command: .getmininginfo) { (response, errorMessage) in
            if let miningInfo = response as? [String:Any] {
                parseMiningInfo(miningInfo: miningInfo, completion: completion)
            } else {
                completion((nil, errorMessage ?? ""))
            }
        }
    }
    
    class func getUptime(completion: @escaping ((response: [String:Any]?, errorMessage: String?)) -> Void) {
        Reducer.sharedInstance.makeCommand(command: .uptime) { (response, errorMessage) in
            if let uptime = response as? Double {
                var toReturn = [String:Any]()
                toReturn["uptime"] = Int(uptime)
                completion((toReturn, nil))
            } else {
                completion((nil, errorMessage ?? ""))
            }
        }
    }
    
    class func getMempoolInfo(completion: @escaping ((response: [String:Any]?, errorMessage: String?)) -> Void) {
        Reducer.sharedInstance.makeCommand(command: .getmempoolinfo) { (response, errorMessage) in
            if let dict = response as? [String:Any] {
                var mempoolInfo = [String:Any]()
                mempoolInfo["mempoolCount"] = dict["size"] as? Int ?? 0
                completion((mempoolInfo, nil))
            } else {
                completion((nil, errorMessage ?? ""))
            }
        }
    }
    
    class func estimateSmartFee(completion: @escaping ((response: [String:Any]?, errorMessage: String?)) -> Void) {
        let feeRate = UserDefaults.standard.integer(forKey: "feeTarget")
        let param:Estimate_Smart_Fee_Param = .init(["conf_target":feeRate])
        var toReturn = [String:Any]()
        Reducer.sharedInstance.makeCommand(command: .estimatesmartfee(param: param)) { (response, errorMessage) in
            if let result = response as? [String:Any] {
                if let feeRate = result["feerate"] as? Double {
                    let btcperbyte = feeRate / 1000
                    let satsperbyte = (btcperbyte * 100000000).avoidNotation
                    toReturn["feeRate"] = "\(satsperbyte) sats/byte"
                    completion((toReturn, nil))
                } else {
                    if let errors = result["errors"] as? NSArray {
                        toReturn["feeRate"] = "\(errors[0] as! String)"
                        completion((toReturn, nil))
                    }
                }
            } else {
                completion((nil, errorMessage ?? ""))
            }
        }
    }
    
    class func loadTransactions(completion: @escaping ((response: [[String:Any]]?, errorMessage: String?)) -> Void) {
        if !walletDisabled {
            let param:List_Transactions = .init(["count": 100])
            Reducer.sharedInstance.makeCommand(command: .listtransactions(param)) { (response, errorMessage) in
                if let transactions = response as? NSArray {
                    if transactions.count > 0 {
                        parseTransactions(transactions: transactions) { txArray in
                            completion((txArray, nil))
                        }
                    } else {
                        completion(([], nil))
                    }
                }
            }
        } else {
            completion(([], nil))
        }
    }
        
    private class func saveLocally(txid: String, date: Date) {
        let dict = [
            "txid":txid,
            "id":UUID(),
            "memo":"no transaction memo",
            "date":date,
            "label":""
        ] as [String:Any]

        CoreDataService.saveEntity(dict: dict, entityName: .transactions) { _ in }
    }
    
    // MARK: Section 1 parsers
    
    class func parseMiningInfo(miningInfo: [String:Any], completion: @escaping ((response: [String:Any]?, errorMessage: String?)) -> Void) {
        var miningInfoToReturn = [String:Any]()
        let hashesPerSecond = miningInfo["networkhashps"] as? Double ?? 0.0
        let exahashesPerSecond = hashesPerSecond / 1000000000000000000
        miningInfoToReturn["networkhashps"] = Int(exahashesPerSecond).withCommas
        completion((miningInfoToReturn, nil))
    }
    
    class func parsePeerInfo(peerInfo: NSArray, completion: @escaping ((response: [String:Any]?, errorMessage: String?)) -> Void) {
        var peerInfoToReturn = [String:Any]()
        var incomingCount = 0
        var outgoingCount = 0
        
        for peer in peerInfo {
            let peerDict = peer as! [String:Any]
            let incoming = peerDict["inbound"] as! Bool
            
            if incoming {
                incomingCount += 1
                peerInfoToReturn["incomingCount"] = incomingCount
            } else {
                outgoingCount += 1
                peerInfoToReturn["outgoingCount"] = outgoingCount
            }
        }
        
        completion((peerInfoToReturn, nil))
    }
    
    class func parseNetworkInfo(networkInfo: [String:Any], completion: @escaping ((response: [String:Any]?, errorMessage: String?)) -> Void) {
        var networkInfoToReturn = [String:Any]()
        let subversion = (networkInfo["subversion"] as! String).replacingOccurrences(of: "/", with: "")
        let version = subversion.replacingOccurrences(of: "Satoshi:", with: "")
        networkInfoToReturn["subversion"] = version
        let versionInt = networkInfo["version"] as! Int
        UserDefaults.standard.set(versionInt, forKey: "version")
        
        let networks = networkInfo["networks"] as! NSArray
        
        for network in networks {
            let dict = network as! [String:Any]
            let name = dict["name"] as! String
            
            if name == "onion" {
                let reachable = dict["reachable"] as! Bool
                networkInfoToReturn["reachable"] = reachable
            }
        }
        
        completion((networkInfoToReturn, nil))
    }
    
    class func parseTransactions(transactions: NSArray, completion: @escaping (([[String:Any]])) -> Void) {
        var arrayToReturn:[[String:Any]] = []
        
        for (x, item) in transactions.enumerated() {
            if let transaction = item as? [String:Any] {
                var label = String()
                var replaced_by_txid = String()
                let address = transaction["address"] as? String ?? ""
                let amount = transaction["amount"] as? Double ?? 0.0
                let amountString = amount.avoidNotation
                let confsCheck = transaction["confirmations"] as? Int ?? 0
                
                let confirmations = String(confsCheck)
                
                if let replaced_by_txid_check = transaction["replaced_by_txid"] as? String {
                    replaced_by_txid = replaced_by_txid_check
                }
                
                if let labelCheck = transaction["label"] as? String {
                    label = labelCheck
                    if labelCheck == "" || labelCheck == "," {
                        label = ""
                    }
                } else {
                    label = ""
                }
                
                let secondsSince = transaction["time"] as? Double ?? 0.0
                let rbf = transaction["bip125-replaceable"] as? String ?? ""
                let txID = transaction["txid"] as? String ?? ""
                
                let date = Date(timeIntervalSince1970: secondsSince)
                dateFormatter.dateFormat = "MMM-dd-yyyy HH:mm"
                let dateString = dateFormatter.string(from: date)
                
                let amountSats = amountString.btcToSats
                let amountBtc = amountString.doubleValue.avoidNotation
                let fxRate = UserDefaults.standard.object(forKey: "fxRate") as? Double ?? 0.0
                let amountFiat = (amountBtc.doubleValue * fxRate).balanceTextWithNoSymbol
                
                let tx = [
                    "address": address,
                    "amountBtc": amountBtc,
                    "amountSats": amountSats,
                    "amountFiat": amountFiat,
                    "confirmations": confirmations,
                    "label": label,
                    "date": dateString,
                    "rbf": rbf,
                    "txID": txID,
                    "replacedBy": replaced_by_txid,
                    "selfTransfer": false,
                    "remove": false,
                    "onchain": true,
                    "isLightning": false,
                    "sortDate": date
                ] as [String:Any]
                
                arrayToReturn.append(tx)
                                
                func saveLocally() {
                    #if DEBUG
                    print("saveLocally")
                    #endif
                    var labelToSave = "no transaction label"
                    
                    if label != "" {
                        labelToSave = label
                    }
                    
                    let dict = [
                        "txid":txID,
                        "id":UUID(),
                        "memo":"no transaction memo",
                        "date":date,
                        "label":labelToSave
                    ] as [String:Any]
                    
                    CoreDataService.saveEntity(dict: dict, entityName: .transactions) { _ in }
                }
                
                CoreDataService.retrieveEntity(entityName: .transactions) { txs in
                    guard let txs = txs, txs.count > 0 else {
                        saveLocally()
                        completion(arrayToReturn)
                        return
                    }
                    
                    var alreadySaved = false
                    
                    for (i, tx) in txs.enumerated() {
                        let txStruct = TransactionStruct(dictionary: tx)
                        if txStruct.txid == txID {
                            alreadySaved = true
                        }
                        if i + 1 == txs.count, x + 1 == transactions.count {
                            if !alreadySaved {
                                saveLocally()
                            }
                            completion(arrayToReturn)
                        }
                    }
                }
            }
        }
    }
}
