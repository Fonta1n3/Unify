//
//  Extensions.swift
//  Pay Join
//
//  Created by Peter Denton on 2/11/24.
//

import Foundation

public extension Data {
    var hex: String {
        return reduce("") {$0 + String(format: "%02x", $1)}
    }
    
    var urlSafeB64String: String {
        return self.base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-")
    }
}

public extension String {
    var noWhiteSpace: String {
        let components = self.components(separatedBy: .whitespacesAndNewlines)
        return components.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

