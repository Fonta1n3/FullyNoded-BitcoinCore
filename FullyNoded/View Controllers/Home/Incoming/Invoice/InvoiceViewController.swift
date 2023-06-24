//
//  InvoiceViewController.swift
//  BitSense
//
//  Created by Peter on 21/03/19.
//  Copyright © 2019 Fontaine. All rights reserved.
//

import UIKit

class InvoiceViewController: UIViewController, UITextFieldDelegate {
    
    var textToShareViaQRCode = String()
    var addressString = String()
    var qrCode = UIImage()
    var nativeSegwit = Bool()
    var p2shSegwit = Bool()
    var legacy = Bool()
    let qrGenerator = QRGenerator()
    var isHDInvoice = Bool()
    var descriptor = ""
    var wallet = [String:Any]()
    let ud = UserDefaults.standard
    var isBtc = false
    var isSats = false
    var isFiat = false
    var refreshButton = UIBarButtonItem()
    var dataRefresher = UIBarButtonItem()
    let spinner = UIActivityIndicatorView(style: .medium)
    
    @IBOutlet weak var invoiceHeader: UILabel!
    @IBOutlet var amountField: UITextField!
    @IBOutlet var labelField: UITextField!
    @IBOutlet var qrView: UIImageView!
    @IBOutlet var addressOutlet: UILabel!
    @IBOutlet private weak var invoiceText: UITextView!
    @IBOutlet private weak var messageField: UITextField!
    @IBOutlet weak var fieldsBackground: UIView!
    @IBOutlet weak var addressBackground: UIView!
    @IBOutlet weak var invoiceBackground: UIView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setDelegates()
        configureView(fieldsBackground)
        configureView(addressBackground)
        configureView(invoiceBackground)
        confirgureFields()
        configureTap()
        getAddressSettings()
        addDoneButtonOnKeyboard()
        addressOutlet.text = ""
        invoiceText.text = ""
        qrView.image = generateQrCode(key: "bitcoin:")
        generateOnchainInvoice()
    }
    
    private func addNavBarSpinner() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            spinner.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
            dataRefresher = UIBarButtonItem(customView: self.spinner)
            navigationItem.setRightBarButton(self.dataRefresher, animated: true)
            spinner.startAnimating()
            spinner.alpha = 1
        }
    }
    
    private func removeLoader() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            spinner.stopAnimating()
            spinner.alpha = 0
            refreshButton = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(refreshData(_:)))
            navigationItem.setRightBarButton(refreshButton, animated: true)
        }
    }
    
    @objc func refreshData(_ sender: Any) {
        generateOnchainInvoice()
    }
    
    @IBAction func switchDenominationsAction(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0:
            self.isBtc = true
            self.isSats = false
            self.isFiat = false
        default:
            self.isBtc = false
            self.isSats = true
            self.isFiat = false
        }
        
        updateQRImage()
    }
    
    
    private func setDelegates() {
        messageField.delegate = self
        amountField.delegate = self
        labelField.delegate = self
    }
    
    
    private func confirgureFields() {
        amountField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: .editingChanged)
        labelField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: .editingChanged)
        messageField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: .editingChanged)
    }
    
    
    private func configureTap() {
        let tap: UITapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        view.addGestureRecognizer(tap)
        amountField.removeGestureRecognizer(tap)
        labelField.removeGestureRecognizer(tap)
        messageField.removeGestureRecognizer(tap)
    }
    
    
    private func configureView(_ view: UIView) {
        view.clipsToBounds = true
        view.layer.cornerRadius = 8
        view.layer.borderColor = UIColor.darkGray.cgColor
        view.layer.borderWidth = 0.5
    }
    
    
    @IBAction func getAddressInfoAction(_ sender: Any) {
        func getFromRpc() {
            OnchainUtils.getAddressInfo(address: addressString) { (addressInfo, message) in
                guard let addressInfo = addressInfo else { return }
                showAlert(vc: self, title: "", message: addressInfo.hdkeypath + ": " + "solvable: \(addressInfo.solvable)")
            }
        }
        
        activeWallet { w in
            guard let _ = w else { return }
            
            getFromRpc()
        }
    }
    
    @IBAction func shareAddressAction(_ sender: Any) {
        shareText(addressString)
    }
    
    @IBAction func copyAddressAction(_ sender: Any) {
        UIPasteboard.general.string = addressString
        showAlert(vc: self, title: "", message: "Address copied ✓")
    }
    
    @IBAction func shareQrAction(_ sender: Any) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let activityController = UIActivityViewController(activityItems: [self.qrView.image as Any], applicationActivities: nil)
            activityController.popoverPresentationController?.sourceView = self.view
            activityController.popoverPresentationController?.sourceRect = self.view.bounds
            self.present(activityController, animated: true) {}
        }
    }
    
    @IBAction func copyQrAction(_ sender: Any) {
        UIPasteboard.general.image = self.qrView.image
        showAlert(vc: self, title: "", message: "QR copied ✓")
    }
    
    @IBAction func shareInvoiceTextAction(_ sender: Any) {
        shareText(invoiceText.text)
    }
    
    @IBAction func copyInvoiceTextAction(_ sender: Any) {
        UIPasteboard.general.string = invoiceText.text
        showAlert(vc: self, title: "", message: "Invoice copied ✓")
    }
            
    @IBAction func generateOnchainAction(_ sender: Any) {
        generateOnchainInvoice()
    }
    
    func generateOnchainInvoice() {
        addNavBarSpinner()
        
        addressOutlet.text = ""
        
        activeWallet { [weak self] wallet in
            guard let self = self else { return }
            
            guard let wallet = wallet else {
                self.fetchAddress()
                return
            }
            if wallet.type == WalletType.descriptor.stringValue {
                self.getReceieveAddressForFullyNodedWallet(wallet)
            } else {
                self.fetchAddress()
            }
        }
    }
            
    private func getReceieveAddressForFullyNodedWallet(_ wallet: Wallet) {
        let index = Int(wallet.index) + 1
        
        CoreDataService.update(id: wallet.id, keyToUpdate: "index", newValue: Int64(index), entity: .wallets) { success in
            guard success else { return }
            
            let param:Derive_Addresses = .init(["descriptor":wallet.receiveDescriptor, "range":[index,index]])
            
                                                Reducer.sharedInstance.makeCommand(command: .deriveaddresses(param: param)) { [weak self] (response, errorMessage) in
                guard let self = self else { return }
                
                guard let addresses = response as? NSArray, let address = addresses[0] as? String else {
                    showAlert(vc: self, title: "", message: errorMessage ?? "error getting multisig address")
                    return
                }
                
                self.showAddress(address: address)
            }
        }
    }
    
    func getAddressSettings() {
        let ud = UserDefaults.standard
        nativeSegwit = ud.object(forKey: "nativeSegwit") as? Bool ?? true
        p2shSegwit = ud.object(forKey: "p2shSegwit") as? Bool ?? false
        legacy = ud.object(forKey: "legacy") as? Bool ?? false
    }
    
    func fetchAddress() {
        var addressType = ""
        
        if self.nativeSegwit {
            addressType = "bech32"
        } else if self.legacy {
            addressType = "legacy"
        } else if self.p2shSegwit {
            addressType = "p2sh-segwit"
        }
        
        let param:Get_New_Address = .init(["address_type":addressType])
        
        self.getAddress(param)
    }
    
    func showAddress(address: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.addressOutlet.alpha = 1
            self.addressOutlet.text = address
            self.addressString = address
            self.updateQRImage()
            removeLoader()
        }
    }
        
    private func shareText(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let textToShare = [text]
            let activityViewController = UIActivityViewController(activityItems: textToShare, applicationActivities: nil)
            activityViewController.popoverPresentationController?.sourceView = self.view
            activityViewController.popoverPresentationController?.sourceRect = self.view.bounds
            self.present(activityViewController, animated: true) {}
        }
    }
    
    func getAddress(_ params: Get_New_Address) {
        Reducer.sharedInstance.makeCommand(command: .getnewaddress(param: params)) { [weak self] (response, errorMessage) in
            guard let self = self else { return }
            guard let address = response as? String else {
                removeLoader()
                
                showAlert(vc: self, title: "Error", message: errorMessage ?? "unknown error fetching address")
                
                return
            }
            
            self.showAddress(address: address)
        }
    }
    
    @objc func textFieldDidChange(_ textField: UITextField) {
        updateQRImage()
    }
    
    func generateQrCode(key: String) -> UIImage {
        qrGenerator.textInput = key
        let qr = qrGenerator.getQRCode()
        return qr
    }
    
    func updateQRImage() {
        var newImage = UIImage()
        var amount = self.amountField.text ?? ""
                
        if isSats {
            if amount != "" {
                if let dbl = Double(amount) {
                    amount = (dbl / 100000000.0).avoidNotation
                }
            }
        }
        
        let label = self.labelField.text?.replacingOccurrences(of: " ", with: "%20") ?? ""
        let message = self.messageField.text?.replacingOccurrences(of: " ", with: "%20") ?? ""
        textToShareViaQRCode = "bitcoin:\(self.addressString)"
        let dict = ["amount": amount, "label": label, "message": message]
        
        if amount != "" || label != "" || message != "" {
            textToShareViaQRCode += "?"
        }
        
        for (key, value) in dict {
            if textToShareViaQRCode.contains("amount=") || textToShareViaQRCode.contains("label=") || textToShareViaQRCode.contains("message=") {
                if value != "" {
                    textToShareViaQRCode += "&\(key)=\(value)"
                }
            } else {
                if value != "" {
                    textToShareViaQRCode += "\(key)=\(value)"
                }
            }
        }
        
        newImage = self.generateQrCode(key:textToShareViaQRCode)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            UIView.transition(with: self.qrView,
                              duration: 0.75,
                              options: .transitionCrossDissolve,
                              animations: { self.qrView.image = newImage },
                              completion: nil)
            
            self.invoiceText.text = self.textToShareViaQRCode
        }
    }
    
    @objc func doneButtonAction() {
        self.amountField.resignFirstResponder()
        self.labelField.resignFirstResponder()
        self.messageField.resignFirstResponder()
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        view.endEditing(true)
        return false
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        updateQRImage()
    }
    
    func addDoneButtonOnKeyboard() {
        let doneToolbar = UIToolbar()
        doneToolbar.frame = CGRect(x: 0, y: 0, width: 320, height: 50)
        doneToolbar.barStyle = .default
        
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let done: UIBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(doneButtonAction))
        
        let items = NSMutableArray()
        items.add(flexSpace)
        items.add(done)
        
        doneToolbar.items = (items as! [UIBarButtonItem])
        doneToolbar.sizeToFit()
        
        self.amountField.inputAccessoryView = doneToolbar
        self.labelField.inputAccessoryView = doneToolbar
        self.messageField.inputAccessoryView = doneToolbar
    }
    
    @objc func dismissKeyboard() {
        view.endEditing(true)
    }
}
