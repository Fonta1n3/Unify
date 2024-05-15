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
    @State private var payeeNpub = UserDefaults.standard.object(forKey: "peerNpub") as? String ?? ""
    @State private var ourKeypair: Keypair?
    @State private var invoice = ""
    @State private var utxosToPotentiallyConsume: [Utxo] = []
    @State private var showUtxosView = false
    @State private var originalPsbt: PSBT? = nil
    private let urlString = UserDefaults.standard.string(forKey: "nostrRelay") ?? "wss://relay.damus.io"
    
    
    var body: some View {
        Spacer()
        Label("Receive", systemImage: "qrcode")
        Form() {
            Section("Create Invoice") {
                TextField("Amount in btc", text: $amount)
                #if os(iOS)
                    .keyboardType(.decimalPad)
                #endif
                
                TextField("Recipient address", text: $address)
                #if os(iOS)
                    .keyboardType(.default)
                #endif
            }
//            Section("Amount") {
//                
//            }
//            Section("Recipient Address") {
//                
//            }
            
            if let amountDouble = Double(amount), amountDouble > 0 && address != "" {
                let url = "bitcoin:\($address.wrappedValue)?amount=\($amount.wrappedValue)&pj=nostr:\($npub.wrappedValue)"
                Section("PayJoin Invoice") {
                    QRView(url: url)
                    Text(url)
                        .truncationMode(.middle)
                        .lineLimit(1)
                    HStack {
                        ShareLink("Export", item: url)
                        Button("Copy", systemImage: "doc.on.doc") {
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(url, forType: .string)
                            print()
                            #elseif os(iOS)
                            UIPasteboard.general.string = url
                            #endif
                            showCopiedAlert = true
                        }
                    }
                }
                .onAppear {
                    invoice = url
                }
                
                Section("Request") {
                    TextField("Payee Npub", text: $payeeNpub)
                    Button("Request") {
                        if let _ = PublicKey(npub: payeeNpub) {
                            connectToNostr()
                        }
                    }
                    .disabled(PublicKey(npub: payeeNpub) == nil)
                }
                if showUtxosView, let originalPsbt = originalPsbt {
                    Section("Add Input") {
                            UtxosSelectionView(utxos: utxosToPotentiallyConsume, 
                                               originalPsbt: originalPsbt,
                                               ourKeypair: ourKeypair!,
                                               payeeNpub: payeeNpub)
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
            DataManager.retrieve(entityName: "Credentials") { dict in
                guard let dict = dict, let encPrivKey = dict["nostrPrivkey"] as? Data else { return }
                
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
        guard let payeePubkey = PublicKey(npub: payeeNpub) else {
            print("failed getting pubkey")
            return
        }
        
        StreamManager.shared.openWebSocket(relayUrlString: urlString)
        
        StreamManager.shared.eoseReceivedBlock = { _ in
            guard let encInvoice = encryptedMessage(ourKeypair: ourKeypair!, receiversNpub: payeeNpub, message: self.invoice) else {
                print("failed encrytping invoice")
                return
            }
            StreamManager.shared.writeEvent(content: encInvoice, recipientNpub: payeeNpub)
        }
        
        StreamManager.shared.errorReceivedBlock = { nostrError in
            print("nostr received error: \(nostrError)")
        }
        
        StreamManager.shared.onDoneBlock = { nostrResponse in
            guard let response = nostrResponse.response as? String else {
                print("nostr response error: \(nostrResponse.errorDesc ?? "unknown error")")
                return
            }
            
            guard let decryptedMessage = try? decrypt(encryptedContent: response, privateKey: ourKeypair!.privateKey, publicKey: payeePubkey) else {
                print("failed decrypting")
                return
            }
            
            // First check if it satisfies our current invoice...
            guard let psbt = try? PSBT(psbt: decryptedMessage, network: .testnet) else { return }
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
                print("something not segwit...")
                return
            }
            
            let finalizeParam = Finalize_Psbt(["psbt": psbt.description])
            BitcoinCoreRPC.shared.btcRPC(method: .finalizepsbt(finalizeParam)) { (response, errorDesc) in
                guard let response = response as? [String: Any], 
                        let complete = response["complete"] as? Bool, complete,
                        let hex = response["hex"] as? String else {
                    return
                }
                // Non-interactive receivers (like a payment processor) need to check that the original PSBT is broadcastable. *
                // Make sure that the inputs included in the original transaction have never been seen before.
                // This prevent probing attacks.
                let testmempoolacceptParam = Test_Mempool_Accept(["rawtxs": [hex]])
                BitcoinCoreRPC.shared.btcRPC(method: .testmempoolaccept(testmempoolacceptParam)) { (response, errorDesc) in
                    guard let response = response as? [[String: Any]], let allowed = response[0]["allowed"] as? Bool else {
                        print("no response from testmempoolaccept")
                        return
                    }
                    
                    if allowed {
                        originalPsbt = psbt
                        showUtxosView = true
                    }
                }
            }
            

            // Receiver's original PSBT checklist
            //
            // The receiver needs to do some check on the original PSBT before proceeding:
            
            //  If the sender included inputs in the original PSBT owned by the receiver, the receiver must either return error original-psbt-rejected or make sure they do not sign those inputs in the payjoin proposal.
            
            // This prevent reentrant payjoin, where a sender attempts to use payjoin transaction as a new original transaction for a new payjoin.
            // *: Interactive receivers are not required to validate the original PSBT because they are not exposed to probing attacks.
            
            BitcoinCoreRPC.shared.btcRPC(method: .listunspent(List_Unspent([:]))) { (response, errorDesc) in
                guard let utxos = response as? [[String: Any]] else { return }
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
            guard let address = response as? String else { return }
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
    @State private var additionalOutputAddress = ""
    @State private var additionalOutputAmount = ""
    @State var selectedUtxo: Utxo? = nil
    
    let utxos: [Utxo]
    let originalPsbt: PSBT
    let ourKeypair: Keypair
    let payeeNpub: String
    
    var body: some View {
        List {
            ForEach(utxos, id: \.self) { utxo in
                UtxoSelectionCell(utxo: utxo, selectedUtxo: self.$selectedUtxo)
            }
        }
        .frame(minHeight: CGFloat(utxos.count) * 40)
        
        if let selectedUtxo = selectedUtxo {
            AddOutputView(utxo: selectedUtxo, 
                          originalPsbt: originalPsbt,
                          ourKeypair: ourKeypair,
                          payeeNpub: payeeNpub)
        }
    }
}


struct UtxoSelectionCell: View {
    let utxo: Utxo
    @Binding var selectedUtxo: Utxo?
    
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
        Section("Add Output") {
            TextField("Address", text: $additionalOutputAddress)
            TextField("Amount", text: $additionalOutputAmount)
        }
        
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
            let p = Wallet_Create_Funded_Psbt(["inputs": inputsForParams, "outputs": outputsForParams, "options": options, "bip32derivs": false])
            
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
                        guard let encPsbtProposal = encryptedMessage(ourKeypair: ourKeypair, 
                                                                     receiversNpub: payeeNpub,
                                                                     message: signedPayjoinProposal) else {
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
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: 200, height: 200)
        
        HStack {
            ShareLink(item: Image(nsImage: image), preview: SharePreview("", image: image)) {
                Label("Export", systemImage:  "square.and.arrow.up")
            }
            Button("Copy", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
                showCopiedAlert = true
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







