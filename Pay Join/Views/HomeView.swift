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
        print("createDefaultCreds")
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
                    
                    guard let encryptedNostrPrivateKey = Crypto.encrypt(privkey) else {
                        showingNotSavedAlert = true
                        print("unable to encrypt nostr private key.")
                        return
                    }
                    
                    //print("encryptedNostrWords: \(encryptedNostrWords.hex)")
                    print("encryptedNostrPrivateKey: \(encryptedNostrPrivateKey.hex)")
                    
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
                
//                if let _ = UserDefaults.standard.object(forKey: "peerNpub") as? String,
//                    let nostrRelay = UserDefaults.standard.object(forKey: "nostrRelay") as? String {
//                    connectAndSubscribe(urlString: nostrRelay)
//                }
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
            
            DataManager.retrieve(entityName: "Signers") { signer in
                guard let signer = signer else {
                    print("no signer")
                    let words = "smile pool offer seat betray sponsor build genius vault follow glad near"
                    let wordData = words.data(using: .utf8)!
                    guard let encryptedWords = Crypto.encrypt(wordData) else { return }
                    DataManager.saveEntity(entityName: "Signers", dict: ["encryptedData": encryptedWords]) { saved in
                        print("encryptedSigner saved: \(saved)")
                    }
                    return
                }
                
                guard let encSigner = signer["encryptedData"] as? Data else {
                    print("no signer")
//                    let words = "smile pool offer seat betray sponsor build genius vault follow glad near"
//                    let wordData = words.data(using: .utf8)!
//                    guard let encryptedWords = Crypto.encrypt(wordData) else { return }
//                    DataManager.saveEntity(entityName: "Signer", dict: ["encryptedData": encryptedWords]) { saved in
//                        print("encryptedSigner saved: \(saved)")
//                    }
                    return
                }
                
                print("encSigner: \(encSigner)")
            }
            
            
        }
    }
    
    
//    private func connectAndSubscribe(urlString: String) {
//        StreamManager.shared.openWebSocket(relayUrlString: urlString)
//        
//        StreamManager.shared.eoseReceivedBlock = { _ in
//            print("eos received :)")
//        }
//        
//        StreamManager.shared.errorReceivedBlock = { nostrError in
//            print("nostr received error")
//        }
//        
//        StreamManager.shared.onDoneBlock = { nostrResponse in
//            if let errDesc = nostrResponse.errorDesc {
//                if errDesc != "" {
//                    print("nostr response error: \(nostrResponse.errorDesc!)")
//                } else {
//                    if nostrResponse.response != nil {
//                        print("nostr response: \(nostrResponse.response!)")
//                    }
//                }
//            } else {
//                if nostrResponse.response != nil {
//                    print("nostr response: \(nostrResponse.response!)")
//                }
//            }
//        }
//    }
}


struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
    }
}
