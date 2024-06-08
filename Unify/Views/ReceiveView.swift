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
    @State private var peerNpub = UserDefaults.standard.object(forKey: "peerNpub") as? String ?? ""
    @State private var ourKeypair: Keypair?
    @State private var invoice = ""
    @State private var utxosToPotentiallyConsume: [Utxo] = []
    @State private var showAddOutputView = false
    @State private var utxoToConsume: Utxo?
    @State private var showUtxosView = false
    @State private var originalPsbt: PSBT? = nil
    
    private let urlString = UserDefaults.standard.string(forKey: "nostrRelay") ?? "wss://relay.damus.io"
    
    
    var body: some View {
        Spacer()
        
        Label("Receive", systemImage: "arrow.down.forward.circle")
        
        Form() {
            Section("Create Invoice") {
                HStack() {
                    Label("BTC Amount", systemImage: "bitcoinsign.circle")
                    
                    TextField("", text: $amount)
                    #if os(iOS)
                        .keyboardType(.decimalPad)
                    #endif
                }
                
                HStack() {
                    Label("Recipient address", systemImage: "arrow.down.forward.circle")
                    
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
                
                Section("Request") {
                    TextField("Peer npub", text: $peerNpub)
                    
                    Button("Request via nostr") {
                        if let _ = PublicKey(npub: peerNpub) {
                            connectToNostr()
                        }
                    }
                    .disabled(PublicKey(npub: peerNpub) == nil)
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
            
            peerNpub = UserDefaults.standard.object(forKey: "peerNpub") as? String ?? ""
            
            DataManager.retrieve(entityName: "Credentials") { dict in
                guard let dict = dict, let encPrivKey = dict["nostrPrivkey"] as? Data else {
                    return
                }
                
                guard let decPrivkey = Crypto.decrypt(encPrivKey) else { return }
                
                ourKeypair = Keypair(privateKey: PrivateKey(dataRepresentation: decPrivkey)!)!
                npub = ourKeypair!.publicKey.npub
            }
        }
        .alert("Invoice copied ✓", isPresented: $showCopiedAlert) {
            Button("OK", role: .cancel) { }
        }
    }
    
    private func connectToNostr() {
        guard let payeePubkey = PublicKey(npub: peerNpub) else {
            return
        }
        
        StreamManager.shared.openWebSocket(relayUrlString: urlString)
        
        StreamManager.shared.eoseReceivedBlock = { _ in
            guard let encInvoice = encryptedMessage(ourKeypair: ourKeypair!,
                                                    receiversNpub: peerNpub,
                                                    message: self.invoice) else {
                return
            }
            
            StreamManager.shared.writeEvent(content: encInvoice,
                                            recipientNpub: peerNpub)
        }
        
        StreamManager.shared.errorReceivedBlock = { nostrError in
            print("nostr received error: \(nostrError)")
        }
        
        StreamManager.shared.onDoneBlock = { nostrResponse in
            guard let response = nostrResponse.response as? String else {
                print("nostr response error: \(nostrResponse.errorDesc ?? "unknown error")")
                return
            }
            
            guard let decryptedMessage = try? decrypt(encryptedContent: response,
                                                      privateKey: ourKeypair!.privateKey,
                                                      publicKey: payeePubkey) else {
                print("failed decrypting")
                return
            }
            
            guard let decryptedMessageData = decryptedMessage.data(using: .utf8) else {
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
            
            guard let psbt = try? PSBT(psbt: originalPsbtBase64, network: .testnet) else {
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
            
        }
        .frame(minHeight: CGFloat(utxos.count) * 40)
    }
}


struct UtxoSelectionCell: View {
    let utxo: Utxo
    @Binding var selectedUtxo: Utxo?
    @Binding var utxoToConsume: Utxo?
    @Binding var showAddOutputView: Bool
    
    var body: some View {
        HStack {
            Text(utxo.address! + ":" + utxo.amount!.description)
                .bold(utxo == selectedUtxo)
            
            Spacer()
            
            if utxo == selectedUtxo {
                Image(systemName: "checkmark")
                    .foregroundColor(.accentColor)
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
        TextField("Address", text: $additionalOutputAddress)
        
        TextField("Amount", text: $additionalOutputAmount)
        
        if additionalOutputAmount != "", additionalOutputAmount != "" {
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
                            "psbt:": signedPayjoinProposal,
                            "parameters": [
                                "version": 1,
                                "maxAdditionalFeeContribution": 1000,
                                "additionalFeeOutputIndex": 0,
                                "minFeeRate": 10,
                                "disableOutputSubstitution": true
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
                        
                        StreamManager.shared.writeEvent(content: encPsbtProposal, recipientNpub: payeeNpub)
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
        Image(uiImage: generateQRCode(from: url))
            .resizable()
            .scaledToFit()
            .frame(width: 200, height: 200)
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







