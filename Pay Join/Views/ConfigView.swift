//
//  ConfigView.swift
//  Pay Join
//
//  Created by Peter Denton on 2/13/24.
//

import SwiftUI
import UniformTypeIdentifiers

struct ConfigView: View {
    @State private var rpcUser = "PayJoin"
    @State private var rpcPassword = ""
    @State private var rpcAuth = ""
    @State private var rpcWallet = ""
    @State private var rpcWallets: [String] = []
    @State private var rpcPort = UserDefaults.standard.object(forKey: "rpcPort") as? String ?? "8332"
    @State private var nostrEncryptionWords = ""
    @State private var showBitcoinCoreError = false
    @State private var bitcoinCoreError = ""
    @State private var showNoCredsError = false
    @State private var showCopiedAlert = false
    @State private var showEncWords = false
    
    private func setValues() {
        rpcWallets.removeAll()
        
        DataManager.retrieve(entityName: "Credentials", completion: { credentials in
            guard let credentials = credentials else {
                showNoCredsError = true
                return
            }
                        
            guard let encRpcPass = credentials["rpcPass"] as? Data else {
                print("no rpc creds")
                return
            }
            
            guard let rpcPassData = Crypto.decrypt(encRpcPass) else { print("unable to decrypt rpcpass"); return }
            
            guard let rpcPass = String(data: rpcPassData, encoding: .utf8) else { return }
            
            rpcPassword = rpcPass
            
            guard let rpcUser = credentials["rpcUser"] as? String else {
                return
            }
            
            self.rpcUser = rpcUser
            
            guard let encNostrWords = credentials["nostrEncWords"] as? Data else {
                print("no encNostrWords")
                return
            }
            
            guard let decryptedNostrWords = Crypto.decrypt(encNostrWords) else {
                print("no decrypted nostr words")
                return
            }
            
            nostrEncryptionWords = String(data: decryptedNostrWords, encoding: .utf8)!
            
            guard let rpcauthcreds = RPCAuth().generateCreds(username: rpcUser, password: rpcPass) else { return }
            
            rpcAuth = rpcauthcreds.rpcAuth
            
            if let walletName = UserDefaults.standard.object(forKey: "walletName") as? String {
                rpcWallet = walletName
            }
            
            rpcPort = UserDefaults.standard.object(forKey: "rpcPort") as? String ?? "8332"
            
            BitcoinCoreRPC.shared.btcRPC(method: .listwallets) { (response, errorDesc) in
                guard errorDesc == nil else {
                    bitcoinCoreError = errorDesc!
                    showBitcoinCoreError = true
                    rpcWallets.removeAll()
                    return
                }
                
                guard let wallets = response as? [String] else {
                    showBitcoinCoreError = true
                    bitcoinCoreError = BitcoinCoreError.noWallets.localizedDescription
                    return
                }
                
                guard wallets.count > 0 else {
                    showBitcoinCoreError = true
                    bitcoinCoreError = "No wallets exist yet..."
                    return
                }
                
                for wallet in wallets {
                    rpcWallets.append(wallet)
                }
            }
        })
    }
    
    private func saveNewNostrEncWords(words: String) {
        guard let encWordsData = words.data(using: .utf8) else { return }
        
        guard let encryptedWords = Crypto.encrypt(encWordsData) else { return }
        
        DataManager.update(keyToUpdate: "nostrEncWords", newValue: encryptedWords) { updated in
            if updated {
                nostrEncryptionWords = words
            } else {
                //show error
            }
        }
    }
    
    private func updateRpcUser(rpcUser: String) {
        DataManager.update(keyToUpdate: "rpcUser", newValue: rpcUser) { updated in
            if updated {
                self.rpcUser = rpcUser
            } else {
                //show error
            }
        }
    }
    
    private func updateRpcPass(rpcPass: String) {
        guard let rpcPassData = rpcPass.data(using: .utf8) else { return }
        
        guard let encryptedRpcPass = Crypto.encrypt(rpcPassData) else { return }
        
        DataManager.update(keyToUpdate: "rpcPass", newValue: encryptedRpcPass) { updated in
            if updated {
                rpcPassword = rpcPass
            } else {
                //show error
            }
        }
    }
    
    var body: some View {
        Form() {
            Section("RPC User") {
                TextField("", text: $rpcUser)
                    .onSubmit {
                        // update rpcUser
                        updateRpcUser(rpcUser: rpcUser)
                        setValues()
                    }
            }
            
            Section("RPC Password") {
                HStack {
                    SecureField("", text: $rpcPassword)
                        .onSubmit {
                            // update rpcPass
                            updateRpcPass(rpcPass: rpcPassword)
                            setValues()
                        }
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        rpcPassword = Crypto.privateKey
                        updateRpcPass(rpcPass: rpcPassword)
                        setValues()
                    }
                }
               
            }
            
            Section("RPC Authentication") {
                HStack {
                    Text(rpcAuth)
                        .truncationMode(.middle)
                    
                    ShareLink("Export", item: rpcAuth)
                    
                    Button("Copy", systemImage: "doc.on.doc") {
                        #if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(rpcAuth, forType: .string)
                        #elseif os(iOS)
                        UIPasteboard.general.string = rpcAuth
                        #endif
                        showCopiedAlert = true
                    }
                }
            }
            
            Section("RPC Port") {
                TextField("", text: $rpcPort)
                    .onSubmit {
                        UserDefaults.standard.setValue(rpcPort, forKey: "rpcPort")
                        setValues()
                    }
            }
            
            Section("RPC Wallet") {
                if rpcWallets.count == 0 {
                    Text("No wallets...")
                }
                ForEach(rpcWallets, id: \.self) { wallet in
                    if rpcWallet == wallet {
                        HStack {
                            Image(systemName: "checkmark")
                            Text(wallet)
                                .bold()
                        }
                        
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
                HStack {
                    if showEncWords {
                        TextField("", text: $nostrEncryptionWords)
                            .onSubmit {
                                //save new words
                                saveNewNostrEncWords(words: nostrEncryptionWords)
                            }
                        Button("Hide", systemImage: "eye.slash") {
                            showEncWords = false
                        }
                    } else {
                        SecureField("", text: $nostrEncryptionWords)
                            .onSubmit {
                                //save new words
                                saveNewNostrEncWords(words: nostrEncryptionWords)
                            }
                        Button("Show", systemImage: "eye") {
                            showEncWords = true
                        }
                    }
                    
                }
               
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
        .alert(bitcoinCoreError, isPresented: $showBitcoinCoreError) {
            Button("OK", role: .cancel) { }
        }
        .alert(CoreDataError.notPresent.localizedDescription, isPresented: $showNoCredsError) {
            Button("OK", role: .cancel) { }
        }
        .alert("RPC Authentication copied ✓", isPresented: $showCopiedAlert) {
            Button("OK", role: .cancel) { }
        }
    }
}
