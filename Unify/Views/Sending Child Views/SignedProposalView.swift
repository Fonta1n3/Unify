//
//  SignedProposalView.swift
//  Unify
//
//  Created by Peter Denton on 6/18/24.
//

import Foundation
import SwiftUI
import LibWally
import NostrSDK

struct SignedProposalView: View {
    @State private var copied = false
    @State private var proposalPsbtReceived = false
    
    
    let signedRawTx: String
    let invoice: Invoice
    let ourKeypair: Keypair
    let recipientsPubkey: PublicKey
    let psbtProposal: PSBT

    
    var body: some View {
        Form() {
            Section("Signed Tx") {
                Label("Raw transaction", systemImage: "doc.plaintext")
                
                HStack() {
                    Text(signedRawTx)
                        .truncationMode(.middle)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.secondary)
                    
                    Button {
#if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(signedRawTx, forType: .string)
#elseif os(iOS)
                        UIPasteboard.general.string = signedRawTx
#endif
                        copied = true
                        
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }
                
                Label("PSBT", systemImage: "doc.plaintext.fill")
                
                HStack() {
                    Text(psbtProposal.description)
                        .truncationMode(.middle)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.secondary)
                    
                    Button {
#if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(psbtProposal.description, forType: .string)
#elseif os(iOS)
                        UIPasteboard.general.string = psbtProposal.description
#endif
                        copied = true
                        
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }
                ForEach(Array(psbtProposal.inputs.enumerated()), id: \.offset) { (index, input) in
                    let inputAmount = (Double(input.amount!) / 100000000.0).btcBalanceWithSpaces
                    
                    HStack() {
                        Label("Input", systemImage: "arrow.down.right.circle")
                        Spacer()
                        Text(inputAmount)
                    }
                }
                
                ForEach(Array(psbtProposal.outputs.enumerated()), id: \.offset) { (index, output) in
                    let btcAmount = (Double(output.txOutput.amount) / 100000000.0)
                    let outputAmount = btcAmount.btcBalanceWithSpaces
                    
                    if let outputAddress = output.txOutput.address {
                        let bold = outputAddress == invoice.address && btcAmount == invoice.amount!
                        
                        HStack() {
                            Label("Output", systemImage: "arrow.up.right.circle")
                            
                            Spacer()
                            
                            VStack(alignment: .trailing) {
                                if bold {
                                    Text(outputAddress)
                                        .bold(bold)
                                        .foregroundStyle(.primary)
                                    
                                    Text(outputAmount)
                                        .bold(bold)
                                        .foregroundStyle(.primary)
                                    
                                } else {
                                    Text(outputAddress)
                                        .bold(bold)
                                        .foregroundStyle(.secondary)
                                    
                                    Text(outputAmount)
                                        .bold(bold)
                                        .foregroundStyle(.secondary)
                                    
                                }
                            }
                        }
                    }
                }
                
                HStack() {
                    Label("Fee", systemImage: "bitcoinsign")
                    
                    Spacer()
                    
                    Text((Double(psbtProposal.fee!) / 100000000.0).btcBalanceWithSpaces)
                }
                
                NavigationLink {
                    BroadcastView(hexstring: signedRawTx,
                                  invoice: invoice,
                                  ourKeypair: ourKeypair,
                                  recipientsPubkey: recipientsPubkey)
                } label: {
                    Text("Broadcast")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.bordered)
            }
            .buttonStyle(.bordered)
            .alert("Copied ✓", isPresented: $copied) {}
            .alert("Payjoin Proposal PSBT received ✓", isPresented: $proposalPsbtReceived) {
                Button("OK", role: .cancel) {}
            }
        }
        .formStyle(.grouped)
        .multilineTextAlignment(.leading)
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
    }
}
