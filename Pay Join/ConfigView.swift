//
//  ConfigView.swift
//  Pay Join
//
//  Created by Peter Denton on 2/13/24.
//

import SwiftUI


struct ConfigView: View {
    @State private var rpcAuth = ""
    @State private var rpcWallet = ""
    @State private var rpcWallets: [String] = []
    @State private var rpcPort = UserDefaults.standard.object(forKey: "rpcPort") as? String ?? "8332"
    @State private var nostrEncryptionWords = ""
    
    
    func setValues() {
        DataManager.retrieve(entityName: "Credentials", completion: { credentials in
            guard let credentials = credentials else {
                guard let rpcauthcreds = RPCAuth().generateCreds(username: "PayJoin", password: nil) else { return }
                let rpcpass = rpcauthcreds.password
                let randomKey = Crypto.randomKey//save to keychain
                guard KeyChain.set(randomKey.data(using: .utf8)!, forKey: "encKey") else { return }
                let password = Crypto.randomKey
                guard let encryptedKey = Crypto.encryptNostr(password.data(using: .utf8)!, randomKey) else { return }
                // save encrypted key to core data and the random enc key to the keychain.
                
                let p: [String: Any] = ["rpcpass": rpcpass.data(using: .utf8)!, "nostrKey": encryptedKey]
                DataManager.saveEntity(dict: p) { saved in
                    guard saved else {
                        print("not saved")
                        return
                    }
                }
                return
            }
            
            guard let rpcpass = credentials["rpcpass"] as? Data else {
                print("no rpc creds")
                return
            }
            
            guard let nostrKey = credentials["nostrKey"] as? Data else { return }
            guard let encKey = KeyChain.getData("encKey") else { return }
            guard let decryptedNostrKey = Crypto.decryptNostr(nostrKey, String(data: encKey, encoding: .utf8)!) else {
                return
            }
            
            print("decryptedNostrKey: \(decryptedNostrKey)")
            
            guard let rpcauthcreds = RPCAuth().generateCreds(username: "PayJoin", password: String(data: rpcpass, encoding: .utf8)) else { return }
            rpcAuth = rpcauthcreds.rpcAuth
            if let walletName = UserDefaults.standard.object(forKey: "walletName") as? String {
                rpcWallet = walletName
            }
            rpcPort = UserDefaults.standard.object(forKey: "rpcPort") as? String ?? "8332"
            
            BitcoinCoreRPC.shared.btcRPC(method: .listwallets) { (response, errorDesc) in
                guard errorDesc == nil else {
                    print("errorDesc: \(errorDesc)")
                    rpcWallets.removeAll()
                    return
                }
                
                guard let wallets = response as? [String] else { return }
                
                for wallet in wallets {
                    rpcWallets.append(wallet)
                }
            }
        })
    }
    
    var body: some View {
        Form() {
            Section("RPC Authentication") {
                TextField("", text: $rpcAuth)
                    .truncationMode(.middle)
            }
            Section("RPC Port") {
                TextField("", text: $rpcPort)
                    .onSubmit {
                        UserDefaults.standard.setValue(rpcPort, forKey: "rpcPort")
                    }
            }
            Section("RPC Wallet") {
                if rpcWallets.count == 0 {
                    Text("No response from bitcoin-cli listwallets...")
                }
                ForEach(rpcWallets, id: \.self) { wallet in
                    if rpcWallet == wallet {
                        Text(wallet)
                            .bold()
                    } else {
                        Text(wallet)
                            .onTapGesture {
                                print("tapped \(wallet)")
                                UserDefaults.standard.setValue(wallet, forKey: "walletName")
                                rpcWallet = wallet
                            }
                    }
                }
            }
            Section("Nostr Encryption") {
                SecureField("", text: $nostrEncryptionWords)
            }
        }
        .formStyle(.grouped)
        .multilineTextAlignment(.leading)
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
        .onSubmit {
            setValues()
        }
        .onAppear {
            setValues()
        }
    }
}
