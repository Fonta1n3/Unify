//
//  ContentView.swift
//  Pay Join
//
//  Created by Peter Denton on 2/11/24.
//

import SwiftUI


struct ContentView: View {
    private let names = ["Send", "Receive", "Config"]
    private let views:[any View] = [SendView(), ReceiveView(), ConfigView()]
    
    private func createDefaultCreds() {
        DataManager.retrieve(entityName: "Credentials", completion: { credentials in
            guard let credentials = credentials else {
                guard let rpcauthcreds = RPCAuth().generateCreds(username: "PayJoin", password: nil) else { return }
                let rpcpass = rpcauthcreds.password
                let p: [String: Any] = ["rpcpass": rpcpass.data(using: .utf8)!]
                DataManager.saveEntity(dict: p) { saved in
                    guard saved else {
                        print("not saved")
                        return
                    }
                    print("rpcpass saved")
                }
                return
            }
        })
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
            Text("Select Config to export authentication credentials for your bitcoin.conf.")
                .onAppear {
                    createDefaultCreds()
                }
        }
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
