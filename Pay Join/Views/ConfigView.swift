//
//  ConfigView.swift
//  Pay Join
//
//  Created by Peter Denton on 2/13/24.
//

import SwiftUI
import UniformTypeIdentifiers
import NostrSDK

struct ConfigView: View {
    @State private var rpcUser = "PayJoin"
    @State private var rpcPassword = ""
    @State private var rpcAuth = ""
    @State private var rpcWallet = ""
    @State private var rpcWallets: [String] = []
    @State private var rpcPort = UserDefaults.standard.object(forKey: "rpcPort") as? String ?? "8332"
    @State private var nostrRelay = UserDefaults.standard.object(forKey: "nostrRelay") as? String ?? "wss://relay.damus.io"
    @State private var nostrEncryptionWords = ""
    @State private var showBitcoinCoreError = false
    @State private var bitcoinCoreError = ""
    @State private var showNoCredsError = false
    @State private var showCopiedAlert = false
    @State private var showEncWords = false
    @State private var peerNpub = UserDefaults.standard.object(forKey: "peerNpub") as? String ?? ""
    @State private var nostrPrivkey = ""
    
    private func setValues() {
        print("setValues")
        rpcWallets.removeAll()
        rpcWallet = ""
        
        //DataManager.deleteAllData { deleted in
            //if deleted {
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
                        print("no rpcUser")
                        return
                    }
                    
                    self.rpcUser = rpcUser
                    
                    guard let rpcauthcreds = RPCAuth().generateCreds(username: rpcUser, password: rpcPass) else {
                        print("rpcAuthCreds failing")
                        return
                    }
                    
                    rpcAuth = rpcauthcreds.rpcAuth
                    
                    if let walletName = UserDefaults.standard.object(forKey: "walletName") as? String {
                        rpcWallet = walletName
                    }
                    
                    rpcPort = UserDefaults.standard.object(forKey: "rpcPort") as? String ?? "8332"
                    
                    nostrRelay = UserDefaults.standard.object(forKey: "nostrRelay") as? String ?? "wss://relay.damus.io"
                    
                    guard let encNostrPrivkey = credentials["nostrPrivkey"] as? Data else {
                        print("no nostrPrivkey")
                        return
                    }
                    
                    guard let nostrPrivkeyData = Crypto.decrypt(encNostrPrivkey) else {
                        print("unable to decrypt nostrPrivkey")
                        return
                    }
                                        
                    self.nostrPrivkey = nostrPrivkeyData.hex
                    self.peerNpub = UserDefaults.standard.object(forKey: "peerNpub") as? String ?? ""
                    
                    BitcoinCoreRPC.shared.btcRPC(method: .listwallets) { (response, errorDesc) in
                        guard errorDesc == nil else {
                            bitcoinCoreError = errorDesc!
                            showBitcoinCoreError = true
                            //rpcWallets.removeAll()
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
            //}
        //}
        
    }
    
    
    private func updateRpcUser(rpcUser: String) {
        DataManager.update(entityName: "Credentials", keyToUpdate: "rpcUser", newValue: rpcUser) { updated in
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
        
        DataManager.update(entityName: "Credentials", keyToUpdate: "rpcPass", newValue: encryptedRpcPass) { updated in
            if updated {
                rpcPassword = rpcPass
                setValues()
            } else {
                //show error
            }
        }
    }
    
    private func updateNostrPrivkey(nostrPrivkey: String) {
        guard let nostrPrivkeyData = nostrPrivkey.data(using: .utf8) else { return }
        
        guard let encryptedNostrPrivkey = Crypto.encrypt(nostrPrivkeyData) else { return }
        
        DataManager.update(entityName: "Credentials", keyToUpdate: "nostrPrivkey", newValue: encryptedNostrPrivkey) { updated in
            if updated {
                self.nostrPrivkey = nostrPrivkey
                setValues()
            } else {
                //show error
            }
        }
    }
    
    var body: some View {
        Spacer()
        Label("Configuration", systemImage: "gear")
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
                    Button("", systemImage: "arrow.clockwise") {
                        rpcPassword = Crypto.privateKey
                        updateRpcPass(rpcPass: rpcPassword)
                        //setValues()
                    }
                }
               
            }
            
            Section("RPC Authentication") {
                HStack {
                    Text(rpcAuth)
                        .truncationMode(.middle)
                        .lineLimit(1)
                    
                    ShareLink(" ", item: rpcAuth)
                    
                    Button(" ", systemImage: "doc.on.doc") {
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
            
            Section("Nostr Relay") {
                TextField("", text: $nostrRelay)
                    .onSubmit {
                        print("on submit")
                        //rpcWallets.removeAll()
                        //rpcWallet = ""
                        print("nostrRelay \(nostrRelay)")
                        nostrRelay = nostrRelay
                        UserDefaults.standard.setValue(nostrRelay, forKey: "nostrRelay")
                        
                        //setValues()
                    }
                    
            }
            
            if nostrPrivkey != "" {
                Section("Nostr privkey") {
                    HStack {
                        SecureField("", text: $nostrPrivkey)
                            .onSubmit {
                                updateNostrPrivkey(nostrPrivkey: nostrPrivkey)
                            }
                        Button("", systemImage: "arrow.clockwise") {
                            updateRpcPass(rpcPass: Crypto.privateKey)
                            setValues()
                        }
                    }
                   
                }
                
                Section("Nostr npub") {
                    let privKey = PrivateKey(hex: nostrPrivkey)!
                    let keypair = Keypair(privateKey: privKey)
                    let npub = keypair!.publicKey.npub
                    
                    HStack {
                        Text(npub)
                            .truncationMode(.middle)
                            .lineLimit(1)
                        
                        ShareLink(" ", item: npub)
                        
                        Button(" ", systemImage: "doc.on.doc") {
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(npub, forType: .string)
                            #elseif os(iOS)
                            UIPasteboard.general.string = npub
                            #endif
                            showCopiedAlert = true
                        }
                    }
                }
                
                Section("Subscribe to") {
                    TextField("", text: $peerNpub)
                        .onSubmit {
                            UserDefaults.standard.setValue(peerNpub, forKey: "peerNpub")
                            setValues()
                        }
                        .autocorrectionDisabled()
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
        .alert("Copied ✓", isPresented: $showCopiedAlert) {
            Button("OK", role: .cancel) { }
        }
    }
}
