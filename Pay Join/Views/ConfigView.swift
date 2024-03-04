//
//  ConfigView.swift
//  Pay Join
//
//  Created by Peter Denton on 2/13/24.
//

import SwiftUI
import UniformTypeIdentifiers

struct ConfigView: View {
    @State private var rpcAuth = ""
    @State private var rpcWallet = ""
    @State private var rpcWallets: [String] = []
    @State private var rpcPort = UserDefaults.standard.object(forKey: "rpcPort") as? String ?? "8332"
    @State private var nostrEncryptionWords = ""
    @State private var showBitcoinCoreError = false
    @State private var bitcoinCoreError = ""
    @State private var showNoCredsError = false
    @State private var showCopiedAlert = false
    
    
    func setValues() {
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
            
            guard let encNostrWords = credentials["nostrEncWords"] as? Data else {
                print("no encNostrWords")
                return
            }
            
            guard let decryptedNostrWords = Crypto.decrypt(encNostrWords) else {
                print("no decrypted nostr words")
                return
            }
            
            nostrEncryptionWords = String(data: decryptedNostrWords, encoding: .utf8)!
            
            guard let rpcauthcreds = RPCAuth().generateCreds(username: "PayJoin", password: rpcPass) else { return }
            
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
                
                guard let wallets = response as? [String], wallets.count > 0 else {
                    showBitcoinCoreError = true
                    bitcoinCoreError = BitcoinCoreError.noWallets.localizedDescription
                    return
                }
                
                for wallet in wallets {
                    rpcWallets.append(wallet)
                }
            }
        })
    }
    
    var body: some View {
        Form() {
            Section("RPC Authentication") {
                HStack {
                    TextField("", text: $rpcAuth)
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
