//
//  Crypto.swift
//  Pay Join
//
//  Created by Peter Denton on 2/11/24.
//

import Foundation
import RNCryptor
import secp256k1

class Crypto {
    static func encryptNostr(_ content: Data, _ password: String) -> Data? {
        return RNCryptor.encrypt(data: content, withPassword: password.replacingOccurrences(of: " ", with: ""))
    }

    static func decryptNostr(_ content: Data, _ password: String) -> Data? {
        return try? RNCryptor.decrypt(data: content, withPassword: password.replacingOccurrences(of: " ", with: ""))
    }
    
    static var randomKey: String {
        let privateKey = try! secp256k1.KeyAgreement.PrivateKey()
        let publicKey = privateKey.publicKey
        return publicKey.dataRepresentation.hex
    }
    
    static var privateKey: String {
        return try! secp256k1.KeyAgreement.PrivateKey().rawRepresentation.hex
    }
    
    static func publicKey(privKey: String) -> String {
        let privateKey = try! secp256k1.KeyAgreement.PrivateKey(dataRepresentation: hex_decode(privKey) ?? [])
        return privateKey.publicKey.dataRepresentation.hex
    }
    
    static func hex_decode(_ str: String) -> [UInt8]? {
        if str.count == 0 {
            return nil
        }
        var ret: [UInt8] = []
        let chars = Array(str.utf8)
        var i: Int = 0
        for c in zip(chars, chars[1...]) {
            i += 1

            if i % 2 == 0 {
                continue
            }

            guard let c1 = char_to_hex(c.0) else {
                return nil
            }

            guard let c2 = char_to_hex(c.1) else {
                return nil
            }

            ret.append((c1 << 4) | c2)
        }

        return ret
    }
    
    static func char_to_hex(_ c: UInt8) -> UInt8? {
        // 0 && 9
        if (c >= 48 && c <= 57) {
            return c - 48 // 0
        }
        // a && f
        if (c >= 97 && c <= 102) {
            return c - 97 + 10;
        }
        // A && F
        if (c >= 65 && c <= 70) {
            return c - 65 + 10;
        }
        return nil;
    }
}
