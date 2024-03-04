//
//  Crypto.swift
//  Pay Join
//
//  Created by Peter Denton on 2/11/24.
//

import Foundation
import RNCryptor
import secp256k1
import CryptoKit
import LibWally

class Crypto {
//    static func sha256hash(_ text: String) -> String {
//        let digest = SHA256.hash(data: text.utf8)
//        
//        return digest.map { String(format: "%02hhx", $0) }.joined()
//    }
    
    static func encrypt(_ data: Data) -> Data? {
        guard let key = KeyChain.getData("encKey") else { print("no encKey saved"); return nil }
        
        return try? ChaChaPoly.seal(data, using: SymmetricKey(data: key)).combined
    }
    
    static func decrypt(_ data: Data) -> Data? {
        guard let key = KeyChain.getData("encKey"),
            let box = try? ChaChaPoly.SealedBox.init(combined: data) else {
                return nil
        }
        
        return try? ChaChaPoly.open(box, using: SymmetricKey(data: key))
    }
    
    static func sha256hash(_ data: Data) -> Data {
        let digest = SHA256.hash(data: data)
        
        return Data(digest)
    }
    
    static func seed() -> String? {
        var words: String?
        let bytesCount = 32
        var randomBytes = [UInt8](repeating: 0, count: bytesCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytesCount, &randomBytes)
        
        if status == errSecSuccess {
            var data = Crypto.sha256hash(Crypto.sha256hash(Crypto.sha256hash(Data(randomBytes))))
            data = data.subdata(in: Range(0...15))
            let entropy = BIP39Mnemonic.Entropy(data)
            if let mnemonic = try? BIP39Mnemonic(entropy: entropy) {
                words = mnemonic.description
            }
        }
        
        return words
    }
    
    static func encryptNostr(_ content: Data, _ password: String) -> Data? {
        return RNCryptor.encrypt(data: content, withPassword: password.replacingOccurrences(of: " ", with: ""))
    }

    static func decryptNostr(_ content: Data, _ password: String) -> Data? {
        return try? RNCryptor.decrypt(data: content, withPassword: password.replacingOccurrences(of: " ", with: ""))
    }
    
    static var randomKey: String {
        let privateKey = try! secp256k1.KeyAgreement.PrivateKey()
        let publicKey = privateKey.publicKey
        return publicKey.rawRepresentation.hex
    }
    
    static var privateKey: String {
        return try! secp256k1.KeyAgreement.PrivateKey().rawRepresentation.hex
    }
    
    static func privateKeyData() -> Data {
        return P256.Signing.PrivateKey().rawRepresentation
    }
    
    static func nostrPrivateKey() -> Data {
        return P256.Signing.PrivateKey().rawRepresentation
    }
    
    static func publicKey(privKey: String) -> String {
        let privateKey = try! secp256k1.KeyAgreement.PrivateKey(rawRepresentation: hex_decode(privKey) ?? [])
        return privateKey.publicKey.rawRepresentation.hex
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
