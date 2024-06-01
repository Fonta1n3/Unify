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
    @State private var rpcUser = "Unify"
    @State private var rpcPassword = ""
    @State private var rpcAuth = ""
    @State private var rpcWallet = ""
    @State private var rpcWallets: [String] = []
    @State private var rpcPort = UserDefaults.standard.object(forKey: "rpcPort") as? String ?? "8332"
    @State private var nostrRelay = UserDefaults.standard.object(forKey: "nostrRelay") as? String ?? "wss://relay.damus.io"
    @State private var showBitcoinCoreError = false
    @State private var bitcoinCoreError = ""
    @State private var showNoCredsError = false
    @State private var showInvalidSignerError = false
    @State private var peerNpub = UserDefaults.standard.object(forKey: "peerNpub") as? String ?? ""
    @State private var nostrPrivkey = ""
    @State private var encSigner = ""
    @State private var bitcoinCoreConnected = false
    @State private var tint: Color = .red
    
    
    var body: some View {
        Label("Configuration", systemImage: "gear")
        Form() {
            Section("Bitcoin Core") {
                Label("Bitcoin Core Status", systemImage: "server.rack")
                HStack() {
                    Image(systemName: "circle.fill")
                        .foregroundColor(tint)
                    if bitcoinCoreConnected {
                        Text("Connected")
                    } else {
                        Text("Disconnected")
                    }
                }
                if !bitcoinCoreConnected {
                    Text(bitcoinCoreError)
                }
            }
            Section("RPC Credentials") {
                Label("RPC User", systemImage: "person.circle")
                TextField("User", text: $rpcUser)
                    .onChange(of: rpcUser) {
                        updateRpcUser(rpcUser: rpcUser)
                    }
                Label("RPC Password", systemImage: "ellipsis.rectangle.fill")
                HStack {
                    SecureField("Password", text: $rpcPassword)
                        .onChange(of: rpcPassword) {
                            updateRpcPass(rpcPass: rpcPassword)
                        }
                    Button("", systemImage: "arrow.clockwise") {
                        rpcPassword = Crypto.privateKey
                        updateRpcPass(rpcPass: rpcPassword)
                    }
                }
                Label("RPC Authentication", systemImage: "key.horizontal.fill")
                CopyView(item: rpcAuth)
                Label("RPC Port", systemImage: "network")
                TextField("Port", text: $rpcPort)
                    .onChange(of: rpcPort) {
                        updateRpcPort()
                    }
                    .keyboardType(.numberPad)
            }
            Section("RPC Wallet") {
                Label("Wallet Filename", systemImage: "wallet.pass")
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
                Label("Relay URL", systemImage: "server.rack")
                TextField("Relay", text: $nostrRelay)
                    .onChange(of: nostrRelay) {
                        updateNostrRelay()
                    }
                Label("Private Key", systemImage: "key.horizontal.fill")
                HStack {
                    SecureField("Private key", text: $nostrPrivkey)
                        .onChange(of: nostrPrivkey) {
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
                    Label("Public Key", systemImage: "key.horizontal")
                    CopyView(item: npub)
                }
                Label("Peer Npub", systemImage: "person.line.dotted.person")
                TextField("Subscribe", text: $peerNpub)
                    .onChange(of: peerNpub) {
                        updateNostrPeer()
                    }
            }
            Section("Signer") {
                Label("BIP39 Menmonic", systemImage: "signature")
                HStack() {
                    SecureField("BIP 39 mnemonic", text: $encSigner)
                    Button("Save") {
                        updateSigner()
                    }
                }
                Text("Your signer is encrypted before being saved.")
            }
        }
        .autocorrectionDisabled()
        .formStyle(.grouped)
        .multilineTextAlignment(.leading)
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
        .onSubmit {
            rpcWallets.removeAll()
        }
        .onAppear {
            setValues()
        }
        .alert(bitcoinCoreError, isPresented: $showBitcoinCoreError) {
            Button("OK", role: .cancel) {}
        }
        .alert(CoreDataError.notPresent.localizedDescription, isPresented: $showNoCredsError) {
            Button("OK", role: .cancel) {}
        }
        .alert("Invalid BIP39 Mnemonic.", isPresented: $showInvalidSignerError) {
            Button("OK", role: .cancel) {}
        }
    }
    
    
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
                    //showBitcoinCoreError = true
                    return
                }
                guard let wallets = response as? [String] else {
                    //showBitcoinCoreError = true
                    bitcoinCoreError = BitcoinCoreError.noWallets.localizedDescription
                    return
                }
                bitcoinCoreConnected = true
                tint = .green
                guard wallets.count > 0 else {
                    //showBitcoinCoreError = true
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
                updateRpcAuth()
            }
        }
    }
    
    
    private func updateRpcPass(rpcPass: String) {
        guard let rpcPassData = rpcPass.data(using: .utf8) else { return }
        guard let encryptedRpcPass = Crypto.encrypt(rpcPassData) else { return }
        DataManager.update(entityName: "Credentials", keyToUpdate: "rpcPass", newValue: encryptedRpcPass) { updated in
            if updated {
                self.rpcPassword = rpcPass
                updateRpcAuth()
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
    
    
    private func updateRpcAuth() {
        guard let rpcauthcreds = RPCAuth().generateCreds(username: rpcUser, password: rpcPassword) else {
            print("rpcAuthCreds failing")
            return
        }
        rpcAuth = rpcauthcreds.rpcAuth
    }
    
    
    private func updateRpcPort() {
        UserDefaults.standard.setValue(rpcPort, forKey: "rpcPort")
    }
    
    
    private func updateNostrRelay() {
        UserDefaults.standard.setValue(nostrRelay, forKey: "nostrRelay")
    }
    
    
    private func updateNostrPeer() {
        guard let npub = PublicKey(npub: peerNpub) else { return }
        UserDefaults.standard.setValue(npub, forKey: "peerNpub")
    }
    
    
    private func updateSigner() {
        let words = encSigner.components(separatedBy: " ")
        var wordsNoSpaces: [String] = []
        for word in words {
            wordsNoSpaces.append(word.noWhiteSpace)
        }
        guard let _ = try? BIP39Mnemonic(words: wordsNoSpaces) else {
            encSigner = ""
            showInvalidSignerError = true
            return
        }
        guard let encSeed = Crypto.encrypt(encSigner.data(using: .utf8)!) else { return }
        let dict: [String: Any] = ["encryptedData": encSeed]
        DataManager.saveEntity(entityName: "Signers", dict: dict) { saved in
            guard saved else {
                print("not saved")
                return
            }
            encSigner = encSeed.hex
        }
    }
}

struct CopyView: View {
    @State private var copied = false
    let item: String
    
    var body: some View {
        HStack() {
            Text(item)
                .truncationMode(.middle)
                .lineLimit(1)
                .multilineTextAlignment(.leading)
            ShareLink("", item: item)
            Button("", systemImage: "doc.on.doc") {
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
