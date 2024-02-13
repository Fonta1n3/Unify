//
//  HomeView.swift
//  Pay Join
//
//  Created by Peter Denton on 2/13/24.
//

import SwiftUI

struct HomeView: View {
    var body: some View {
        List() {
            
        }
        .onAppear {
            makeRPCCall()
        }
    }
    
    private func makeRPCCall() {
        print("makeRPCCall")
        let unfinalizedSignedPsbt = "cHNidP8BAHMCAAAAAY8nutGgJdyYGXWiBEb45Hoe9lWGbkxh/6bNiOJdCDuDAAAAAAD+////AtyVuAUAAAAAF6kUHehJ8GnSdBUOOv6ujXLrWmsJRDCHgIQeAAAAAAAXqRR3QJbbz0hnQ8IvQ0fptGn+votneofTAAAAAAEBIKgb1wUAAAAAF6kU3k4ekGHKWRNbA1rV5tR5kEVDVNCHAQQWABTHikVyU1WCjVZYB03VJg1fy2mFMCICAxWawBqg1YdUxLTYt9NJ7R7fzws2K09rVRBnI6KFj4UWRzBEAiB8Q+A6dep+Rz92vhy26lT0AjZn4PRLi8Bf9qoB/CMk0wIgP/Rj2PWZ3gEjUkTlhDRNAQ0gXwTO7t9n+V14pZ6oljUBIgYDFZrAGqDVh1TEtNi300ntHt/PCzYrT2tVEGcjooWPhRYYSFzWUDEAAIABAACAAAAAgAEAAAAAAAAAAAEAFgAURvYaK7pzgo7lhbSl/DeUan2MxRQiAgLKC8FYHmmul/HrXLUcMDCjfuRg/dhEkG8CO26cEC6vfBhIXNZQMQAAgAEAAIAAAACAAQAAAAEAAAAAAA=="
        
        let originalPsbt = "cHNidP8BAHMCAAAAAY8nutGgJdyYGXWiBEb45Hoe9lWGbkxh/6bNiOJdCDuDAAAAAAD+////AtyVuAUAAAAAF6kUHehJ8GnSdBUOOv6ujXLrWmsJRDCHgIQeAAAAAAAXqRR3QJbbz0hnQ8IvQ0fptGn+votneofTAAAAAAEBIKgb1wUAAAAAF6kU3k4ekGHKWRNbA1rV5tR5kEVDVNCHAQcXFgAUx4pFclNVgo1WWAdN1SYNX8tphTABCGsCRzBEAiB8Q+A6dep+Rz92vhy26lT0AjZn4PRLi8Bf9qoB/CMk0wIgP/Rj2PWZ3gEjUkTlhDRNAQ0gXwTO7t9n+V14pZ6oljUBIQMVmsAaoNWHVMS02LfTSe0e388LNitPa1UQZyOihY+FFgABABYAFEb2Giu6c4KO5YW0pfw3lGp9jMUUAAA="
        
        let payjoinProposal = "cHNidP8BAJwCAAAAAo8nutGgJdyYGXWiBEb45Hoe9lWGbkxh/6bNiOJdCDuDAAAAAAD+////jye60aAl3JgZdaIERvjkeh72VYZuTGH/ps2I4l0IO4MBAAAAAP7///8CJpW4BQAAAAAXqRQd6EnwadJ0FQ46/q6NcutaawlEMIcACT0AAAAAABepFHdAltvPSGdDwi9DR+m0af6+i2d6h9MAAAAAAAEBIICEHgAAAAAAF6kUyPLL+cphRyyI5GTUazV0hF2R2NWHAQcXFgAUX4BmVeWSTJIEwtUb5TlPS/ntohABCGsCRzBEAiBnu3tA3yWlT0WBClsXXS9j69Bt+waCs9JcjWtNjtv7VgIge2VYAaBeLPDB6HGFlpqOENXMldsJezF9Gs5amvDQRDQBIQJl1jz1tBt8hNx2owTm+4Du4isx0pmdKNMNIjjaMHFfrQAAAA=="
        
        let payjoinProposalFilledWithSendersInformation = "cHNidP8BAJwCAAAAAo8nutGgJdyYGXWiBEb45Hoe9lWGbkxh/6bNiOJdCDuDAAAAAAD+////jye60aAl3JgZdaIERvjkeh72VYZuTGH/ps2I4l0IO4MBAAAAAP7///8CJpW4BQAAAAAXqRQd6EnwadJ0FQ46/q6NcutaawlEMIcACT0AAAAAABepFHdAltvPSGdDwi9DR+m0af6+i2d6h9MAAAAAAQEgqBvXBQAAAAAXqRTeTh6QYcpZE1sDWtXm1HmQRUNU0IcBBBYAFMeKRXJTVYKNVlgHTdUmDV/LaYUwIgYDFZrAGqDVh1TEtNi300ntHt/PCzYrT2tVEGcjooWPhRYYSFzWUDEAAIABAACAAAAAgAEAAAAAAAAAAAEBIICEHgAAAAAAF6kUyPLL+cphRyyI5GTUazV0hF2R2NWHAQcXFgAUX4BmVeWSTJIEwtUb5TlPS/ntohABCGsCRzBEAiBnu3tA3yWlT0WBClsXXS9j69Bt+waCs9JcjWtNjtv7VgIge2VYAaBeLPDB6HGFlpqOENXMldsJezF9Gs5amvDQRDQBIQJl1jz1tBt8hNx2owTm+4Du4isx0pmdKNMNIjjaMHFfrQABABYAFEb2Giu6c4KO5YW0pfw3lGp9jMUUIgICygvBWB5prpfx61y1HDAwo37kYP3YRJBvAjtunBAur3wYSFzWUDEAAIABAACAAAAAgAEAAAABAAAAAAA="
        
        //BitcoinCoreRPC
        DataManager.retrieve(entityName: "Credentials", completion: { credentials in
            guard let credentials = credentials else {
                print("no credentials")
                return
            }
            
            guard let rpcpass = credentials["rpcpass"] as? Data else {
                print("no rpcpass")
                return
            }
            
            guard let rpcauthcreds = RPCAuth().generateCreds(username: "PayJoin", password: String(data: rpcpass, encoding: .utf8)) else {
                print("unable to derive rpcauth.")
                return
            }
            
            let p: Decode_Psbt = .init(["psbt": unfinalizedSignedPsbt])
            
            BitcoinCoreRPC.shared.btcRPC(method: .decodepsbt(param: p)) { (response, errorDesc) in
                print("response: \(response)")
            }
        })
    }
}
