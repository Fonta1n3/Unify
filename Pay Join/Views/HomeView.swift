//
//  ContentView.swift
//  Pay Join
//
//  Created by Peter Denton on 2/11/24.
//

import SwiftUI


struct HomeView: View {
    @State private var showingNotSavedAlert = false
    @State private var showingSavedAlert = false
    
    private let names = ["Send", "Receive", "Config"]
    private let views:[any View] = [SendView(), ReceiveView(), ConfigView()]
    
    private func createDefaultCreds() {
        //DataManager.deleteAllData { deleted in
            DataManager.retrieve(entityName: "Credentials", completion: { credentials in
                guard let _ = credentials else {
                    // first create and save encKey to keychain so we can store things encrypted to Core Data
                    guard KeyChain.set(Crypto.privateKeyData(), forKey: "encKey") else {
                        showingNotSavedAlert = true
                        print("unable to save encKey")
                        return
                    }
                    
                    guard let rpcauthcreds = RPCAuth().generateCreds(username: "PayJoin", password: nil) else {
                        showingNotSavedAlert = true
                        return
                    }
                    
                    let rpcpass = rpcauthcreds.password
                    
                    guard let encRpcPass = Crypto.encrypt(rpcpass.data(using: .utf8)!) else {
                        showingNotSavedAlert = true
                        print("unable to encrypt rpcpass")
                        return
                    }
                    
                    
                    let privkey = Crypto.nostrPrivateKey()
                    let pubkey = Crypto.publicKey(privKey: privkey.hex)
                    
                    guard let seed = Crypto.seed() else {
                        showingNotSavedAlert = true
                        return
                    }
                    
                    let arr = seed.split(separator: " ")
                    var encryptionWords = ""
                    for (i, word) in arr.enumerated() {
                        if i < 5 {
                            encryptionWords += word
                            if i < 4 {
                                encryptionWords += " "
                            }
                        }
                    }
                    print("nostr pubkey: \(pubkey)")
                    print("encryptionWords: \(encryptionWords)")
                    
                    
                    guard let encryptedNostrWords = Crypto.encrypt(encryptionWords.data(using: .utf8)!) else {
                        showingNotSavedAlert = true
                        print("unable to encrypt nostr words")
                        return
                    }
                    
                    guard let encryptedNostrPrivateKey = Crypto.encrypt(privkey) else {
                        showingNotSavedAlert = true
                        print("unable to encrypt nostr private key.")
                        return
                    }
                    
                    print("encryptedNostrWords: \(encryptedNostrWords.hex)")
                    print("encryptedNostrPrivateKey: \(encryptedNostrPrivateKey.hex)")
                    
                    let dict: [String:Any] = [
                        "nostrKey": encryptedNostrPrivateKey,
                        "rpcPass": encRpcPass,
                        "nostrEncWords": encryptedNostrWords
                    ]
                                        
                    DataManager.saveEntity(dict: dict) { saved in
                        guard saved else {
                            print("creds not saved")
                            showingNotSavedAlert = true
                            return
                        }
                        print("credentials saved")
                        showingSavedAlert = true
                    }
                                
                    return
                }
            })
       // }
    }
    
    
    var body: some View {
        NavigationView {
            List() {
                NavigationLink {
                    SendView()
                } label: {
                    Text("Send")
                }
                NavigationLink {
                    ReceiveView()
                } label: {
                    Text("Receive")
                }
                NavigationLink {
                    ConfigView()
                } label: {
                    Text("Config")
                }
            }
            Text(Messages.contentViewPrompt.description)
                .onAppear {
                    createDefaultCreds()
                }
        }
        .alert(CoreDataError.notSaved.localizedDescription, isPresented: $showingNotSavedAlert) {
                    Button("OK", role: .cancel) { }
                }
        .alert(Messages.savedCredentials.description, isPresented: $showingSavedAlert) {
                    Button("OK", role: .cancel) { }
                }
    }
}


struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
    }
}
