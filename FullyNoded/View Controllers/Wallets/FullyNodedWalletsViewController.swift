//
//  FullyNodedWalletsViewController.swift
//  BitSense
//
//  Created by Peter on 29/06/20.
//  Copyright © 2020 Fontaine. All rights reserved.
//

import UIKit

class FullyNodedWalletsViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    
    @IBOutlet weak var fxRateLabel: UILabel!
    @IBOutlet weak var balanceFiatLabel: UILabel!
    @IBOutlet weak var totalBalanceLabel: UILabel!
    @IBOutlet weak var walletsTable: UITableView!
    
    var wallets = [[String:Any]]()
    var externalWallets = [Wallet]()
    var walletId:UUID!
    var index = 0
    var existingActiveWalletName = ""
    var totalBtcBalance = 0.0
    var fxRate:Double?
    var bitcoinCoreWallets = [String]()
    let spinner = ConnectingView()
    var initialLoad = true
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        walletsTable.delegate = self
        walletsTable.dataSource = self
        totalBalanceLabel.alpha = 0
        totalBalanceLabel.text = ""
        balanceFiatLabel.alpha = 0
        balanceFiatLabel.text = ""
        fxRateLabel.alpha = 0
        fxRateLabel.text = ""
        existingActiveWalletName = UserDefaults.standard.object(forKey: "walletName") as? String ?? ""
        initialLoad = true
    }
    
    override func viewDidAppear(_ animated: Bool) {
        externalWallets.removeAll()
        if initialLoad {
            getBitcoinCoreWallets()
            initialLoad = false
        }
    }
    
    @IBAction func seeExternalWalletsAction(_ sender: Any) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.performSegue(withIdentifier: "segueToShowAllWallets", sender: self)
        }
    }
    
    private func getBitcoinCoreWallets() {
        spinner.addConnectingView(vc: self, description: "getting total balance...")
        bitcoinCoreWallets.removeAll()
        OnchainUtils.listWalletDir { [weak self] (walletDir, message) in
            guard let self = self else { return }
            
            guard let walletDir = walletDir else {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    self.spinner.removeConnectingView()
                    self.initialLoad = false
                    showAlert(vc: self, title: "", message: "error getting wallets: \(message ?? "")")
                }
                return
            }
            
            self.parseWallets(wallets: walletDir.wallets)
        }
    }
    
    private func parseWallets(wallets: [String]) {
        guard !wallets.isEmpty else { self.spinner.removeConnectingView(); return }
        
        for (i, walletName) in wallets.enumerated() {
            bitcoinCoreWallets.append(walletName)
            
            if i + 1 == wallets.count {
                getFullyNodedWallets()
            }
        }
    }
    
    private func getFullyNodedWallets() {
        wallets.removeAll()
        index = 0
        totalBtcBalance = 0.0
        CoreDataService.retrieveEntity(entityName: .wallets) { [weak self] ws in
            guard let self = self else { return }
            
            guard let ws = ws, ws.count > 0 else {
                self.spinner.removeConnectingView()
                let title = "No Fully Noded Wallets"
                let message = "Looks like you have not yet created any Fully Noded wallets, on the active wallet tab you can tap the plus sign (top left) to create a Fully Noded wallet."
                self.initialLoad = false
                showAlert(vc: self, title: title, message: message)
                
                return
            }
            
            for (i, wallet) in ws.enumerated() {
                if wallet["id"] != nil {
                    let walletStruct = Wallet(dictionary: wallet)
                    var isInternal = false
                    for (b, bitcoinCoreWallet) in self.bitcoinCoreWallets.enumerated() {
                        if bitcoinCoreWallet == walletStruct.name {
                            isInternal = true
                            self.wallets.append(wallet)
                        }

                        if b + 1 == self.bitcoinCoreWallets.count && !isInternal {
                            self.externalWallets.append(walletStruct)
                        }
                    }

                    if i + 1 == ws.count {
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }

                            self.loadTotalBalance()
                        }
                    }
                } else {
                    if i + 1 == ws.count {
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }

                            self.loadTotalBalance()
                        }
                    }
                }
            }
        }
    }
    
    private func loadTotalBalance() {
        guard wallets.count > 0 else { spinner.removeConnectingView(); return }
        
        spinner.label.text = "getting total balance..."
        
        guard let fxRate = fxRate else {
            FiatConverter.sharedInstance.getFxRate { [weak self] fxRate in
                guard let self = self else { return }

                guard let fxRate = fxRate else { spinner.removeConnectingView();  getTotals(); return }
                guard self.wallets.count > 0 else { spinner.removeConnectingView(); return }
                self.fxRate = fxRate
                self.getTotals()
            }
            return
        }
        
        self.getTotals()
    }
    
    private func getTotals() {
        if index < wallets.count {
            let wallet = wallets[index]
            let walletStruct = Wallet(dictionary: wallet)
            UserDefaults.standard.set(walletStruct.name, forKey: "walletName")
            
            OnchainUtils.getBalance { [weak self] (balance, message) in
                guard let self = self else { return }
                
                guard let balance = balance else {
                    self.spinner.removeConnectingView()
                    
                    guard let message = message else {
                        showAlert(vc: self, title: "", message: "There was an unknown error getting your balances.")
                        UserDefaults.standard.set(self.existingActiveWalletName, forKey: "walletName")
                        self.initialLoad = false
                        return
                    }
                    if !message.contains("is already loaded") {
                        showAlert(vc: self, title: "", message: "There was an error getting your balances: \(message).")
                    }
                    UserDefaults.standard.set(self.existingActiveWalletName, forKey: "walletName")
                    self.initialLoad = false
                    return
                }
                
                self.wallets[self.index]["balance"] = balance
                self.index += 1
                self.totalBtcBalance += balance
                self.getTotals()
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                UserDefaults.standard.set(self.existingActiveWalletName, forKey: "walletName")
                
                self.totalBalanceLabel.text = "\(self.totalBtcBalance.avoidNotation) btc"
                self.totalBalanceLabel.alpha = 1
                self.initialLoad = false
                self.walletsTable.reloadData()
                self.spinner.removeConnectingView()
                
                if let fxRate = fxRate {
                    let roundedFiat = totalBtcBalance * fxRate
                    self.fxRateLabel.text = fxRate.exchangeRate
                    self.fxRateLabel.alpha = 1
                    self.balanceFiatLabel.alpha = 1
                    self.balanceFiatLabel.text = roundedFiat.fiatString
                }
            }
        }
    }
    
    @IBAction func showHelp(_ sender: Any) {
        let message = "These are the wallets you created via \"Create a Fully Noded Wallet\". They are special wallets which utilize your node in a smarter way than manual Bitcoin Core wallet creation. You will only see \"Fully Noded Wallets\" here. You can activate/deactivate them, rename them, and delete them here by tapping the > button. In the detail view you have more powerful options related to your wallet, to read about it tap the > button to see the detail view and tap the help button there."
        showAlert(vc: self, title: "Fully Noded Wallets", message: message)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 65
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return wallets.count
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "fnWalletCell", for: indexPath)
        cell.selectionStyle = .none
//        cell.layer.borderColor = UIColor.lightGray.cgColor
//        cell.layer.borderWidth = 0.5
        cell.sizeToFit()
        let label = cell.viewWithTag(1) as! UILabel
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.sizeToFit()
        let button = cell.viewWithTag(2) as! UIButton
        let wallet = wallets[indexPath.row]
        let btcBalance = (wallet["balance"] as? Double ?? 0.0)
        let walletStruct = Wallet(dictionary: wallet)
        label.text = walletStruct.label + "\n\(btcBalance.btc)"
        if let fxRate = fxRate {
            label.text! += " | \((btcBalance * fxRate).balanceTextWithSymbol) "
        }
        button.restorationIdentifier = "\(indexPath.row)"
        button.addTarget(self, action: #selector(goToDetail(_:)), for: .touchUpInside)
        if self.existingActiveWalletName == walletStruct.name {
            cell.accessoryType = .checkmark
            cell.isSelected = true
        } else {
            cell.accessoryType = .none
            cell.isSelected = false
        }
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let wallet = Wallet(dictionary: wallets[indexPath.row])
        UserDefaults.standard.set(wallet.name, forKey: "walletName")
        existingActiveWalletName = wallet.name
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            walletsTable.reloadData()
            NotificationCenter.default.post(name: .refreshWallet, object: nil, userInfo: nil)
        }
    }
    
    @objc func goToDetail(_ sender: UIButton) {
        if sender.restorationIdentifier != nil {
            if let row = Int(sender.restorationIdentifier!) {
                walletId = Wallet(dictionary: wallets[row]).id
                goToDetail()
            }
        }
    }
    
    private func goToDetail() {
        DispatchQueue.main.async { [unowned vc = self] in
            vc.performSegue(withIdentifier: "showWalletDetail", sender: vc)
        }
    }
    
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
        
        switch segue.identifier {
        case "segueToShowAllWallets":
            guard let vc = segue.destination as? ExternalFNWalletsViewController else { fallthrough }
            
            vc.externalWallets = externalWallets
        case "showWalletDetail":
            guard let vc = segue.destination as? WalletDetailViewController else { fallthrough }
            
            vc.walletId = walletId
        default:
            break
        }
    }
}
