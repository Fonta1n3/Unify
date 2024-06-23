//
//  ContentView.swift
//  Pay Join
//
//  Created by Peter Denton on 2/11/24.
//

import SwiftUI
import NostrSDK

struct HomeView: View {
    @State private var showNotSavedAlert = false
    @State private var showSavedAlert = false
    
    private let names = ["Receive", "Send", "History", "Config"]
    private let views: [any View] = [ReceiveView(), SendView(), HistoryView(), ConfigView()]
    
    private func createDefaultCreds() {
        DataManager.retrieve(entityName: "Credentials") { credentials in
            guard let _ = credentials else {
                
                guard KeyChain.set(Crypto.privKeyData(), forKey: "encKey") else {
                    showNotSavedAlert = true
                    return
                }
                
                guard let rpcauthcreds = RPCAuth().generateCreds(username: "Unify", password: nil) else {
                    showNotSavedAlert = true
                    return
                }
                
                UserDefaults.standard.setValue("38332", forKey: "rpcPort")
                UserDefaults.standard.setValue("Signet", forKey: "network")
                
                let rpcpass = rpcauthcreds.password
                
                guard let encRpcPass = Crypto.encrypt(rpcpass.data(using: .utf8)!) else {
                    showNotSavedAlert = true
                    return
                }
                                
                let dict: [String:Any] = [
                    "rpcPass": encRpcPass,
                    "rpcUser": "Unify"
                ]
                
                saveCreds(dict: dict)
                
                return
            }
        }
    }
    
    private func saveCreds(dict: [String: Any]) {
        DataManager.saveEntity(entityName: "Credentials", dict: dict) { saved in
            guard saved else {
                showNotSavedAlert = true
                return
            }
            
            showSavedAlert = true
        }
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
                    HistoryView()
                } label: {
                    Text("History")
                }
                NavigationLink {
                    ConfigView()
                } label: {
                    Text("Config")
                }
            }
            Text(Messages.contentViewPrompt.description)
            
        }
        .preferredColorScheme(.dark)
        .alert(CoreDataError.notSaved.localizedDescription, isPresented: $showNotSavedAlert) {
            Button("OK", role: .cancel) { }
        }
        .onAppear {
            DispatchQueue.global(qos: .background).async {
                createDefaultCreds()
            }
        }
    }
}


struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
    }
}
