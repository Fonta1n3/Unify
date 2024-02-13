//
//  ConfigView.swift
//  Pay Join
//
//  Created by Peter Denton on 2/13/24.
//

import SwiftUI


struct ConfigView: View {
    @State private var rpcAuth = ""
    @State private var rpcWallet = ""
    @State private var rpcWallets: [String] = []
    @State private var rpcPort = UserDefaults.standard.object(forKey: "rpcPort") as? String ?? "8332"
    
    
    func setValues() {
        print("setValues")
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
                }
                return
            }
            
            guard let rpcpass = credentials["rpcpass"] as? Data else {
                print("no rpc creds")
                return
            }
            
            guard let rpcauthcreds = RPCAuth().generateCreds(username: "PayJoin", password: String(data: rpcpass, encoding: .utf8)) else { return }
            rpcAuth = rpcauthcreds.rpcAuth
            if let walletName = UserDefaults.standard.object(forKey: "walletName") as? String {
                rpcWallet = walletName
            }
            
            // need to fetch wallets
            BitcoinCoreRPC.shared.btcRPC(method: .listwallets) { (response, errorDesc) in
                guard errorDesc == nil else {
                    print("errorDesc: \(errorDesc)")
                    rpcWallets.removeAll()
                    return
                }
                
                guard let wallets = response as? [String] else { return }
                
                for wallet in wallets {
                    rpcWallets.append(wallet)
                }
            }
        })
    }
    
    var body: some View {
        Form() {
            Section("RPC Authentication") {
                TextField("rpcauth=PayJoin:...", text: $rpcAuth)
            }
            Section("RPC Port") {
                TextField("8332", text: $rpcPort)
                    .onSubmit {
                        UserDefaults.standard.setValue(rpcPort, forKey: "rpcPort")
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
            
        }
        .formStyle(.grouped)
        .multilineTextAlignment(.leading)
        .textFieldStyle(.roundedBorder)
        .frame(width: 700, height: nil, alignment: .leading)
        .padding()
        .onSubmit {
            setValues()
        }
        .onAppear {
            setValues()
        }
    }
}
