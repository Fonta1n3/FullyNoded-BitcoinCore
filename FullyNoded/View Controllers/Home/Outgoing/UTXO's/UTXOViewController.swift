//
//  UTXOViewController.swift
//  BitSense
//
//  Created by Peter on 30/04/19.
//  Copyright © 2019 Fontaine. All rights reserved.
//

import UIKit
import Dispatch

class UTXOViewController: UIViewController, UITextFieldDelegate, UINavigationControllerDelegate {

    private var amountTotal = 0.0
    private let refresher = UIRefreshControl()
    private var unlockedUtxos = [Utxo]()
    private var inputArray:[[String:Any]] = []
    private var selectedUTXOs = [Utxo]()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var wallet:Wallet?
    private var psbt:String?
    private var depositAddress:String?
    var dataRefresher = UIBarButtonItem()
    var refreshButton = UIBarButtonItem()
    var fxRate:Double?
    var isBtc = false
    var isSats = false
    var isFiat = false
    
    @IBOutlet weak private var tableView: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationController?.delegate = self
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UINib(nibName: UTXOCell.identifier, bundle: nil), forCellReuseIdentifier: UTXOCell.identifier)
        refresher.tintColor = UIColor.white
        refresher.addTarget(self, action: #selector(loadUnlockedUtxos), for: UIControl.Event.valueChanged)
        tableView.addSubview(refresher)
        
        activeWallet { [weak self] wallet in
            guard let self = self else { return }
            guard let wallet = wallet else {
                return
            }
            self.wallet = wallet
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        amountTotal = 0.0
        unlockedUtxos.removeAll()
        selectedUTXOs.removeAll()
        inputArray.removeAll()
        guard let _ = self.wallet else {
            showAlert(vc: self, title: "", message: "No active wallet.")
            return
        }
        loadUnlockedUtxos()
    }
    
    @IBAction private func lockAction(_ sender: Any) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.performSegue(withIdentifier: "goToLocked", sender: self)
        }
    }
            
    private func updateSelectedUtxos() {
        selectedUTXOs.removeAll()
        
        for utxo in unlockedUtxos {
            if utxo.isSelected {
                selectedUTXOs.append(utxo)
            }
        }
    }
    
//    @IBAction private func createRaw(_ sender: Any) {
//
//    }
    
    @objc func createRaw() {
        guard let version = UserDefaults.standard.object(forKey: "version") as? Int, version >= 210000 else {
            showAlert(vc: self, title: "Bitcoin Core needs to be updated",
                      message: "Manual utxo selection requires Bitcoin Core 0.21, please update and try again. If you already have 0.21 go to the home screen, refresh and load it completely then try again.")
            
            return
        }
        
        if self.selectedUTXOs.count > 0 {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                self.updateInputs()
                self.performSegue(withIdentifier: "segueToSendFromUtxos", sender: self)
            }
        } else {
            showAlert(vc: self, title: "Select a UTXO first", message: "Just tap a utxo(s) to select it. Then tap the 🔗 to create a transaction with those utxos.")
        }
    }
    
    private func lock(_ utxo: Utxo) {
        //spinner.addConnectingView(vc: self, description: "locking...")
        addNavBarSpinner()
        
        let param = Lock_Unspent(["unlock": false, "transactions": [["txid": utxo.txid,"vout": utxo.vout] as [String:Any]]])
        
        Reducer.sharedInstance.makeCommand(command: .lockunspent(param)) { (response, errorMessage) in
            guard let success = response as? Bool else {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    self.loadUnlockedUtxos()
                    showAlert(vc: self, title: "", message: errorMessage ?? "unknown error")
                }
                
                return
            }
            
            if success {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    self.loadUnlockedUtxos()
                }
                
                showAlert(vc: self, title: "UTXO Locked 🔐", message: "You can tap the locked button to see your locked utxo's and unlock them. Be aware if your node reboots all utxo's will be unlocked by default!")
                
            } else {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    self.loadUnlockedUtxos()
                    showAlert(vc: self, title: "", message: "Utxo was not locked.")
                }
            }
        }
    }
    
    private func updateInputs() {
        inputArray.removeAll()
        amountTotal = 0.0
        
        for utxo in selectedUTXOs {
            amountTotal += utxo.amount ?? 0.0
            let input:[String:Any] = ["txid": utxo.txid, "vout": utxo.vout, "sequence": 1]
            inputArray.append(input)
        }
    }
    
    private func finishedLoading() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.updateSelectedUtxos()
            self.tableView.isUserInteractionEnabled = true
            self.tableView.reloadData()
            self.tableView.setContentOffset(.zero, animated: true)
            self.removeSpinner()
        }
    }
    
    func addNavBarSpinner() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.spinner.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
            self.dataRefresher = UIBarButtonItem(customView: self.spinner)
            self.navigationItem.setRightBarButton(self.dataRefresher, animated: true)
            self.spinner.startAnimating()
            self.spinner.alpha = 1
        }
    }
    
    @objc private func loadUnlockedUtxos() {
        unlockedUtxos.removeAll()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            tableView.isUserInteractionEnabled = false
            addNavBarSpinner()
        }
        
        getUtxosFromBtcRpc()
    }
        
    private func getUtxosFromBtcRpc() {
        guard let wallet = wallet else { return }
        
        CoreDataService.retrieveEntity(entityName: .utxos) { [weak self] cachedUtxos in
            guard let self = self else { return }
            
            guard let cachedUtxos = cachedUtxos, cachedUtxos.count > 0 else { return }
                        
            for (i, cachedUtxo) in cachedUtxos.enumerated() {
                let cachedUtxoStr = UtxoResponse(cachedUtxo)
                if cachedUtxoStr.walletId == wallet.id {
                    let utxoStr = Utxo(cachedUtxoStr.dict)
                    updateUtxoArray(utxo: utxoStr)
                }
                if i + 1 == cachedUtxos.count {
                    self.unlockedUtxos = self.unlockedUtxos.sorted {
                        $0.confs ?? 0 < $1.confs ?? 1
                    }
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        
                        self.updateSelectedUtxos()
                        self.tableView.isUserInteractionEnabled = true
                        self.tableView.reloadData()
                        self.tableView.setContentOffset(.zero, animated: true)
                    }
                }
            }
        }
        
        let param:List_Unspent = .init(["minconf":0])
        OnchainUtils.listUnspent(param: param) { [weak self] (utxos, message) in
            guard let self = self else { return }
                        
            guard let utxos = utxos else {
                self.finishedLoading()
                showAlert(vc: self, title: "Error", message: message ?? "unknown error fecthing your utxos")
                return
            }
            
            unlockedUtxos.removeAll()
            
            guard utxos.count > 0 else {
                self.finishedLoading()
                showAlert(vc: self, title: "No UTXO's", message: "")
                return
            }
                        
            for (i, utxo) in utxos.enumerated() {
                updateUtxoArray(utxo: utxo)
                
                if i + 1 == utxos.count {
                    self.unlockedUtxos = self.unlockedUtxos.sorted {
                        $0.confs ?? 0 < $1.confs ?? 1
                    }
                    self.finishedLoading()
                }
            }
        }
    }
    
    private func updateUtxoArray(utxo: Utxo) {
        var utxoDict = utxo.dict
        
        let amountBtc = utxo.amount!
        utxoDict["amountSats"] = amountBtc.sats
        if let fxrate = fxRate {
            utxoDict["amountFiat"] = (fxrate * amountBtc).fiatString
        }
        
        unlockedUtxos.append(Utxo(utxoDict))
    }
    
    private func removeSpinner() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.refresher.endRefreshing()
            self.spinner.stopAnimating()
            self.spinner.alpha = 0
            self.refreshButton = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(self.loadUnlockedUtxos))
            self.navigationItem.setRightBarButton(self.refreshButton, animated: true)
        }
    }
        
    private func depositNow(_ utxo: Utxo) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            for (i, unlockedUtxo) in self.unlockedUtxos.enumerated() {
                if unlockedUtxo.id == utxo.id && unlockedUtxo.txid == utxo.txid && unlockedUtxo.vout == utxo.vout {
                    self.unlockedUtxos[i].isSelected = true
                    self.updateSelectedUtxos()
                    self.updateInputs()
                }
                
                if i + 1 == self.unlockedUtxos.count {
                    self.performSegue(withIdentifier: "segueToSendFromUtxos", sender: self)
                }
            }
        }
    }
        
    private func promptToDonateChange(_ utxo: Utxo) {
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                let tit = "Donate toxic change?"
                let mess = "Toxic change is best used as a donation to the developer."
                
                let alert = UIAlertController(title: tit, message: mess, preferredStyle: .actionSheet)
                
                alert.addAction(UIAlertAction(title: "Donate", style: .default, handler: { [weak self] action in
                    guard let self = self else { return }
                    
                    guard let donationAddress = Keys.donationAddress() else {
                        return
                    }
                    
                    self.depositAddress = donationAddress
                    self.depositNow(utxo)
                }))
                
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { action in }))
                alert.popoverPresentationController?.sourceView = self.view
                self.present(alert, animated: true, completion: nil)
            }
    }
                
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        switch segue.identifier {
            
        case "goToLocked":
            guard let vc = segue.destination as? LockedViewController else { fallthrough }
            
            vc.fxRate = fxRate
            vc.isFiat = isFiat
            vc.isBtc = isBtc
            vc.isSats = isSats
            
        case "segueToSendFromUtxos":
            guard let vc = segue.destination as? CreateRawTxViewController else { fallthrough }
            
            vc.inputs = inputArray
            vc.utxoTotal = amountTotal
            vc.address = depositAddress ?? ""
            
        case "segueToBroadcasterFromUtxo":
            guard let vc = segue.destination as? VerifyTransactionViewController, let psbt = psbt else { fallthrough }
            
            vc.unsignedPsbt = psbt
            
        default:
            break
        }
    }
}


// MARK: UTXOCellDelegate

extension UTXOViewController: UTXOCellDelegate {
    func didTapToLock(_ utxo: Utxo) {
        lock(utxo)
    }
}

// Mark: UITableViewDataSource

extension UTXOViewController: UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: UTXOCell.identifier, for: indexPath) as! UTXOCell
        let utxo = unlockedUtxos[indexPath.section]
        cell.configure(utxo: utxo, isLocked: false, fxRate: fxRate, isSats: isSats, isBtc: isBtc, isFiat: isFiat, delegate: self)
        return cell
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return unlockedUtxos.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }
    
}


// MarK: UITableViewDelegate

extension UTXOViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 5 // Spacing between cells
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = UIView()
        headerView.backgroundColor = .clear
        return headerView
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let cell = tableView.cellForRow(at: indexPath) as! UTXOCell
        let isSelected = unlockedUtxos[indexPath.section].isSelected
        
        if isSelected {
            cell.deselectedAnimation()
        } else {
            cell.selectedAnimation()
        }
        
        unlockedUtxos[indexPath.section].isSelected = !isSelected
        
        updateSelectedUtxos()
        updateInputs()
        
        tableView.deselectRow(at: indexPath, animated: false)
    }
    
}
