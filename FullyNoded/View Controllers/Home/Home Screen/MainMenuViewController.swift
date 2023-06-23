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
                    if KeyChain.getData("UnlockPassword") != nil {
                        if isUnlocked {
                            startLoading()
                        }
                    } else {
                        startLoading()
                    }
                }
            }
            initialLoad = false
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
                label.text = "Peer count \(peerInfo.outgoingCount) outgoing / \(peerInfo.incomingCount) incoming"
                icon.image = UIImage(systemName: "person.3")
                //background.backgroundColor = .systemIndigo
                //chevron.alpha = 1
            }
            
        case .miningInfo:
            if miningInfo != nil {
                label.text = miningInfo.hashrate + " " + "EH/s mining hashrate"
                icon.image = UIImage(systemName: "speedometer")
                //background.backgroundColor = .systemRed
                //chevron.alpha = 0
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
            
            
            
            
//        case .verificationProgress:
//            if blockchainInfo != nil {
//
//            }
            
//        case .totalSupply:
//            if uptimeInfo != nil {
//                label.text = "Verify total supply"
//                icon.image = UIImage(systemName: "person.fill.checkmark")
//                //background.backgroundColor = .systemYellow
//                //chevron.alpha = 1
//            }
            
//        case .nodeVersion:
//            if networkInfo != nil {
//
//            }
            
//        case .blockchainNetwork:
//            if blockchainInfo != nil {
//                label.text = blockchainInfo.network.capitalized
//                icon.image = UIImage(systemName: "bitcoinsign.circle")
////                switch blockchainInfo.network {
////                case "test":
////                    //background.backgroundColor = #colorLiteral(red: 0.4399289489, green: 0.9726744294, blue: 0.2046178877, alpha: 1)
////                case "main":
////                    //background.backgroundColor = #colorLiteral(red: 0.9629253745, green: 0.5778557658, blue: 0.1043280438, alpha: 1)
////                case "regtest":
////                    //background.backgroundColor = #colorLiteral(red: 0.2165609896, green: 0.7795373201, blue: 0.9218732715, alpha: 1)
////                case "signet":
////                    //background.backgroundColor = #colorLiteral(red: 0.8719944954, green: 0.9879228473, blue: 0.07238187641, alpha: 1)
////                default:
////                    //background.backgroundColor = .systemTeal
////                }
//                //chevron.alpha = 1
//            }
            
//        case .peerConnections:
//            if peerInfo != nil {
//
//            }
            
//        case .blockchainState:
//            if blockchainInfo != nil {
//                if blockchainInfo.pruned {
//                    label.text = "Pruned"
//                    icon.image = UIImage(systemName: "rectangle.compress.vertical")
//
//                } else if !blockchainInfo.pruned {
//                    label.text = "Not pruned"
//                    icon.image = UIImage(systemName: "rectangle.expand.vertical")
//                }
//                //background.backgroundColor = .systemPurple
//                //chevron.alpha = 1
//            }
            
        //case .miningHashrate:
            
            
//        case .currentBlockHeight:
//            if blockchainInfo != nil {
//
//            }
            
//        case .miningDifficulty:
//            if blockchainInfo != nil {
//
//            }
            
//        case .blockchainSizeOnDisc:
//            if blockchainInfo != nil {
//
//            }
            
        //case .memPool:
            
            
        //case .feeRate:
            
            
//        case .p2pHiddenService:
//            if networkInfo != nil {
//
//            }
            
        //case .nodeUptime:
            
            
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
                
                self.removeLoader()
                
                return
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.headerLabel.textColor = .none
                self.blockchainInfo = blockchainInfo
                self.mainMenu.reloadSections(IndexSet(arrayLiteral: Section.blockchainInfo.rawValue), with: .fade)
                self.getPeerInfo()
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
                
                self.peerInfo = PeerInfo(dictionary: response)
                self.mainMenu.reloadSections(IndexSet(arrayLiteral: Section.peerInfo.rawValue), with: .fade)
                self.getNetworkInfo()
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
                
                self.networkInfo = NetworkInfo(dictionary: response)
                self.mainMenu.reloadSections(IndexSet(arrayLiteral:
                                                        Section.networkInfo.rawValue), with: .fade)
                self.getMiningInfo()
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
        
//        switch section {
//        case .verificationProgress:
//            return "Progress"
//        case .nodeUptime:
//            return "Uptime"
//        case .blockchainNetwork:
//            return "Network"
//        case .nodeVersion:
//            return "Version"
//        case .peerConnections:
//            return "Peers"
//        case .currentBlockHeight:
//            return "Blockheight"
//        case .memPool:
//            return "Mempool"
//        case .p2pHiddenService:
//            return "Hidden service p2p"
//        case .miningHashrate:
//            return "Hashrate"
//        case .miningDifficulty:
//            return "Difficulty"
//        case .blockchainSizeOnDisc:
//            return "Blockchain size on disc"
//        case .feeRate:
//            return "Fee rate"
//        case .blockchainState:
//            return "Blockchain state"
//        case .totalSupply:
//            return "Audit total supply"
//        }
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
            if let node = self?.activeNode {
                self?.loadNode(node: node)
            }
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
    
//    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
//        switch Section(rawValue: indexPath.section) {
//        case .verificationProgress:
//            if blockchainInfo != nil {
//                command = "getblockchaininfo"
//                detailHeaderText = headerName(for: .verificationProgress)
//                if blockchainInfo.progress == "Fully verified" {
//                    detailImageTint = .green
//                    detailImage = UIImage(systemName: "checkmark.seal")!
//                } else {
//                    detailImageTint = .systemRed
//                    detailImage = UIImage(systemName: "exclamationmark.triangle")!
//                }
//                detailSubheaderText = blockchainInfo.progressString
//                detailTextDescription = """
//                Don't trust, verify!
//
//                Simply put the "verification progress" field lets you know what percentage of the blockchain's transactions have been verified by your node. The value your node returns is a decimal number between 0.0 and 1.0. 1 meaning your node has verified 100% of the transactions on the blockchain. As new transactions and blocks are always being added to the blockchain your node is constantly catching up and this field will generally be a number such as "0.99999974646", never quite reaching 1 (although it is possible). Fully Noded checks if this number is greater than 0.99 (e.g. 0.999) and if it is we consider your node's copy of the blockchain to be "Fully Verified".
//
//                Fully Noded makes the bitcoin-cli getblockchaininfo call to your node in order to get the "verification progress" of your node. Your node is always verifying each transaction that is broadcast onto the Bitcoin network. This is the fundamental reason to run your own node. If you use someone elses node you are trusting them to verify your utxo's which defeats the purpose of Bitcoin in the first place. Bitcoin was invented to disintermediate 3rd parties, removing trust from the foundation of our financial system, reintroducing that trust defeats Bitcoin's purpose. This is why it is so important to run your own node.
//
//                During the initial block download your node proccesses each transaction starting from the genesis block, ensuring all the inputs and outputs of each transaction balance out with future transactions, this is possible because all transactions can be traced back to their coinbase transaction (also known as a "block reward"). This is true whether your node is pruned or not. In this way your node verifies all new transactions are valid, preventing double spending or inflation of the Bitcoin supply. You can think of it as preventing the counterfeiting of bitcoins as it would be impossible for an attacker to fake historic transactions in order to make the new one appear valid.
//                """
//                segueToShowDetail()
//            }
//
//        case .totalSupply:
//            if feeInfo != nil {
//                command = "gettxoutsetinfo"
//                detailHeaderText = headerName(for: .totalSupply)
//                detailSubheaderText = "Use your own node to verify total supply"
//                detailImage = UIImage(systemName: "person.fill.checkmark")!
//                detailImageTint = .systemYellow
//                detailTextDescription = """
//                Fully Noded uses the bitcoin-cli gettxoutsetinfo command to determine the total amount of mined Bitcoins. This command can take considerable time to load, usually around 30 seconds so please be patient while it loads.
//
//                With this command you can at anytime verify all the Bitcoins that have ever been issued without using any third parties at all.
//                """
//                segueToShowDetail()
//            }
//
//        case .nodeVersion:
//            if networkInfo != nil {
//                command = "getnetworkinfo"
//                detailHeaderText = headerName(for: .nodeVersion)
//                detailImageTint = .systemBlue
//                detailImage = UIImage(systemName: "v.circle")!
//                detailSubheaderText = "Bitcoin Core v\(networkInfo.version)"
//                detailTextDescription = """
//                The current version number of your node's software.
//
//                Fully Noded makes the bitcoin-cli getnetworkinfo command to your node in order to obtain information about your node's connection to the Bitcoin peer to peer network. The command returns your node's current version number along with other info regarding your connections. To get the version number Fully Noded looks specifically at the "subversion" field.
//
//                See the list of releases for each version along with detailed release notes.
//                """
//                segueToShowDetail()
//            }
//
//        case .blockchainNetwork:
//            if blockchainInfo != nil {
//                command = "getblockchaininfo"
//                detailHeaderText = headerName(for: .blockchainNetwork)
//                detailSubheaderText = blockchainInfo.network.capitalized
//                if blockchainInfo.network == "test chain" {
//                    detailImageTint = .green
//                } else if blockchainInfo.network == "main chain" {
//                    detailImageTint = .systemOrange
//                } else {
//                    detailImageTint = .systemTeal
//                }
//                detailImage = UIImage(systemName: "bitcoinsign.circle")!
//                switch blockchainInfo.network {
//                case "test":
//                    detailImageTint = #colorLiteral(red: 0.4399289489, green: 0.9726744294, blue: 0.2046178877, alpha: 1)
//                case "main":
//                    detailImageTint = #colorLiteral(red: 0.9629253745, green: 0.5778557658, blue: 0.1043280438, alpha: 1)
//                case "regtest":
//                    detailImageTint = #colorLiteral(red: 0.2165609896, green: 0.7795373201, blue: 0.9218732715, alpha: 1)
//                case "signet":
//                    detailImageTint = #colorLiteral(red: 0.8719944954, green: 0.9879228473, blue: 0.07238187641, alpha: 1)
//                default:
//                    detailImageTint = .systemTeal
//                }
//
//                detailTextDescription = """
//                Fully Noded makes the bitcoin-cli getblockchaininfo command to determine which network your node is running on. Your node can run three different chain's simultaneously; "main", "test" and "regtest". Fully Noded is capable of connecting to either one. To launch mutliple chains simultaneously you would want to run the "bitcoind" command with the "-chain=test", "-chain=regtest" arguments or omit the argument to run the main chain.
//
//                It should be noted when running multiple chains simultaneously you can not specifiy the network in your bitcoin.conf file.
//
//                The main chain is of course the real one, where real bitcoin can be spent and received.
//
//                The test chain is called "testnet3" and is mostly for users who would like to test new functionality or get familiar with how bitcoin really works before commiting real funds. Its also usefull for developers and stress testing.
//
//                The regtest chain is for developers who want to create their own personal blockchain, it is incredibly handy for developing bitcoin software as no internet is required and you can mine your own test bitcoins instantly. You may even setup multiple nodes and simulate specific kinds of network conditions.
//
//                Fully Noded talks to each node via a port. Generally mainnet uses the default port 8332, testnet 18332 and regtest 18443. However because Fully Noded works over Tor we actually use what are called virtual ports under the hood. The rpcports as just mentioned are only ever exposed to your nodes localhost meaning they are only accessible remotely via a Tor hidden service.
//                """
//                segueToShowDetail()
//            }
//
//        case .peerConnections:
//            if peerInfo != nil {
//                command = "getpeerinfo"
//                detailHeaderText = headerName(for: .peerConnections)
//                detailSubheaderText = "\(peerInfo.outgoingCount) outgoing / \(peerInfo.incomingCount) incoming"
//                detailImage = UIImage(systemName: "person.3")!
//                detailImageTint = .systemIndigo
//                detailTextDescription = """
//                Fully Noded makes the bitcoin-cli getpeerinfo command to your node in order to find out how many peers you are connected to.
//
//                You can have a number of incoming and outgoing peers, these are other nodes which your node is connected to over the peer to peer network (p2p). In order to receive incoming connections you can either forward port 8333 from your router or (more easily) use bitcoin core's built in functionality to create a hidden service using Tor to get incoming connections on, that way you can get incoming connections but do not need to forward a port.
//
//                The p2p network is where your node receives all the information it needs about historic transactions when carrying out its initial block download and verification as well as all newly broadcast transactions.
//
//                All new potential transactions are broadcast to the p2p network and whenever a peer learns of a new transaction it immedietly validates it and lets all of its peers know about the transaction, this is how bitcoin transactions propogate across the network. This way all nodes can stay up to date on the latest blocks/transactions.
//
//                Check out this link for a deeper dive into the Bitcoin p2p network.
//                """
//                segueToShowDetail()
//            }
//
//        case .blockchainState:
//            if blockchainInfo != nil {
//                command = "getblockchaininfo"
//                detailHeaderText = headerName(for: .blockchainState)
//                if blockchainInfo.pruned {
//                    detailSubheaderText = "Pruned"
//                    detailImage = UIImage(systemName: "rectangle.compress.vertical")!
//
//                } else if !blockchainInfo.pruned {
//                    detailSubheaderText = "Not pruned"
//                    detailImage = UIImage(systemName: "rectangle.expand.vertical")!
//                }
//                detailImageTint = .systemPurple
//                detailTextDescription = """
//                Fully Noded makes the bitcoin-cli getblockchaininfo command to determine the blockchain's state. When configuring your node you can set "prune=1" or specifiy a size in mebibytes to prune the blockchain to.
//
//                In this way you can avoid having to keep an entire copy of the blockchain on your computer, the minimum size is 550 mebibytes and the full current size is around 320gb.
//
//                Pruned nodes still verify and validate every single transaction so no trust is needed to prune your node, however you can lose some convenient functionality like restoring old wallets that you may want to migrate to your new node.
//
//                Once your initial block download and verification completes you can not "rescan" the blockchain past your prune height which is the block at which have pruned from.
//                """
//                segueToShowDetail()
//            }
//
//        default:
//            break
//        }
//    }
    
}

extension MainMenuViewController: UITableViewDataSource {}

extension MainMenuViewController: UINavigationControllerDelegate {}

