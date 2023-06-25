//
//  LogInViewController.swift
//  BitSense
//
//  Created by Peter on 03/09/18.
//  Copyright © 2018 Fontaine. All rights reserved.
//

import UIKit
import LocalAuthentication

class LogInViewController: UIViewController, UITextFieldDelegate {

    var onDoneBlock: (() -> Void)?
    let fingerPrintView = UIImageView()
    let nextAttemptLabel = UILabel()
    var timeToDisable = 2.0
    var timer: Timer?
    var secondsRemaining = 2
    var tapGesture:UITapGestureRecognizer!
    var isRessetting = false
    var initialLoad = true
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var touchIdButton: UIButton!
    @IBOutlet weak var passwordInput: UITextField!
    @IBOutlet weak var resetButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.dismissKeyboard (_:)))
        tapGesture.numberOfTapsRequired = 1
        self.view.addGestureRecognizer(tapGesture)
        resetButton.alpha = 0
        passwordInput.delegate = self
        passwordInput.autocapitalizationType = .none
        passwordInput.autocorrectionType = .no

        guard let timeToDisableOnKeychain = KeyChain.getData("TimeToDisable") else {
            let _ = KeyChain.set("2.0".utf8, forKey: "TimeToDisable")
            return
        }

        guard let seconds = timeToDisableOnKeychain.utf8String, let time = Double(seconds) else { return }

        timeToDisable = time
        secondsRemaining = Int(timeToDisable)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        if initialLoad {
            initialLoad = false
            passwordInput.removeGestureRecognizer(tapGesture)

            let ud = UserDefaults.standard
            let bioMetricsDisabled = ud.object(forKey: "bioMetricsDisabled") as? Bool ?? false

            if bioMetricsDisabled {
                touchIdButton.removeFromSuperview()
            } else {
                if !bioMetricsDisabled {
                    touchIdButton.alpha = 1
                    authenticationWithTouchID()
                }
            }

            configureTimeoutLabel()

            if timeToDisable > 2.0 {
                disable()
            }
        }
    }
    
    @IBAction func touchIdAction(_ sender: Any) {
        authenticationWithTouchID()
    }
    
    
    private func addResetPassword() {
        resetButton.alpha = 1
    }
    
    @IBAction func resetAction(_ sender: Any) {
        promptToReset()
    }
    
    @IBAction func unlockAction(_ sender: Any) {
        nextButtonAction()
    }
    
    
    
    private func promptToReset() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let alert = UIAlertController(title: "⚠️ Reset app password?",
                                          message: "THIS DELETES ALL DATA AND COMPLETELY WIPES THE APP! Force quit the app and reopen the app after this action.",
                                          preferredStyle: .alert)
            
            alert.addAction(UIAlertAction(title: "Reset", style: .destructive, handler: { [weak self] action in
                guard let self = self else { return }
                
                self.destroy { destroyed in
                    if destroyed {
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            
                            KeyChain.removeAll()
                            self.timeToDisable = 0.0
                            self.timer?.invalidate()
                            self.secondsRemaining = 0
                            self.dismiss(animated: true) {
                                showAlert(vc: self, title: "", message: "The app has been wiped.")
                                self.onDoneBlock!()
                            }
                        }
                    } else {
                        showAlert(vc: self, title: "", message: "The app was not wiped!")
                    }
                }
            }))
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { action in }))
            alert.popoverPresentationController?.sourceView = self.view
            self.present(alert, animated: true) {}
        }
    }
    
    private func destroy(completion: @escaping ((Bool)) -> Void) {
        
        let entities:[ENTITY] = [.authKeys,
                                 .nodes,
                                 .signers,
                                 .transactions,
                                 .utxos,
                                 .wallets]
        
        for entity in entities {
            deleteEntity(entity: entity) { success in
                completion(success)
            }
        }
    }
    
    private func deleteEntity(entity: ENTITY, completion: @escaping ((Bool)) -> Void) {
        CoreDataService.deleteAllData(entity: entity) { success in
            completion((success))
        }
    }
    
    @objc func present2fa() {
        self.promptToReset()
    }

    @objc func dismissKeyboard(_ sender: UITapGestureRecognizer) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.passwordInput.resignFirstResponder()
        }
    }

    @objc func nextButtonAction() {
        guard passwordInput.text != "" else {
            shakeAlert(viewToShake: passwordInput)
            return
        }

        passwordInput.resignFirstResponder()
        checkPassword(password: passwordInput.text!)
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard passwordInput.text != "" else {
            shakeAlert(viewToShake: passwordInput)
            return true
        }
        
        checkPassword(password: passwordInput.text!)
        
        return true
    }

    private func unlock() {
        let _ = KeyChain.set("2.0".dataUsingUTF8StringEncoding, forKey: "TimeToDisable")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.passwordInput.text = ""
            
            DispatchQueue.main.async {
                self.dismiss(animated: true) {
                    self.onDoneBlock!()
                }
            }
        }
    }

    func checkPassword(password: String) {
        guard let passwordData = KeyChain.getData("UnlockPassword") else { return }

        let retrievedPassword = passwordData.utf8String

        let hashedPassword = Crypto.sha256hash(password)

        guard let hexData = Data(hexString: hashedPassword) else { return }

        /// Overwrite users password with the hash of the password, sorry I did not do this before...
        if password == retrievedPassword {
            let _ = KeyChain.set(hexData, forKey: "UnlockPassword")
            unlock()

        } else {
            if hexData.hexString == passwordData.hexString {
                unlock()

            } else {
                timeToDisable = timeToDisable * 2.0
                
                if timeToDisable > 4.0 {
                    addResetPassword()
                }

                guard KeyChain.set("\(timeToDisable)".dataUsingUTF8StringEncoding, forKey: "TimeToDisable") else {
                    showAlert(vc: self, title: "Unable to set timeout", message: "This means something is very wrong, the device has probably been jailbroken or is corrupted")
                    return
                }

                secondsRemaining = Int(timeToDisable)

                disable()
            }
        }
    }

    private func configureTimeoutLabel() {
        nextAttemptLabel.textColor = .lightGray
        nextAttemptLabel.frame = CGRect(x: 0, y: view.frame.maxY - 50, width: view.frame.width, height: 50)
        nextAttemptLabel.textAlignment = .center
        nextAttemptLabel.text = ""
        view.addSubview(nextAttemptLabel)
    }

    private func disable() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.passwordInput.alpha = 0
            self.passwordInput.isUserInteractionEnabled = false
            self.nextButton.removeTarget(self, action: #selector(self.nextButtonAction), for: .touchUpInside)
            self.nextButton.alpha = 0
        }

        timer?.invalidate()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                if self.secondsRemaining == 0 {
                    self.timer?.invalidate()
                    self.nextAttemptLabel.text = ""
                    self.nextButton.addTarget(self, action: #selector(self.nextButtonAction), for: .touchUpInside)
                    self.nextButton.alpha = 1
                    self.passwordInput.alpha = 1
                    self.passwordInput.isUserInteractionEnabled = true
                } else {
                    self.secondsRemaining -= 1
                    self.nextAttemptLabel.text = "try again in \(self.secondsRemaining) seconds"
                }
            }
        }

        showAlert(vc: self, title: "Wrong password", message: "")
    }
    
    @objc func authenticationWithTouchID() {
        let localAuthenticationContext = LAContext()
        localAuthenticationContext.localizedFallbackTitle = "Use passcode"
        var authError: NSError?
        let reasonString = "To unlock"

        if localAuthenticationContext.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) {
            localAuthenticationContext.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reasonString) { success, evaluateError in
                if success {
                    DispatchQueue.main.async {
                        self.unlock()
                    }
                } else {
                    guard let error = evaluateError else { return }

                    print(self.evaluateAuthenticationPolicyMessageForLA(errorCode: error._code))
                }
            }

        } else {

            guard let error = authError else { return }

            //TODO: Show appropriate alert if biometry/TouchID/FaceID is lockout or not enrolled
            if self.evaluateAuthenticationPolicyMessageForLA(errorCode: error._code) != "Too many failed attempts." {

            }
        }
    }

    func evaluatePolicyFailErrorMessageForLA(errorCode: Int) -> String {
        var message = ""

        if #available(iOS 11.0, macOS 10.13, *) {

            switch errorCode {

            case LAError.biometryNotAvailable.rawValue:
                message = "Authentication could not start because the device does not support biometric authentication."

            case LAError.biometryLockout.rawValue:
                message = "Authentication could not continue because the user has been locked out of biometric authentication, due to failing authentication too many times."

            case LAError.biometryNotEnrolled.rawValue:
                message = "Authentication could not start because the user has not enrolled in biometric authentication."

            default:
                message = "Did not find error code on LAError object"
            }

        } else {

            switch errorCode {

            case LAError.touchIDLockout.rawValue:
                message = "Too many failed attempts."

            case LAError.touchIDNotAvailable.rawValue:
                message = "TouchID is not available on the device"

            case LAError.touchIDNotEnrolled.rawValue:
                message = "TouchID is not enrolled on the device"

            default:
                message = "Did not find error code on LAError object"
            }

        }

        return message

    }

    func evaluateAuthenticationPolicyMessageForLA(errorCode: Int) -> String {
        var message = ""

        switch errorCode {
        case LAError.authenticationFailed.rawValue:
            message = "The user failed to provide valid credentials"

        case LAError.appCancel.rawValue:
            message = "Authentication was cancelled by application"

        case LAError.invalidContext.rawValue:
            message = "The context is invalid"

        case LAError.notInteractive.rawValue:
            message = "Not interactive"

        case LAError.passcodeNotSet.rawValue:
            message = "Passcode is not set on the device"

        case LAError.systemCancel.rawValue:
            message = "Authentication was cancelled by the system"

        case LAError.userCancel.rawValue:
            message = "The user did cancel"

        case LAError.userFallback.rawValue:
            message = "The user chose to use the fallback"

        default:
            message = evaluatePolicyFailErrorMessageForLA(errorCode: errorCode)
        }

        return message
    }
}

extension UIViewController {

    func topViewController() -> UIViewController! {

        if self.isKind(of: UITabBarController.self) {

            let tabbarController =  self as! UITabBarController

            return tabbarController.selectedViewController!.topViewController()

        } else if (self.isKind(of: UINavigationController.self)) {

            let navigationController = self as! UINavigationController

            return navigationController.visibleViewController!.topViewController()

        } else if ((self.presentedViewController) != nil) {

            let controller = self.presentedViewController

            return controller!.topViewController()

        } else {

            return self

        }

    }

}
