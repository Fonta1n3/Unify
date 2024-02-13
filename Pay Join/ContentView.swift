//
//  ContentView.swift
//  Pay Join
//
//  Created by Peter Denton on 2/11/24.
//

import SwiftUI


struct ContentView: View {
    private let names = ["Home", "Config"]
    private let views:[any View] = [HomeView(), ConfigView()]
    @State private var selection: String? = "Home"
    
    private func createDefaultCreds() {
        print("createDefaultCreds")
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
                    HomeView()
                } label: {
                    Text("Home")
                }
                NavigationLink {
                    ConfigView()
                } label: {
                    Text("Config")
                }
            }
            Text("Select Home to start Pay Join or Config to export credentials.")
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
