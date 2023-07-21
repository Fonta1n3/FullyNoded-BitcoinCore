//
//  UtxoResponse.swift
//  FullyNoded
//
//  Created by Peter Denton on 7/20/23.
//  Copyright © 2023 Fontaine. All rights reserved.
//

import Foundation

 /*
  [                                (json array)
    {                              (json object)
      "txid" : "hex",              (string) the transaction id
      "vout" : n,                  (numeric) the vout value
      "address" : "str",           (string, optional) the bitcoin address
      "label" : "str",             (string, optional) The associated label, or "" for the default label
      "scriptPubKey" : "str",      (string) the script key
      "amount" : n,                (numeric) the transaction output amount in BTC
      "confirmations" : n,         (numeric) The number of confirmations
      "ancestorcount" : n,         (numeric, optional) The number of in-mempool ancestor transactions, including this one (if transaction is in the mempool)
      "ancestorsize" : n,          (numeric, optional) The virtual transaction size of in-mempool ancestors, including this one (if transaction is in the mempool)
      "ancestorfees" : n,          (numeric, optional) The total fees of in-mempool ancestors (including this one) with fee deltas used for mining priority in sat (if transaction is in the mempool)
      "redeemScript" : "hex",      (string, optional) The redeemScript if scriptPubKey is P2SH
      "witnessScript" : "str",     (string, optional) witnessScript if the scriptPubKey is P2WSH or P2SH-P2WSH
      "spendable" : true|false,    (boolean) Whether we have the private keys to spend this output
      "solvable" : true|false,     (boolean) Whether we know how to spend this output, ignoring the lack of keys
      "reused" : true|false,       (boolean, optional) (only present if avoid_reuse is set) Whether this output is reused/dirty (sent to an address that was previously spent from)
      "desc" : "str",              (string, optional) (only when solvable) A descriptor for spending this output
      "parent_descs" : [           (json array) List of parent descriptors for the scriptPubKey of this coin.
        "str",                     (string) The descriptor string.
        ...
      ],
      "safe" : true|false          (boolean) Whether this output is considered safe to spend. Unconfirmed transactions
                                   from outside keys and unconfirmed replacement transactions are considered unsafe
                                   and are not eligible for spending by fundrawtransaction and sendtoaddress.
    },
    ...
  ]
  */
public struct UtxoResponse: CustomStringConvertible {
    
    let id: UUID
    let address: String?
    var amount: Double
    let desc: String?
    let solvable: Bool?
    let txid: String
    let vout: Int64
    let walletId: UUID
    let confirmations: Int64
    let safe: Bool
    let spendable: Bool
    let reused: Bool?
    let label: String?
    let scriptPubKey: String
    let redeemScript: String?
    let witnessScript: String?
    var dict: [String:Any]
    
    init(_ dictionary: [String: Any]) {
        id = dictionary["id"] as! UUID
        address = dictionary["address"] as? String
        amount = dictionary["amount"] as! Double
        desc = dictionary["desc"] as? String
        txid = dictionary["txid"] as! String
        vout = dictionary["vout"] as! Int64
        walletId = dictionary["walletId"] as! UUID
        confirmations = dictionary["confirmations"] as! Int64
        spendable = dictionary["spendable"] as! Bool
        safe = dictionary["safe"] as! Bool
        reused = dictionary["reused"] as? Bool
        solvable = dictionary["solvable"] as? Bool
        label = dictionary["label"] as? String
        scriptPubKey = dictionary["scriptPubKey"] as! String
        redeemScript = dictionary["redeemScript"] as? String
        witnessScript = dictionary["witnessScript"] as? String
        
        dict = [
            "id": id,
            "amount": amount,
            "txid": txid,
            "vout": vout,
            "walletId": walletId,
            "confirmations": confirmations,
            "spendable": spendable,
            "safe": safe,
            "scriptPubKey": scriptPubKey
        ]
        
        if let address = address {
            dict["address"] = address
        }
        if let desc = desc {
            dict["desc"] = desc
        }
        if let reused = reused {
            dict["reused"] = reused
        }
        if let solvable = solvable {
            dict["solvable"] = solvable
        }
        if let label = label {
            dict["label"] = label
        }
        if let redeemScript = redeemScript {
            dict["redeemScript"] = redeemScript
        }
        if let witnessScript = witnessScript {
            dict["witnessScript"] = witnessScript
        }
    }
    
    public var description: String {
        return "Utxo response from Bitcoin Core to be cached."
    }
}

