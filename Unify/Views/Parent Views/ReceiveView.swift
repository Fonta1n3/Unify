//
//  ReceiveView.swift
//  Pay Join
//
//  Created by Peter Denton on 2/14/24.
//


import NostrSDK
import SwiftUI
import CoreImage.CIFilterBuiltins
import LibWally
#if os(iOS)
import UIKit
#elseif os(macOS)
import Cocoa
#endif


struct ReceiveView: View, DirectMessageEncrypting {
    @State private var amount = ""
    @State private var address = ""
    @State private var npub = ""
    @State private var showCopiedAlert = false
    @State private var peerNpub = ""
    @State private var ourKeypair: Keypair?
    @State private var invoice = ""
    @State private var utxosToPotentiallyConsume: [Utxo] = []
    @State private var showAddOutputView = false
    @State private var utxoToConsume: Utxo?
    @State private var showUtxosView = false
    @State private var originalPsbt: PSBT? = nil
    @State private var hex: String?
    @State private var txSent = false
    @State private var originalPsbtReceived = false
    @State private var payeePubkey: PublicKey?
    @State private var paymentBroadcastBySender = false
    
    private let urlString = UserDefaults.standard.string(forKey: "nostrRelay") ?? "wss://relay.damus.io"
    
    
    var body: some View {
        Spacer()
        
        Label("Receive", systemImage: "arrow.down.forward.circle")
        
        Form() {
            Section("Create Invoice") {
                HStack() {
                    Label("BTC Amount", systemImage: "bitcoinsign.circle")
                        .frame(maxWidth: 200, alignment: .leading)
                    
                    Spacer()
                    
                    TextField("", text: $amount)
                    #if os(iOS)
                        .keyboardType(.decimalPad)
                    #endif
                }
                
                HStack() {
                    Label("Recipient address", systemImage: "arrow.down.forward.circle")
                        .frame(maxWidth: 200, alignment: .leading)
                    
                    Spacer()
                    
                    TextField("", text: $address)
                    #if os(iOS)
                        .keyboardType(.default)
                    #endif
                }
            }
            
            if let amountDouble = Double(amount), amountDouble > 0 && address != "" {                
                let url = "bitcoin:\($address.wrappedValue)?amount=\($amount.wrappedValue)&pj=nostr:\($npub.wrappedValue)"
                
                Section("Payjoin Invoice") {
                        Label("Payjoin over Nostr Invoice", systemImage: "qrcode")
                                                
                        QRView(url: url)
                    
                    HStack {
                        Text(url)
                            .truncationMode(.middle)
                            .lineLimit(1)
                        
                        Button {
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(url, forType: .string)
                            print()
                            #elseif os(iOS)
                            UIPasteboard.general.string = url
                            #endif
                            showCopiedAlert = true
                            
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                    }
                }
                .onAppear {
                    invoice = url
                }
                
                if let hex = hex {
                    Section("Signed Payment (not Payjoin)") {
                        Label("Signed Transaction", systemImage: "doc.plaintext")
                        
                        HStack() {
                            Text(hex)
                                .truncationMode(.middle)
                                .lineLimit(1)
                                .multilineTextAlignment(.leading)
                                .foregroundStyle(.secondary)
                            
                            Button {
                                #if os(macOS)
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(hex, forType: .string)
                                #elseif os(iOS)
                                UIPasteboard.general.string = hex
                                #endif
                                showCopiedAlert = true
                                
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            
                            Button {
                                let p = Send_Raw_Transaction(["hexstring": hex])
                                
                                BitcoinCoreRPC.shared.btcRPC(method: .sendrawtransaction(p)) { (response, errorDesc) in
                                    guard let _ = response as? String else {
                                        print("error sending")
                                        return
                                    }
                                    
                                    self.txSent = true
                                    
                                    guard let encEvent = try? encrypt(content: "Payment broadcast by recipient ✓",
                                                                      privateKey: ourKeypair!.privateKey,
                                                                      publicKey: payeePubkey!) else {
                                        return
                                    }
                                    
                                    StreamManager.shared.writeEvent(content: encEvent, recipientNpub: peerNpub, ourKeypair: ourKeypair!)
                                   
                                   
                                }
                            } label: {
                                Text("Broadcast")
                            }
                        }
                        
                        Text("Optionally broadcast the received payment from the sender instead of creating a Payjoin transaction. In order to create the Payjoin transaction you must add an input and output below.")
                            .foregroundStyle(.primary)
                    }
                }
                
                if showUtxosView, let originalPsbt = originalPsbt {
                    Section("Add Input") {
                            UtxosSelectionView(utxos: utxosToPotentiallyConsume, 
                                               originalPsbt: originalPsbt,
                                               ourKeypair: ourKeypair!,
                                               payeeNpub: peerNpub,
                                               utxoToConsume: $utxoToConsume,
                                               showAddOutputView: $showAddOutputView)
                        
                    }
                    
                    if showAddOutputView, let utxoToConsume = utxoToConsume {
                        Section("Add Output") {
                            AddOutputView(utxo: utxoToConsume, 
                                          originalPsbt: originalPsbt,
                                          ourKeypair: ourKeypair!,
                                          payeeNpub: peerNpub)
                        }
                    }
                }
            }
        }
        .buttonStyle(.bordered)
        .formStyle(.grouped)
        .multilineTextAlignment(.leading)
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
        .onAppear {
            fetchAddress()
            
            guard let keypair = Keypair() else {
                return
            }
            
            ourKeypair = keypair
            npub = ourKeypair!.publicKey.npub
            connectToNostr()
        }
        .alert("Invoice copied ✓", isPresented: $showCopiedAlert) {
            Button("OK", role: .cancel) { }
        }
        .alert("Payment sent ✓", isPresented: $txSent) {
            Button("OK", role: .cancel) {
                StreamManager.shared.closeWebSocket()
                
                invoice = ""
                amount = ""
                address = ""
                npub = ""
                peerNpub = ""
                ourKeypair = nil
                utxosToPotentiallyConsume.removeAll()
                showAddOutputView = false
                utxoToConsume = nil
                showUtxosView = false
                originalPsbt = nil
                hex = nil
                txSent = false
            }
        }
        .alert("Original PSBT received ✓", isPresented: $originalPsbtReceived) {
            Button("OK", role: .cancel) { }
        }
        .alert("Payment broadcast by sender ✓", isPresented: $paymentBroadcastBySender) {
            Button("OK", role: .cancel) { }
        }
    }
    
    private func connectToNostr() {
        StreamManager.shared.openWebSocket(relayUrlString: urlString, peerNpub: nil, p: ourKeypair!.publicKey.hex)
        
        StreamManager.shared.eoseReceivedBlock = { _ in }
        
        StreamManager.shared.errorReceivedBlock = { nostrError in
            print("nostr received error: \(nostrError)")
        }
        
        StreamManager.shared.onDoneBlock = { nostrResponse in
            guard let content = nostrResponse.content else {
                print("nostr response error: \(nostrResponse.errorDesc ?? "unknown error")")
                                
                return
            }
            
            guard let payeePubkeyHex = nostrResponse.pubkey else {
                return
            }
            
            guard let payeePubkey = PublicKey(hex: payeePubkeyHex) else {
                return
            }
            
            self.payeePubkey = payeePubkey
            
            peerNpub = payeePubkey.npub
            
            guard let decryptedMessage = try? decrypt(encryptedContent: content,
                                                      privateKey: ourKeypair!.privateKey,
                                                      publicKey: payeePubkey) else {
                print("failed decrypting")
                return
            }
            
            print("decryptedMessage: \(decryptedMessage)")
            
            if decryptedMessage == "Payment broadcast by sender ✓" {
                // show alert
                paymentBroadcastBySender = true
            }
                        
            guard let decryptedMessageData = decryptedMessage.data(using: .utf8) else {
                print("failed decrypting message data")
                return
            }
            
            guard let dictionary =  try? JSONSerialization.jsonObject(with: decryptedMessageData, options: [.allowFragments]) as? [String: Any] else {
                print("converting to dictionary failed")
                return
            }
            
            let eventContent = EventContent(dictionary)
            
            guard let originalPsbtBase64 = eventContent.psbt else {
                return
            }
            
            originalPsbtReceived = true
            
            let networkSetting = UserDefaults.standard.object(forKey: "network") as? String ?? "Signet"
            var network: Network = .testnet
            
            if networkSetting == "Mainnet" {
                network = .mainnet
            }
            
            guard let psbt = try? PSBT(psbt: originalPsbtBase64, network: network) else {
                return
            }
            
            let invoiceAddress = try! Address(string: address)
            var allInputsSegwit = false
            
            for input in psbt.inputs {
                if input.isSegwit {
                    allInputsSegwit = true
                }
            }
            
            var allOutputsSegwit = false
            var ourInvoiceGetsPaid = false
            
            for output in psbt.outputs {
                if output.txOutput.scriptPubKey.type == .payToWitnessPubKeyHash {
                    allOutputsSegwit = true
                }
                
                if output.txOutput.address! == invoiceAddress.description {
                    ourInvoiceGetsPaid = true
                }
            }
            
            guard allOutputsSegwit, allInputsSegwit, ourInvoiceGetsPaid else {
                return
            }
            
            let finalizeParam = Finalize_Psbt(["psbt": psbt.description])
            
            BitcoinCoreRPC.shared.btcRPC(method: .finalizepsbt(finalizeParam)) { (response, errorDesc) in
                guard let response = response as? [String: Any], 
                        let complete = response["complete"] as? Bool, complete,
                        let hex = response["hex"] as? String else {
                    return
                }
                
                let testmempoolacceptParam = Test_Mempool_Accept(["rawtxs": [hex]])
                
                BitcoinCoreRPC.shared.btcRPC(method: .testmempoolaccept(testmempoolacceptParam)) { (response, errorDesc) in
                    guard let response = response as? [[String: Any]], let allowed = response[0]["allowed"] as? Bool else {
                        return
                    }
                    
                    if allowed {
                        self.hex = hex
                        originalPsbt = psbt
                        showUtxosView = true
                    }
                }
            }
            
            BitcoinCoreRPC.shared.btcRPC(method: .listunspent(List_Unspent([:]))) { (response, errorDesc) in
                guard let utxos = response as? [[String: Any]] else {
                    return
                }
                
                for utxo in utxos {
                    let utxo = Utxo(utxo)
                    if let confs = utxo.confs, confs > 0, 
                        let solvable = utxo.solvable, solvable {
                        if let address = utxo.address,
                            ((try? Address(string: address).scriptPubKey.type == .payToWitnessPubKeyHash)!) {
                            utxosToPotentiallyConsume.append(utxo)
                        }
                    }
                }
            }
        }
    }
    
    
    private func fetchAddress() {
        let p = Get_New_Address(["address_type": "bech32"])
        
        BitcoinCoreRPC.shared.btcRPC(method: .getnewaddress(param: p)) { (response, errorDesc) in
            guard let address = response as? String else {
                return
            }
            
            self.address = address
        }
    }
    
    
    private func encryptedMessage(ourKeypair: Keypair, receiversNpub: String, message: String) -> String? {
        guard let receiversPubKey = PublicKey(npub: receiversNpub) else {
            return nil
        }
        
        guard let encryptedMessage = try? encrypt(content: message,
                                                  privateKey: ourKeypair.privateKey,
                                                  publicKey: receiversPubKey) else {
            return nil
        }
        
        return encryptedMessage
    }
    
}


struct UtxosSelectionView: View {
    @State var selectedUtxo: Utxo? = nil
    
    let utxos: [Utxo]
    let originalPsbt: PSBT
    let ourKeypair: Keypair
    let payeeNpub: String
    @Binding var utxoToConsume: Utxo?
    @Binding var showAddOutputView: Bool
    
    var body: some View {
        List {
            ForEach(utxos, id: \.self) { utxo in
                UtxoSelectionCell(utxo: utxo,
                                  selectedUtxo: self.$selectedUtxo,
                                  utxoToConsume: $utxoToConsume,
                                  showAddOutputView: $showAddOutputView)
            }
            Text("Tap or click a utxo to add it as an additional input.")
                .foregroundStyle(.tertiary)
        }
    }
}


struct UtxoSelectionCell: View {
    let utxo: Utxo
    @Binding var selectedUtxo: Utxo?
    @Binding var utxoToConsume: Utxo?
    @Binding var showAddOutputView: Bool
    
    var body: some View {
        HStack {
            let utxoString = utxo.address! + "\n" + utxo.amount!.btcBalanceWithSpaces
            
            if utxo == selectedUtxo {
                Text(utxoString)
                    .foregroundStyle(.primary)
                    .bold(true)
                
                Spacer()
                
                Image(systemName: "checkmark")
                    .foregroundColor(.accentColor)
                
            } else {
                Text(utxoString)
                    .foregroundStyle(.secondary)
                    .bold(false)
            }
        }
        .onTapGesture {
            self.selectedUtxo = self.utxo
            self.utxoToConsume = self.utxo
            self.showAddOutputView = true
        }
    }
}

struct AddOutputView: View {
    @State private var additionalOutputAddress = ""
    @State private var additionalOutputAmount = ""
    
    let utxo: Utxo
    let originalPsbt: PSBT
    let ourKeypair: Keypair
    let payeeNpub: String
    
    var body: some View {
         HStack() {
             Label("Amount", systemImage: "bitcoinsign.circle")
                 .frame(maxWidth: 200, alignment: .leading)
             
             Spacer()
             
             TextField("", text: $additionalOutputAmount)
             #if os(iOS)
                 .keyboardType(.decimalPad)
             #endif
         }
         
         HStack() {
             Label("Address", systemImage: "arrow.down.forward.circle")
                 .frame(maxWidth: 200, alignment: .leading)
             
             Spacer()
             
             TextField("", text: $additionalOutputAddress)
             #if os(iOS)
                 .keyboardType(.default)
             #endif
         }
        
        if additionalOutputAmount != "", additionalOutputAddress != "" {
                CreateProposalView(utxo: utxo,
                                   originalPsbt: originalPsbt,
                                   ourKeypair: ourKeypair,
                                   payeeNpub: payeeNpub,
                                   additionalOutputAddress: additionalOutputAddress,
                                   additionalOutputAmount: additionalOutputAmount)
        }
    }
}


struct CreateProposalView: View, DirectMessageEncrypting {
    let utxo: Utxo
    let originalPsbt: PSBT
    let ourKeypair: Keypair
    let payeeNpub: String
    let additionalOutputAddress: String
    let additionalOutputAmount: String
    
    var body: some View {
        Button("Create Payjoin Proposal") {
            var inputsForParams: [[String:Any]] = []
            // add our input
            var ourInputDict: [String: Any] = [:]
            ourInputDict["txid"] = utxo.txid
            ourInputDict["vout"] = utxo.vout
            inputsForParams.append(ourInputDict)
            
            // add the outputs
            let ourOutput = [additionalOutputAddress: additionalOutputAmount]
            var outputsForParams: [[String: Any]] = []
            outputsForParams.append(ourOutput)
            
            let options = ["add_inputs": true]
            
            let paramDict:[String: Any] = [
                "inputs": inputsForParams,
                "outputs": outputsForParams,
                "options": options,
                "bip32derivs": false
            ]
            
            let p = Wallet_Create_Funded_Psbt(paramDict)
            
            BitcoinCoreRPC.shared.btcRPC(method: .walletcreatefundedpsbt(param: p)) { (response, errorDesc) in
                guard let response = response as? [String: Any], let receiversPsbt = response["psbt"] as? String else {
                    print("failed creating psbt")
                    return
                }
                
                let param = Join_Psbt(["txs": [receiversPsbt, originalPsbt.description]])
                
                BitcoinCoreRPC.shared.btcRPC(method: .joinpsbts(param)) { (response, errorMessage) in
                    guard let payjoinProposalUnsigned = response as? String else {
                        print("There was an error joining the psbts: \(errorMessage ?? "unknown error")")
                        return
                    }
                    
                    Signer.sign(psbt: payjoinProposalUnsigned, passphrase: nil) { (signedPayjoinProposal, rawTx, errorMessage) in
                        guard let signedPayjoinProposal = signedPayjoinProposal else {
                            print("no signed psbt")
                            return
                        }
                                                
                        let unencryptedContent = [
                            "psbt": signedPayjoinProposal,
                            "parameters": [
//                                "version": 1,
//                                "maxAdditionalFeeContribution": 1000,
//                                "additionalFeeOutputIndex": 0,
//                                "minFeeRate": 10,
//                                "disableOutputSubstitution": true
                            ]
                        ]
                        
                        guard let jsonData = try? JSONSerialization.data(withJSONObject: unencryptedContent, options: .prettyPrinted) else {
                            #if DEBUG
                            print("converting to jsonData failing...")
                            #endif
                            return
                        }
                        
                        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                            return
                        }
                        
                        guard let encPsbtProposal = encryptedMessage(ourKeypair: ourKeypair,
                                                                     receiversNpub: payeeNpub,
                                                                     message: jsonString) else {
                            print("failed encrypting payjoin proposal")
                            return
                        }
                        
                        StreamManager.shared.writeEvent(content: encPsbtProposal, recipientNpub: payeeNpub, ourKeypair: ourKeypair)
                    }
                }
            }
        }
    }
    
    private func encryptedMessage(ourKeypair: Keypair, receiversNpub: String, message: String) -> String? {
        guard let receiversPubKey = PublicKey(npub: receiversNpub) else {
            return nil
        }
        
        guard let encryptedMessage = try? encrypt(content: message,
                                                  privateKey: ourKeypair.privateKey,
                                                  publicKey: receiversPubKey) else {
            return nil
        }
        
        return encryptedMessage
    }
}


struct QRView: View {
    @State private var showCopiedAlert = false
    
    let url: String
    
    #if os(iOS)
    var body: some View {
        let image = generateQRCode(from: url)
        
        HStack() {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
            
            Button {
                UIPasteboard.general.image = image
                showCopiedAlert = true
            } label: {
                Image(systemName: "doc.on.doc")
            }
        }
        .alert("Invoice copied ✓", isPresented: $showCopiedAlert) {
            Button("OK", role: .cancel) { }
        }
    }
    #elseif os(macOS)
    
    var body: some View {
        let image = generateQRCode(from: url)
        
        HStack() {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
            
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
                showCopiedAlert = true
            } label: {
                Image(systemName: "doc.on.doc")
            }
        }
        
        .alert("Invoice copied ✓", isPresented: $showCopiedAlert) {
            Button("OK", role: .cancel) { }
        }
    }
    #endif
    
    #if os(iOS)
    
    
    func generateQRCode(from string: String) -> UIImage {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)

        if let outputImage = filter.outputImage {
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            let output = outputImage.transformed(by: transform)
            
            if let cgImage = context.createCGImage(output, from: output.extent) {
                let uiImage = UIImage(cgImage: cgImage)
                
                let renderedIMage = UIGraphicsImageRenderer(size: uiImage.size, format: uiImage.imageRendererFormat).image { _ in
                    uiImage.draw(in: CGRect(origin: .zero, size: uiImage.size))
                }
                    
                return renderedIMage
            }
        }

        return UIImage(systemName: "xmark.circle") ?? UIImage()
    }
    #elseif os(macOS)
    
    private func generateQRCode(from string: String) -> NSImage {
        let data = url.data(using: .ascii)
        let filter = CIFilter(name: "CIQRCodeGenerator")
        filter!.setValue(data, forKey: "inputMessage")
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let output = filter?.outputImage?.transformed(by: transform)
        
        let colorParameters = [
            "inputColor0": CIColor(color: NSColor.black), // Foreground
            "inputColor1": CIColor(color: NSColor.white) // Background
        ]
        
        let colored = (output!.applyingFilter("CIFalseColor", parameters: colorParameters as [String : Any]))
        let rep = NSCIImageRep(ciImage: colored)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        
        return nsImage
    }
    #endif
}







