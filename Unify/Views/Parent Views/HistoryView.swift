//
//  HistoryView.swift
//  Unify
//
//  Created by Peter Denton on 6/17/24.
//

import Foundation
import SwiftUI

struct HistoryView: View {
    @State private var transactions: [Transaction] = []
    @State private var copied = false
        
    var body: some View {
        Form() {
            List() {
                ForEach(transactions, id: \.self) { transaction in
                    let amount = transaction.amount.btcBalanceWithSpaces
                                        
                    Section("Transaction") {
                        HStack() {
                            if transaction.category == "send" {
//                                Label("Category", systemImage: "arrow.up.right.circle")
//                                    .foregroundStyle(.secondary)
//                                    .tint(.red)
                                Label {
                                    Text("Category")
                                        .foregroundStyle(.secondary)
                                } icon: {
                                    Image(systemName: "arrow.up.right.circle")
                                        .foregroundColor(.red)
                                }
                                
                               
                            } else {
                                Label {
                                    Text("Category")
                                        .foregroundStyle(.secondary)
                                } icon: {
                                    Image(systemName: "arrow.down.forward.circle")
                                        .foregroundColor(.green)
                                }
                            }
                            
                            Spacer()
                            
                            Text(transaction.category.localizedCapitalized)
                                .foregroundStyle(.primary)
                        }
                        
                        HStack() {
                            Label {
                                Text("Amount")
                                    .foregroundStyle(.secondary)
                            } icon: {
                                Image(systemName: "bitcoinsign.circle")
                                    .foregroundColor(.blue)
                            }
                            
                            Spacer()
                            
                            if transaction.category == "send" {
                                Text("- " + amount)
                                    .foregroundStyle(.primary)
                            } else {
                                Text(amount)
                                    .foregroundStyle(.primary)
                            }
                        }
                        
                        if let fee = transaction.fee {
                            HStack() {
                                Label {
                                    Text("Fee")
                                        .foregroundStyle(.secondary)
                                } icon: {
                                    Image(systemName: "bitcoinsign.arrow.circlepath")
                                        .foregroundColor(.blue)
                                }
                                
                                Spacer()
                                
                                Text(fee.btcBalanceWithSpaces)
                            }
                        }
                                                
                        HStack() {
                            Label {
                                Text("Confirmations")
                                    .foregroundStyle(.secondary)
                            } icon: {
                                Image(systemName: "square.stack")
                                    .foregroundColor(.blue)
                            }
                            
                            Spacer()
                            
                            Text("\(transaction.confirmations)")
                        }
                        
                        HStack() {
                            Label {
                                Text("Date")
                                    .foregroundStyle(.secondary)
                            } icon: {
                                Image(systemName: "calendar.badge.clock")
                                    .foregroundColor(.blue)
                            }
                            
                            Spacer()
                            
                            Text(transaction.date)
                        }
                        
                        HStack() {
                            Label {
                                Text("ID")
                                    .foregroundStyle(.secondary)
                            } icon: {
                                Image(systemName: "person.text.rectangle")
                                    .foregroundColor(.blue)
                            }
                            
                            Spacer()
                            
                            Text(transaction.txid)
                                .frame(width: 200)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            
                            Button {
                                #if os(macOS)
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(transaction.txid, forType: .string)
                                #elseif os(iOS)
                                UIPasteboard.general.string = transaction.txid
                                #endif
                                copied = true
                                
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .alert("Txid copied ✓", isPresented: $copied) {}
                        }
                    }
                }
            }
        }
        .onAppear {
            listTransactions()
        }
    }

    
    
    private func listTransactions() {
        let p = List_Transactions(["count": 100])
        
        BitcoinCoreRPC.shared.btcRPC(method: .listtransactions(p)) { (response, errorDesc) in
            guard let transactions = response as? [[String: Any]] else {
                return
            }
            
            for transaction in transactions {
                let tx = Transaction(transaction)
                
                self.transactions.append(tx)
            }
        }
    }
}
