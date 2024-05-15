//
//  ConfigView.swift
//  Pay Join
//
//  Created by Peter Denton on 2/13/24.
//

import SwiftUI
import UniformTypeIdentifiers
import NostrSDK
import LibWally

struct ConfigView: View {
    @State private var rpcUser = "PayJoin"
    @State private var rpcPassword = ""
    @State private var rpcAuth = ""
    @State private var rpcWallet = ""
    @State private var rpcWallets: [String] = []
    @State private var rpcPort = UserDefaults.standard.object(forKey: "rpcPort") as? String ?? "8332"
    @State private var nostrRelay = UserDefaults.standard.object(forKey: "nostrRelay") as? String ?? "wss://relay.damus.io"
    @State private var showBitcoinCoreError = false
    @State private var bitcoinCoreError = ""
    @State private var showNoCredsError = false
    @State private var peerNpub = UserDefaults.standard.object(forKey: "peerNpub") as? String ?? ""
    @State private var nostrPrivkey = ""
    @State private var encSigner = ""
    
    private func setValues() {
        rpcWallets.removeAll()
        rpcWallet = ""
        
        DataManager.retrieve(entityName: "Signers") { signer in
            guard let signer = signer, let encSignerData = signer["encryptedData"] as? Data else { return }
            self.encSigner = encSignerData.hex
        }
        
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
                rpcWallets = wallets
            }
        })
    }
    
    
    private func updateRpcUser(rpcUser: String) {
        DataManager.update(entityName: "Credentials", keyToUpdate: "rpcUser", newValue: rpcUser) { updated in
            if updated {
                self.rpcUser = rpcUser
            }
        }
    }
    
    
    private func updateRpcPass(rpcPass: String) {
        guard let rpcPassData = rpcPass.data(using: .utf8) else { return }
        guard let encryptedRpcPass = Crypto.encrypt(rpcPassData) else { return }
        DataManager.update(entityName: "Credentials", keyToUpdate: "rpcPass", newValue: encryptedRpcPass) { updated in
            if updated {
                self.rpcPassword = rpcPass
            }
        }
    }
    
    
    private func updateNostrPrivkey(nostrPrivkey: String) {
        guard let nostrPrivkeyData = nostrPrivkey.data(using: .utf8) else { return }
        guard let encryptedNostrPrivkey = Crypto.encrypt(nostrPrivkeyData) else { return }
        DataManager.update(entityName: "Credentials", keyToUpdate: "nostrPrivkey", newValue: encryptedNostrPrivkey) { updated in
            if updated {
                self.nostrPrivkey = nostrPrivkey
            }
        }
    }
    
    
    var body: some View {
        Spacer()
        Label("Configuration", systemImage: "gear")
        Form() {
            Section("RPC Credentials") {
                TextField("User", text: $rpcUser)
                    .onSubmit {
                        updateRpcUser(rpcUser: rpcUser)
                        setValues()
                    }
                HStack {
                    SecureField("Password", text: $rpcPassword)
                        .onSubmit {
                            updateRpcPass(rpcPass: rpcPassword)
                            setValues()
                        }
                    Button("", systemImage: "arrow.clockwise") {
                        rpcPassword = Crypto.privateKey
                        updateRpcPass(rpcPass: rpcPassword)
                    }
                }
                CopyView(item: rpcAuth, title: "Auth")
                TextField("Port", text: $rpcPort)
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
                                UserDefaults.standard.setValue(wallet, forKey: "walletName")
                                rpcWallet = wallet
                            }
                    }
                }
            }
            Section("Nostr Credentials") {
                TextField("Relay", text: $nostrRelay)
                    .onSubmit {
                        nostrRelay = nostrRelay
                        UserDefaults.standard.setValue(nostrRelay, forKey: "nostrRelay")
                    }
                HStack {
                    SecureField("Private key", text: $nostrPrivkey)
                        .onSubmit {
                            updateNostrPrivkey(nostrPrivkey: nostrPrivkey)
                        }
                    Button("", systemImage: "arrow.clockwise") {
                        updateNostrPrivkey(nostrPrivkey: Crypto.privateKey)
                    }
                }
                let privKey = PrivateKey(hex: nostrPrivkey)
                if let privKey = privKey {
                    let keypair = Keypair(privateKey: privKey)
                    let npub = keypair!.publicKey.npub
                    CopyView(item: npub, title: "npub")
                }
                TextField("Subscribe", text: $peerNpub)
                    .onSubmit {
                        UserDefaults.standard.setValue(peerNpub, forKey: "peerNpub")
                        setValues()
                    }
                    .autocorrectionDisabled()
            }
            Section("Signer") {
                SecureField("Encrypted BIP 39 mnemonic", text: $encSigner)
                    .onSubmit {
                        let words = encSigner.components(separatedBy: " ")
                        var wordsNoSpaces: [String] = []
                        for word in words {
                            wordsNoSpaces.append(word.noWhiteSpace)
                        }
                        guard let _ = try? BIP39Mnemonic(words: wordsNoSpaces) else {
                            print("invalid signer")
                            return
                        }
                        guard let encSeed = Crypto.encrypt(encSigner.data(using: .utf8)!) else { return }
                        let dict: [String: Any] = ["encryptedData": encSeed]
                        DataManager.saveEntity(entityName: "Signers", dict: dict) { saved in
                            guard saved else {
                                print("not saved")
                                return
                            }
                            self.encSigner = encSeed.hex
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
            rpcWallets.removeAll()
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
    }
}

struct CopyView: View {
    @State private var copied = false
    let item: String
    let title: String
    
    var body: some View {
        HStack {
            LabeledContent(title, value: item)
                .truncationMode(.middle)
                .lineLimit(1)
            ShareLink("Export", item: item)
            Button("Copy", systemImage: "doc.on.doc") {
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item, forType: .string)
                #elseif os(iOS)
                UIPasteboard.general.string = item
                #endif
                copied = true
            }
            .alert("Copied", isPresented: $copied) {
                Button("OK", role: .cancel) {}
            }
        }
    }
}
