//
//  MainMenuViewController.swift
//  BitSense
//
//  Created by Peter on 08/09/18.
//  Copyright © 2018 Fontaine. All rights reserved.
//

import UIKit

class MainMenuViewController: UIViewController {
    
    weak var mgr = TorClient.sharedInstance
    let backView = UIView()
    let ud = UserDefaults.standard
    var command = ""
    @IBOutlet var mainMenu: UITableView!
    var connectingView = ConnectingView()
    var nodes = [[String:Any]]()
    var activeNode:NodeStruct?
    var existingNodeID:UUID!
    var initialLoad = false
    let spinner = UIActivityIndicatorView(style: .medium)
    var refreshButton = UIBarButtonItem()
    var dataRefresher = UIBarButtonItem()
    var isUnlocked = false
    var nodeLabel = ""
    var detailImage = UIImage()
    var detailImageTint = UIColor()
    let refreshControl = UIRefreshControl()
    
    var detailHeaderText = ""
    var detailSubheaderText = ""
    var detailTextDescription = ""
    var host = ""
    
    var blockchainInfo:BlockchainInfo!
    var peerInfo:PeerInfo!
    var networkInfo:NetworkInfo!
    var miningInfo:MiningInfo!
    var mempoolInfo:MempoolInfo!
    var uptimeInfo:Uptime!
    var feeInfo:FeeInfo!
            
    @IBOutlet weak var headerLabel: UILabel!
    @IBOutlet weak var torProgressLabel: UILabel!
    @IBOutlet weak var progressView: UIProgressView!
    
    private enum Section: Int {
        case blockchainInfo
        case networkInfo
        case peerInfo
        case miningInfo
        case upTime
        case mempoolInfo
        case feeInfo
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        UserDefaults.standard.set(UIDevice.modelName, forKey: "modelName")
        UIApplication.shared.isIdleTimerDisabled = true
        
        setIcon()
        
        refreshControl.attributedTitle = NSAttributedString(string: "")
        refreshControl.addTarget(self, action: #selector(refreshNode), for: .valueChanged)
        mainMenu.addSubview(refreshControl)
        
        if !Crypto.setupinit() {
            showAlert(vc: self, title: "", message: "There was an error setupinit.")
        }
        mainMenu.delegate = self
        mainMenu.alpha = 0
        mainMenu.tableFooterView = UIView(frame: .zero)
        initialLoad = true
        addNavBarSpinner()
        addlaunchScreen()
        showUnlockScreen()
        setFeeTarget()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshNode), name: .refreshNode, object: nil)
        torProgressLabel.text = "Tor bootstrapping 0%"
    }
    
    private func setIcon() {
        let appIcon = UIButton(type: .custom)
        appIcon.setImage(UIImage(named: "1024_fully noded logo.png"), for: .normal)
        appIcon.frame = CGRect(x: 0, y: 0, width: 35, height: 35)
        appIcon.imageView?.contentMode = .scaleAspectFit
        appIcon.translatesAutoresizingMaskIntoConstraints = false
        appIcon.widthAnchor.constraint(equalToConstant: 35).isActive = true
        appIcon.heightAnchor.constraint(equalToConstant: 35).isActive = true
        let leftBarButton = UIBarButtonItem(customView: appIcon)
        navigationItem.leftBarButtonItem = leftBarButton
    }
        
    override func viewDidAppear(_ animated: Bool) {
        if initialLoad {
            if !firstTimeHere() {
                showAlert(vc: self, title: "", message: "There was a critical error setting your devices encryption key, please delete and reinstall the app")
            } else {
                if mgr?.state != .started && mgr?.state != .connected  {
                    if KeyChain.getData("UnlockPassword") == nil {
                        startLoading()
                    }
                }
            }
        } else {
            if self.activeNode == nil {
                MakeRPCCall.sharedInstance.getActiveNode { [weak self] node in
                    guard let self = self else { return }
                    guard let node = node else { return }
                    
                    addNavBarSpinner()
                    activeNode = node
                    loadNode(node: node)
                }
            }
        }
    }
    
    private func startLoading() {
        mgr?.start(delegate: self)
        addNavBarSpinner()
        removeBackView()
        
        MakeRPCCall.sharedInstance.getActiveNode { [weak self] node in
            guard let self = self else { return }
            guard let node = node else {
                alertToAddNode()
                return
            }
            
            activeNode = node
                                        
            if let address = node.onionAddress {
                guard let decryptedAddress = Crypto.decrypt(address), let addressText = decryptedAddress.utf8String else { return }
                
                if addressText.hasPrefix("127.0.0.1:") || addressText.hasPrefix("localhost:") {
                    self.loadNode(node: node)
                }
            }
        }
    }
    
    private func alertToAddNode() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            headerLabel.text = ""
            
            let tit = "Fully Noded only works when you connect your node to it."
            
            let mess = "You can do this manually or by scanning QR codes provided in most of the popular node packages: Umbrel, Start9, NODL, etc..."
            
            let alert = UIAlertController(title: tit, message: mess, preferredStyle: .alert)
            
            alert.addAction(UIAlertAction(title: "Connect my node", style: .default, handler: { action in
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    self.performSegue(withIdentifier: "segueToAddNode", sender: self)
                }
            }))
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { action in }))
            self.present(alert, animated: true, completion: nil)
        }
    }
    
        
    @IBAction func lockAction(_ sender: Any) {
        if KeyChain.getData("UnlockPassword") != nil {
            showUnlockScreen()
        } else {
            DispatchQueue.main.async {[weak self] in
                guard let self = self else { return }
                
                self.performSegue(withIdentifier: "segueToCreateUnlockPassword", sender: self)
            }
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
    
    @objc func refreshNode() {
        if let node = activeNode {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                refreshTable()
                existingNodeID = nil
                addNavBarSpinner()
                refreshControl.endRefreshing()
                loadNode(node: node)
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                refreshControl.endRefreshing()
            }
        }
    }
    
    private func loadNode(node: NodeStruct) {
        if initialLoad {
            existingNodeID = node.id
            loadTableData()
        } else {
            checkIfNodesChanged(newNodeId: node.id!)
        }
        DispatchQueue.main.async { [weak self] in
            self?.headerLabel.text = node.label
        }
    }
    
    private func checkIfNodesChanged(newNodeId: UUID) {
        if newNodeId != existingNodeID {
            loadTableData()
        }
    }
    
    private func refreshTable() {
        existingNodeID = nil
        blockchainInfo = nil
        mempoolInfo = nil
        uptimeInfo = nil
        peerInfo = nil
        feeInfo = nil
        networkInfo = nil
        miningInfo = nil
        reloadTable()
    }
    
    @objc func refreshData(_ sender: Any) {
        refreshTable()
        refreshDataNow()
    }
    
    func refreshDataNow() {
        addNavBarSpinner()
        MakeRPCCall.sharedInstance.getActiveNode { [weak self] node in
            guard let self = self else { return }
            guard let node = node else {
                removeLoader()
                alertToAddNode()
                return
            }
            self.activeNode = node
            self.loadNode(node: node)
        }
    }
    
    func showUnlockScreen() {
        if KeyChain.getData("UnlockPassword") != nil {
            DispatchQueue.main.async { [weak self] in
                self?.performSegue(withIdentifier: "lockScreen", sender: self)
            }
        }
    }
    
    //MARK: Tableview Methods
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 7
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        /*
         private enum Section: Int {
             case blockchainInfo
             case networkInfo
             case peerInfo
             case miningInfo
             case upTime
             case mempoolInfo
             case feeInfo
         }
         */
        
        switch section {
        case 0:
            if blockchainInfo != nil {
                return 6
            } else {
                return 0
            }
        case 1:
            if networkInfo != nil {
                return 2
            } else {
                return 0
            }
        case 2:
            if peerInfo != nil {
                return 1
            } else {
                return 0
            }
        case 3:
            if miningInfo != nil {
                return 1
            } else {
                return 0
            }
        case 4:
            if uptimeInfo != nil {
                return 1
            } else {
                return 0
            }
        case 5:
            if mempoolInfo != nil {
                return 1
            } else {
                return 0
            }
        case 6:
            if feeInfo != nil {
                return 1
            } else {
                return 0
            }
        default:
            return 0
        }
    }
    
    func blankCell() -> UITableViewCell {
        let cell = UITableViewCell()
        cell.selectionStyle = .none
        cell.backgroundColor = .none
        return cell
    }
    
    private func homeCell(_ indexPath: IndexPath) -> UITableViewCell {
        let cell = mainMenu.dequeueReusableCell(withIdentifier: "homeCell", for: indexPath)
        cell.selectionStyle = .none
//        cell.layer.borderColor = UIColor.lightGray.cgColor
//        cell.layer.borderWidth = 0.5
        //cell.backgroundColor = #colorLiteral(red: 0.05172085258, green: 0.05855310153, blue: 0.06978280196, alpha: 1)
        //let background = cell.viewWithTag(3)!
        let icon = cell.viewWithTag(1) as! UIImageView
        let label = cell.viewWithTag(2) as! UILabel
        //let chevron = cell.viewWithTag(4) as! UIImageView
//        background.clipsToBounds = true
//        background.layer.cornerRadius = 8
        //background.tintColor = .clear
        icon.tintColor = .none
        
        switch Section(rawValue: indexPath.section) {
            
        case .blockchainInfo:
            if blockchainInfo != nil {
                switch indexPath.row {
                case 0:
                    if blockchainInfo.progressString == "Fully verified" {
                        //background.backgroundColor = .systemGreen
                        icon.image = UIImage(systemName: "checkmark.seal")
                    } else {
                        //background.backgroundColor = .systemRed
                        icon.image = UIImage(systemName: "exclamationmark.triangle")
                        icon.tintColor = .systemRed
                    }
                    label.text = blockchainInfo.progressString
                    //chevron.alpha = 1
                    
                case 1:
                    label.text = blockchainInfo.network.capitalized + " blockchain"
                    icon.image = UIImage(systemName: "bitcoinsign.circle")
                    
                case 2:
                    if blockchainInfo.pruned {
                        label.text = "Pruned node"
                        icon.image = UIImage(systemName: "rectangle.compress.vertical")
                        
                    } else if !blockchainInfo.pruned {
                        label.text = "Full node"
                        icon.image = UIImage(systemName: "rectangle.expand.vertical")
                    }
                    //background.backgroundColor = .systemPurple
                    //chevron.alpha = 1
                    
                case 3:
                    label.text = "Blockheight \(blockchainInfo.blockheight.withCommas)"
                    icon.image = UIImage(systemName: "square.stack.3d.up")
                    //background.backgroundColor = .systemYellow
                    //chevron.alpha = 0
                    
                case 4:
                    label.text = "Blockchain size \(blockchainInfo.size)"
                    //background.backgroundColor = .systemPink
                    icon.image = UIImage(systemName: "archivebox")
                    //chevron.alpha = 0
                    
                case 5:
                    label.text = "\(blockchainInfo.diffString)"
                    icon.image = UIImage(systemName: "slider.horizontal.3")
                    //background.backgroundColor = .systemBlue
                    //chevron.alpha = 0
                    
                default:
                    break
                }
            }
            
        case .networkInfo:
            if networkInfo != nil {
                switch indexPath.row {
                case 0:
                    label.text = "Bitcoin Core v\(networkInfo.version)"
                    icon.image = UIImage(systemName: "v.circle")
                    //background.backgroundColor = .systemBlue
                    //chevron.alpha = 1
                    
                case 1:
                    if networkInfo.torReachable {
                        label.text = "Tor hidden service on"
                        icon.image = UIImage(systemName: "wifi")
                        //background.backgroundColor = .black
                        
                    } else {
                        label.text = "Tor hidden service off"
                        icon.image = UIImage(systemName: "wifi.slash")
                        //background.backgroundColor = .darkGray
                    }
                    //chevron.alpha = 0
                    
                default:
                    break
                }
            }
        
        case .peerInfo:
            if peerInfo != nil {
                label.text = "Peers \(peerInfo.outgoingCount) outgoing / \(peerInfo.incomingCount) incoming"
                icon.image = UIImage(systemName: "person.3")
            }
            
        case .miningInfo:
            if miningInfo != nil {
                label.text = miningInfo.hashrate + " " + "EH/s mining hashrate"
                icon.image = UIImage(systemName: "speedometer")
            }
        
        case .upTime:
            if uptimeInfo != nil {
                label.text = "\(uptimeInfo.uptime / 86400) days \((uptimeInfo.uptime % 86400) / 3600) hours of uptime"
                icon.image = UIImage(systemName: "clock")
                //background.backgroundColor = .systemGreen
                //chevron.alpha = 0
            }
            
        case .mempoolInfo:
            if mempoolInfo != nil {
                label.text = "\(mempoolInfo.mempoolCount.withCommas) transactions in mempool"
                icon.image = UIImage(systemName: "waveform.path.ecg")
                //background.backgroundColor = .systemGreen
                //chevron.alpha = 0
            }
            
        case .feeInfo:
            if feeInfo != nil {
                label.text = feeInfo.feeRate + " " + "fee rate setting"
                icon.image = UIImage(systemName: "percent")
                //background.backgroundColor = .systemGray
                //chevron.alpha = 0
            }
            
        default:
            break
        }
        return cell
    }
    
    private func segueToShowDetail() {
        DispatchQueue.main.async { [weak self] in
            self?.performSegue(withIdentifier: "showDetailSegue", sender: self)
        }
    }
    
    
    func loadTableData() {
        OnchainUtils.getBlockchainInfo { [weak self] (blockchainInfo, message) in
            guard let self = self else { return }
            
            guard let blockchainInfo = blockchainInfo else {
                
                guard let message = message else {
                    showAlert(vc: self, title: "", message: "unknown error")
                    return
                }
                
                if message.contains("Loading block index") || message.contains("Verifying") || message.contains("Rewinding") || message.contains("Rescanning") {
                    showAlert(vc: self, title: "", message: "Your node is still getting warmed up! Wait 15 seconds and tap the refresh button to try again")
                    
                } else if message.contains("Could not connect to the server.") {
                    showAlert(vc: self, title: "", message: "Looks like your node is not on, make sure it is running and try again.")
                    
                } else if message.contains("unknown error") {
                    showAlert(vc: self, title: "", message: "We got a strange response from your node, first of all make 100% sure your credentials are correct, if they are then your node could be overloaded... Either wait a few minutes and try again or reboot Tor on your node, if that fails reboot your node too, force quit Fully Noded and open it again.")
                    
                } else if message.contains("timed out") || message.contains("The Internet connection appears to be offline") {
                    showAlert(vc: self, title: "", message: "Hmmm we are not getting a response from your node, you can try rebooting Tor on your node and force quitting Fully Noded and reopening it, that generally fixes the issue.")
                    
                } else if message.contains("Unable to decode the response") {
                    showAlert(vc: self, title: "", message: "There was an issue... This can mean your node is busy doing an intense task like rescanning or syncing whoich may be preventing it from responding to commands. If that is the case then just wait a few minutes and try again. As a last resort try rebooting your node and Fully Noded.")
                } else {
                    showAlert(vc: self, title: "Connection issue...", message: message)
                }
                
                removeLoader()
                
                return
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                impact()
                initialLoad = false
                headerLabel.textColor = .none
                self.blockchainInfo = blockchainInfo
                mainMenu.reloadSections(IndexSet(arrayLiteral: Section.blockchainInfo.rawValue), with: .fade)
                getNetworkInfo()
            }
        }
    }
    
    private func getPeerInfo() {
        NodeLogic.getPeerInfo { [weak self] (response, errorMessage) in
            guard let self = self else { return }
            
            guard let response = response else {
                self.removeLoader()
                showAlert(vc: self, title: "", message: errorMessage ?? "unknown error")
                return
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                impact()
                peerInfo = PeerInfo(dictionary: response)
                mainMenu.reloadSections(IndexSet(arrayLiteral: Section.peerInfo.rawValue), with: .fade)
                getMiningInfo()
            }
        }
    }
    
    private func getNetworkInfo() {
        NodeLogic.getNetworkInfo { [weak self] (response, errorMessage) in
            guard let self = self else { return }
            
            guard let response = response else {
                self.removeLoader()
                showAlert(vc: self, title: "", message: errorMessage!)
                return
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                impact()
                networkInfo = NetworkInfo(dictionary: response)
                mainMenu.reloadSections(IndexSet(arrayLiteral: Section.networkInfo.rawValue), with: .fade)
                getPeerInfo()
            }
        }
    }
    
    private func getMiningInfo() {
        NodeLogic.getMiningInfo { [weak self] (response, errorMessage) in
            guard let self = self else { return }
            
            guard let response = response else {
                self.removeLoader()
                showAlert(vc: self, title: "", message: errorMessage ?? "unknown error")
                return
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                impact()
                self.miningInfo = MiningInfo(dictionary: response)
                self.mainMenu.reloadSections(IndexSet(arrayLiteral: Section.miningInfo.rawValue), with: .fade)
                self.getUptime()
            }
        }
    }
    
    private func getUptime() {
        NodeLogic.getUptime { [weak self] (response, errorMessage) in
            guard let self = self else { return }
            
            guard let response = response else {
                self.removeLoader()
                showAlert(vc: self, title: "", message: errorMessage ?? "unknown error")
                return
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                impact()
                self.uptimeInfo = Uptime(dictionary: response)
                self.mainMenu.reloadSections(IndexSet(arrayLiteral: Section.upTime.rawValue), with: .fade)
                self.getMempoolInfo()
            }
        }
    }
    
    private func getMempoolInfo() {
        NodeLogic.getMempoolInfo { [weak self] (response, errorMessage) in
            guard let self = self else { return }
            
            guard let response = response else {
                self.removeLoader()
                showAlert(vc: self, title: "", message: errorMessage ?? "unknown error")
                return
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                impact()
                self.mempoolInfo = MempoolInfo(dictionary: response)
                self.mainMenu.reloadSections(IndexSet(arrayLiteral: Section.mempoolInfo.rawValue), with: .fade)
                self.getFeeInfo()
            }
        }
    }
    
    private func getFeeInfo() {
        NodeLogic.estimateSmartFee { [weak self] (response, errorMessage) in
            guard let self = self else { return }
            
            guard let response = response else {
                self.removeLoader()
                showAlert(vc: self, title: "", message: errorMessage ?? "unknown error")
                return
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                impact()
                self.feeInfo = FeeInfo(dictionary: response)
                self.mainMenu.reloadSections(IndexSet(arrayLiteral: Section.feeInfo.rawValue), with: .fade)
                self.removeLoader()
            }
        }
    }
    
    //MARK: User Interface
    
    func addlaunchScreen() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.backView.frame = self.view.frame
            self.backView.backgroundColor = .none
            let imageView = UIImageView()
            imageView.frame = CGRect(x: self.view.center.x - 75, y: self.view.center.y - 75, width: 150, height: 150)
            imageView.image = UIImage(named: "logo_grey.png")
            self.backView.addSubview(imageView)
            self.view.addSubview(self.backView)
        }
    }
    
    func removeLoader() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.spinner.stopAnimating()
            self.spinner.alpha = 0
            self.refreshButton = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(self.refreshData(_:)))
            //self.refreshButton.tintColor = UIColor.lightGray.withAlphaComponent(1)
            self.navigationItem.setRightBarButton(self.refreshButton, animated: true)
        }
    }
    
    func removeBackView() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            UIView.animate(withDuration: 0.3, animations: { [weak self] in
                guard let self = self else { return }
                
                self.backView.alpha = 0
                self.mainMenu.alpha = 1
            }) { (_) in
                self.backView.removeFromSuperview()
            }
        }
    }
    
    func reloadTable() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.mainMenu.reloadData()
        }
    }
    
    private func setFeeTarget() {
        if ud.object(forKey: "feeTarget") == nil {
            ud.set(432, forKey: "feeTarget")
        }
    }
    
    private func timeStamp() {
        if KeyChain.getData(timestampData) == nil {
            if let currentDate = Data(base64Encoded: currentDate()) {
                let _ = KeyChain.set(currentDate, forKey: timestampData)
            }
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        switch segue.identifier {
        case "lockScreen":
            guard let vc = segue.destination as? LogInViewController else { fallthrough }
            
            vc.onDoneBlock = { [weak self] in
                guard let self = self else { return }
                
                isUnlocked = true
                
                if mgr?.state != .started && mgr?.state != .connected  {
                    startLoading()
                }
            }
            
        default:
            break
        }
    }
    
    //MARK: Helpers
    
    func firstTimeHere() -> Bool {
        return FirstTime.firstTimeHere()
    }
    
    private func hideTorProgress(hide: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.torProgressLabel.isHidden = hide
            self?.progressView.isHidden = hide
        }
    }
}

// MARK: Helpers

extension MainMenuViewController {
    
    private func headerName(for section: Section) -> String {
        
        switch section {
        case .blockchainInfo:
            return "Blockchain info"
        case .networkInfo:
            return "Network info"
        case .peerInfo:
            return "Peer info"
        case .miningInfo:
            return "Mining info"
        case .upTime:
            return "Up time"
        case .mempoolInfo:
            return "Mempool info"
        case .feeInfo:
            return "Fee info"
        }
    }
}

extension MainMenuViewController: OnionManagerDelegate {
    
    func torConnProgress(_ progress: Int) {
        DispatchQueue.main.async { [weak self] in
            self?.torProgressLabel.text = "Tor bootstrapping \(progress)%"
            self?.progressView.setProgress(Float(Double(progress) / 100.0), animated: true)
        }
    }
    
    func torConnFinished() {
        if let address = activeNode?.onionAddress {
            guard let decryptedAddress = Crypto.decrypt(address), let addressText = decryptedAddress.utf8String else {
                return
            }
            if addressText.contains(".onion:") {
                self.loadNode(node: activeNode!)
            }
        } else {
            removeLoader()
        }
        DispatchQueue.main.async { [weak self] in
            self?.hideTorProgress(hide: true)
        }
        timeStamp()
    }
    
    func torConnDifficulties() {
        showAlert(vc: self, title: "", message: "We are having issues connecting tor.")
        DispatchQueue.main.async { [weak self] in
            self?.hideTorProgress(hide: true)
            self?.removeBackView()
        }
    }
}

extension MainMenuViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .blockchainInfo:
            if blockchainInfo == nil {
                return blankCell()
            } else {
                return homeCell(indexPath)
            }
            
        case .networkInfo:
            if networkInfo == nil {
                return blankCell()
            } else {
                return homeCell(indexPath)
            }
            
        case .peerInfo:
            if peerInfo == nil {
                return blankCell()
            } else {
                return homeCell(indexPath)
            }
            
        case .miningInfo:
            if miningInfo == nil {
                return blankCell()
            } else {
                return homeCell(indexPath)
            }
            
        case .upTime:
            if uptimeInfo == nil {
                return blankCell()
            } else {
                return homeCell(indexPath)
            }
            
        case .mempoolInfo:
            if mempoolInfo == nil {
                return blankCell()
            } else {
                return homeCell(indexPath)
            }
            
        case .feeInfo:
            if feeInfo == nil {
                return blankCell()
            } else {
                return homeCell(indexPath)
            }
            
        default:
            return blankCell()
        }
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let header = UIView()
        header.backgroundColor = UIColor.clear
        header.frame = CGRect(x: 0, y: 0, width: view.frame.size.width - 32, height: 20)
        
        let textLabel = UILabel()
        textLabel.textAlignment = .left
        textLabel.font = UIFont.systemFont(ofSize: 17, weight: .regular)
        textLabel.textColor = .secondaryLabel
        
        switch section {
        case 0:
            textLabel.frame = CGRect(x: 0, y: 16, width: 300, height: 20)
        default:
            textLabel.frame = CGRect(x: 0, y: 0, width: 300, height: 20)
        }
        
        if let section = Section(rawValue: section) {
            textLabel.text = headerName(for: section)
        }
        
        header.addSubview(textLabel)
        return header
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        switch section {
        case 0:
            return 40
        default:
            return 25
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 54
    }
    
}

extension MainMenuViewController: UITableViewDataSource {}

extension MainMenuViewController: UINavigationControllerDelegate {}

