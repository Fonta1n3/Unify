//
//  Messages.swift
//  Pay Join
//
//  Created by Peter Denton on 3/4/24.
//

import Foundation

enum Messages : String {
    case contentViewPrompt
    case savedCredentials
    
    public var description: String {
        switch self {
            case .contentViewPrompt:
                return "Select Config to export authentication credentials for your bitcoin.conf and to select a wallet."
            
        case .savedCredentials:
            return "Pay Join automatically created and saved default credentials so you can connect your node and encrypt your nostr traffic. Go to Config to view, edit or export them."
        }
    }
}
