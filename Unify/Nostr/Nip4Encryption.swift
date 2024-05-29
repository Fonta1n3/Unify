////
////  Nip4Encryption.swift
////  Pay Join
////
////  Created by Peter Denton on 3/13/24.
////
//
//import CryptoKit
//import Foundation
//import secp256k1
//
//class Nip4Encryption {
//    
//    let ourPrivateKey = ""
//    let theirPublicKey = ""
//    
//    
//    private init() {}
//    
//    func createEncryptedDm() {
//        let sharedPoint = secp.getSharedSecret(ourPrivateKey, "02" + theirPublicKey)
//        let sharedX = sharedPoint[1..<33]
//        let iv = Data.random(count: 16)
//        let cipher = try! AES.CBC(
//            key: sharedX,
//            iv: iv
//        )
//        let encryptedMessage = cipher.update(text, with: .utf8) + cipher.finalData
//        let ivBase64 = iv.base64EncodedString()
//        let event: [String: Any] = [
//            "pubkey": ourPubKey,
//            "created_at": Int(Date().timeIntervalSince1970),
//            "kind": 4,
//            "tags": [["p", theirPublicKey]],
//            "content": encryptedMessage.base64EncodedString() + "?iv=" + ivBase64
//        ]
//    }
//    
//
//    
//    
//}
