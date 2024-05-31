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
    
    private let names = ["Receive", "Send", "Config"]
    private let views: [any View] = [ReceiveView(), SendView(), ConfigView()]
    
    private func createDefaultCreds() {
        //DataManager.deleteAllData(entityName: "Credentials") { deleted in
            DataManager.retrieve(entityName: "Credentials", completion: { credentials in
                guard let _ = credentials else {
                    // first create and save encKey to keychain so we can store things encrypted to Core Data
                    if KeyChain.getData("encKey") == nil {
                        guard KeyChain.set(Crypto.privateKeyData(), forKey: "encKey") else {
                            showingNotSavedAlert = true
                            print("unable to save encKey")
                            return
                        }
                    }
                    
                    guard let rpcauthcreds = RPCAuth().generateCreds(username: "Unify", password: nil) else {
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
                    
                    guard let encryptedNostrPrivateKey = Crypto.encrypt(privkey) else {
                        showingNotSavedAlert = true
                        print("unable to encrypt nostr private key.")
                        return
                    }
                    
                    let dict: [String:Any] = [
                        "nostrPrivkey": encryptedNostrPrivateKey,
                        "rpcPass": encRpcPass,
                        "rpcUser": "PayJoin"
                    ]
                    
                    DataManager.saveEntity(entityName: "Credentials", dict: dict) { saved in
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
        //}
    }
    
    
    var body: some View {
        NavigationView {
            List() {
                NavigationLink {
                    ReceiveView()
                } label: {
                    Text("Receive")
                }
                NavigationLink {
                    SendView()
                } label: {
                    Text("Send")
                }
                NavigationLink {
                    ConfigView()
                } label: {
                    Text("Config")
                }
            }
            Text(Messages.contentViewPrompt.description)
            
        }
        .alert(CoreDataError.notSaved.localizedDescription, isPresented: $showingNotSavedAlert) {
            Button("OK", role: .cancel) { }
        }
        .alert(Messages.savedCredentials.description, isPresented: $showingSavedAlert) {
            Button("OK", role: .cancel) { }
        }
        .onAppear {
            createDefaultCreds()
        }
    }
}


struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
    }
}
