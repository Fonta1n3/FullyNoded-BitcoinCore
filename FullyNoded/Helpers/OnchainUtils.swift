//
//  OnchainUtils.swift
//  FullyNoded
//
//  Created by Peter Denton on 8/13/21.
//  Copyright © 2021 Fontaine. All rights reserved.
//

import Foundation

class OnchainUtils {
    static func listWalletDir(completion: @escaping ((wallets: WalletDir?, message: String?)) -> Void) {
        Reducer.sharedInstance.makeCommand(command: .listwalletdir) { (response, errorMessage) in
            guard let walletDir = response as? [String:Any] else {
                completion((nil, errorMessage ?? "Unknown Error"))
                return
            }
            
            completion((WalletDir(walletDir), nil))
        }
    }
    
    static func listWallets(completion: @escaping ((wallets: [String]?, message: String?)) -> Void) {
        Reducer.sharedInstance.makeCommand(command: .listwallets) { (response, errorMessage) in
            guard let response = response as? [String] else {
                completion((nil, errorMessage ?? "Unknown error."))
                return
            }
            
            completion((response, nil))
        }
    }
    
    static func getWalletInfo(completion: @escaping ((walletInfo: WalletInfo?, message: String?)) -> Void) {
        Reducer.sharedInstance.makeCommand(command: .getwalletinfo) { (response, message) in
            guard let response = response as? [String:Any] else {
                completion((nil, message ?? "Unknown error."))
                return
            }
            
            completion((WalletInfo(response), nil))
        }
    }
    
    static func getDescriptorInfo(_ param: Get_Descriptor_Info, completion: @escaping ((descriptorInfo: DescriptorInfo?, message: String?)) -> Void) {
        Reducer.sharedInstance.makeCommand(command: .getdescriptorinfo(param: param)) { (response, message) in
            guard let response = response as? [String:Any] else {
                completion((nil, message ?? "Unknown error."))
                return
            }
            
            completion((DescriptorInfo(response), nil))
        }
    }
    
    static func importDescriptors(_ param: Import_Descriptors, completion: @escaping ((imported: Bool, message: String?)) -> Void) {
        Reducer.sharedInstance.makeCommand(command: .importdescriptors(param: param)) { (response, message) in
            guard let responseArray = response as? [[String:Any]] else {
                completion((false, "Error importing descriptors: \(message ?? "unknown error")"))
                return
            }
            
            var warnings:String?
            
            for (i, response) in responseArray.enumerated() {
                var errorMessage = ""
                
                guard let success = response["success"] as? Bool, success else {
                    if let error = response["error"] as? [String:Any], let messageCheck = error["message"] as? String {
                        errorMessage = "Error importing descriptors: \(messageCheck)"
                    }
                    
                    completion((false, errorMessage))
                    return
                }
                
                if let warningsCheck = response["warnings"] as? [String] {
                    warnings = warningsCheck.description
                }
                                
                if i + 1 == responseArray.count {
                    completion((true, warnings))
                }
            }
        }
    }
    
    static func rescan(completion: @escaping ((started: Bool, message: String?)) -> Void) {
        OnchainUtils.getBlockchainInfo { (blockchainInfo, message) in
            guard let blockchainInfo = blockchainInfo else {
                completion((false, message))
                return
            }
            
            guard blockchainInfo.pruned else {
                OnchainUtils.rescanNow(from: 0) { (started, message) in
                    completion((started, message))
                }
                
                return
            }
            
            OnchainUtils.rescanNow(from: blockchainInfo.pruneheight) { (started, message) in
                completion((started, message))
            }
        }
    }
    
    static func getBlockchainInfo(completion: @escaping ((blockchainInfo: BlockchainInfo?, message: String?)) -> Void) {
        Reducer.sharedInstance.makeCommand(command: .getblockchaininfo) { (response, errorMessage) in
            guard let dict = response as? [String:Any] else {
                completion((nil, errorMessage))
                return
            }
            
            completion((BlockchainInfo(dict), errorMessage))
        }
    }
    
    static func rescanNow(from: Int, completion: @escaping ((started: Bool, message: String?)) -> Void) {
        let param: Rescan_Blockchain = .init(["start_height": from])
        // current behavior of bitcoin core is to wait until the rescan completes before responding, which is terrible.
        // this command may fail, as a work around users need to refresh the home screen to see if it was successful.
        Reducer.sharedInstance.makeCommand(command: .rescanblockchain(param)) { (_, _) in }
        completion((true, nil))
        
    }
    
    static func createWallet(param: Create_Wallet_Param, completion: @escaping ((name: String?, message: String?)) -> Void) {
        Reducer.sharedInstance.makeCommand(command: .createwallet(param: param)) { (response, errorMessage) in
            guard let response = response as? [String:Any] else {
                completion((nil, errorMessage))
                return
            }
                        
            let warning = response["warning"] as? String
            let walletName = response["name"] as? String
            completion((walletName, warning))
        }
    }
    
    static func listUnspent(param: List_Unspent, completion: @escaping ((utxos: [Utxo]?, message: String?)) -> Void) {
        activeWallet { wallet in
            guard let wallet = wallet else { completion((nil, "No active wallet.")); return }
            Reducer.sharedInstance.makeCommand(command: .listunspent(param)) { (response, errorMessage) in
                guard let response = response as? [[String:Any]] else {
                    // Load from cache.
//                    CoreDataService.retrieveEntity(entityName: .utxos) { utxos in
//                        guard let utxos = utxos, utxos.count > 0 else {
//                            completion((nil, errorMessage))
//                            return
//                        }
//
//                        var utxosToReturn:[Utxo] = []
//
//                        for (i, utxo) in utxos.enumerated() {
//                            let utxoStr = Utxo(utxo)
//
//                            if utxoStr.walletId == wallet.id {
//                                utxosToReturn.append(utxoStr)
//                            }
//
//                            if i + 1 == utxos.count {
//                                completion((utxosToReturn, nil))
//                            }
//                        }
//                    }
                    completion((nil, errorMessage ?? "Unable to fetch utxos from your node."))
                    return
                }
                
                updateUtxoCache(wallet: wallet, utxos: response)
                
                guard response.count > 0 else {
                    completion(([], nil))
                    return
                }
                
                var utxosToReturn:[Utxo] = []
                
                for (i, dict) in response.enumerated() {
                    let utxoObject = Utxo(dict)
                    utxosToReturn.append(utxoObject)
                    if i + 1 == response.count {
                        completion((utxosToReturn, nil))
                    }
                }
            }
        }
    }
    
    static func updateUtxoCache(wallet: Wallet, utxos: [[String:Any]]) {
        CoreDataService.retrieveEntity(entityName: .utxos) { cachedUtxos in
            guard let cachedUtxos = cachedUtxos else { return }
            
            // Delete all cached utxos for that wallet.
            if cachedUtxos.count > 0 {
                for cachedUtxo in cachedUtxos {
                    let cachedUtxoStr = Utxo(cachedUtxo)
                    if cachedUtxoStr.walletId == wallet.id {
                        CoreDataService.deleteEntity(id: cachedUtxoStr.id!, entityName: .utxos) { deleted in
                            print("utxo deleted from cache")
                        }
                    }
                }
            }
            
            if utxos.count > 0 {
                for fetchedUtxo in utxos {
                    var fetchedUtxoDict = fetchedUtxo
                    fetchedUtxoDict["walletId"] = wallet.id
                    fetchedUtxoDict["id"] = UUID()
                    let fetchedUtxoDictToSave = UtxoResponse(fetchedUtxoDict).dict
                    CoreDataService.saveEntity(dict: fetchedUtxoDictToSave, entityName: .utxos) { utxoSaved in
                        print("utxo saved to cache: \(utxoSaved)")
                    }
                }
            }
        }
    }
    
    static func deriveAddresses(param: Derive_Addresses, completion: @escaping ((addresses: [String]?, message: String?)) -> Void) {        
        Reducer.sharedInstance.makeCommand(command: .deriveaddresses(param: param)) { (response, errorMessage) in
            guard let addresses = response as? [String] else {
                
                if let em = errorMessage, em.contains("Missing checksum") {
                    
                    let getdescinfo_p: Get_Descriptor_Info = .init(["descriptor":(param.param["descriptor"] as! String)])
                    
                    OnchainUtils.getDescriptorInfo(getdescinfo_p) { (descriptorInfo, message_) in
                        guard let descInfo = descriptorInfo else {
                            completion((nil, message_))
                            return
                        }
                        let newp:Derive_Addresses = .init(["descriptor": descInfo.descriptor, "range": param.param["range"] as! NSArray])
                        OnchainUtils.deriveAddresses(param: newp, completion: completion)
                    }
                    
                } else {
                    completion((nil, errorMessage))
                }
                return
            }
            
            completion((addresses, errorMessage))
        }
    }
    
    static func getAddressInfo(address: String, completion: @escaping ((addressInfo: AddressInfo?, message: String?)) -> Void) {
        let param:Get_Address_Info = .init(["address": address])
        Reducer.sharedInstance.makeCommand(command: .getaddressinfo(param: param)) { (response, errorMessage) in
            guard let response = response as? [String:Any] else {
                completion((nil, errorMessage))
                return
            }
            
            completion((AddressInfo(response), errorMessage))
        }
    }
    
    static func getBalance(completion: @escaping ((balance: Double?, message: String?)) -> Void) {
        let gb_param = [
            "dummy": "*",
            "minconf": 0,
            "include_watchonly": true,
            "avoid_reuse": false
        ] as [String:Any]
        
        Reducer.sharedInstance.makeCommand(command: .getbalance(param: .init(gb_param))) { (response, errorMessage) in
            guard let response = response as? Double else {
                guard let responseInt = response as? Int else {
                    completion((nil, errorMessage))
                    return
                }
                completion((Double(responseInt), errorMessage))
                return
            }
            completion((response, errorMessage))
        }
    }
    
    // MARK: TODO - add an address tool here to look up signers that can sign for a specific address.
     
}
