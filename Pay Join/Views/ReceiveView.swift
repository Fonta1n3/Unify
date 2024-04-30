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
    @State private var sendersKeypair: Keypair?
    @State private var invoice = ""
    @State private var utxosToPotentiallyConsume: [Utxo] = []
    @State private var showUtxosView = false
    @State private var originalPsbt: PSBT? = nil
    @State private var outputs: [String] = []
    @State private var outputAddress = ""
    @State private var outputAmount = ""
    @State private var urlString = UserDefaults.standard.string(forKey: "nostrRelay") ?? "wss://relay.damus.io"
    
    
    var body: some View {
        Spacer()
        Label("Receive", systemImage: "qrcode")
        List() {
            Section("Amount") {
                TextField("Amount in btc", text: $amount)
                #if os(iOS)
                    .keyboardType(.decimalPad)
                #endif
            }
            Section("Recipient Address") {
                TextField("Recipient address", text: $address)
                #if os(iOS)
                    .keyboardType(.default)
                #endif
            }
            
            if let amountDouble = Double(amount), amountDouble > 0 && address != "" {
                let url = "bitcoin:\($address.wrappedValue)?amount=\($amount.wrappedValue)&pj=nostr:\($npub.wrappedValue)"
                Section("PayJoin Invoice") {
                    QRView(url: url)
                    
                    Text(url)
                        .truncationMode(.middle)
                        .lineLimit(1)
                    HStack {
                        ShareLink("", item: url)
                        
                        Button("", systemImage: "doc.on.doc") {}
                        .onTapGesture {
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(url, forType: .string)
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
                        if showUtxosView {
                            UtxosSelectionView(utxos: utxosToPotentiallyConsume, originalPsbt: originalPsbt, sendersKeypair: sendersKeypair!, payeeNpub: payeeNpub)
                        }
                    }
                }
            }
        }
        .onAppear {
            print("receive view")
            fetchAddress()
            DataManager.retrieve(entityName: "Credentials") { dict in
                guard let dict = dict, let encPrivKey = dict["nostrPrivkey"] as? Data else { return }
                
                guard let decPrivkey = Crypto.decrypt(encPrivKey) else { return }
                
                sendersKeypair = Keypair(privateKey: PrivateKey(dataRepresentation: decPrivkey)!)!
                npub = sendersKeypair!.publicKey.npub
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
            print("eos received :)")
            //nostrConnected = true
            guard let encInvoice = encryptedMessage(sendersKeypair: sendersKeypair!, receiversNpub: payeeNpub, message: self.invoice) else {
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
            
            guard let decryptedMessage = try? decrypt(encryptedContent: response, privateKey: sendersKeypair!.privateKey, publicKey: payeePubkey) else {
                print("failed decrypting")
                return
            }
            
            print("decryptedMessage: \(decryptedMessage)")
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
            for output in psbt.outputs {
                if output.txOutput.scriptPubKey.type == .payToWitnessPubKeyHash {
                    allOutputsSegwit = true
                }
            }
            
            guard allOutputsSegwit, allInputsSegwit else {
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
                    } else {
                        print("not allowed")
                    }
                }
            }
            

            // Receiver's original PSBT checklist
            //
            //                  The receiver needs to do some check on the original PSBT before proceeding:
            //
            
            
            
            //                  If the sender included inputs in the original PSBT owned by the receiver, the receiver must either return error original-psbt-rejected or make sure they do not sign those inputs in the payjoin proposal.
            
            
            //                  This prevent reentrant payjoin, where a sender attempts to use payjoin transaction as a new original transaction for a new payjoin.
            //                  *: Interactive receivers are not required to validate the original PSBT because they are not exposed to probing attacks.
            
            BitcoinCoreRPC.shared.btcRPC(method: .listunspent(List_Unspent([:]))) { (response, errorDesc) in
                guard let utxos = response as? [[String: Any]] else { return }
                
                for utxo in utxos {
                    let utxo = Utxo(utxo)
                    if let confs = utxo.confs, confs > 0, let solvable = utxo.solvable, solvable {
                        if let address = utxo.address, ((try? Address(string: address).scriptPubKey.type == .payToWitnessPubKeyHash)!) {
                            utxosToPotentiallyConsume.append(utxo)
                        }
                    }
                }
            }
        }
    }
    
    
    private func fetchAddress() {
        let p: Get_New_Address = .init(["address_type": "bech32"])
        BitcoinCoreRPC.shared.btcRPC(method: .getnewaddress(param: p)) { (response, errorDesc) in
            guard let address = response as? String else { return }
            
            self.address = address
        }
    }
    
    private func encryptedMessage(sendersKeypair: Keypair, receiversNpub: String, message: String) -> String? {
        guard let receiversPubKey = PublicKey(npub: receiversNpub) else {
            return nil
        }
        
        guard let encryptedMessage = try? encrypt(content: message, privateKey: sendersKeypair.privateKey, publicKey: receiversPubKey) else { return nil }
        
        return encryptedMessage
    }
    
}


struct AddOutputView: View {
    @State private var address = ""
    @State private var amount = ""
    
    var body: some View {
        TextField("Address", text: $address)
        TextField("Amount", text: $amount)
        Button("Create Payjoin Proposal") {
            
        }
    }
}


struct UtxosSelectionView: View, DirectMessageEncrypting {
    @State private var additionalOutputAddress = ""
    @State private var additionalOutputAmount = ""
    @State var selectedUtxo: Utxo? = nil
    
    let utxos: [Utxo]
    let originalPsbt: PSBT
    let sendersKeypair: Keypair
    let payeeNpub: String
    
    init(utxos: [Utxo], originalPsbt: PSBT, sendersKeypair: Keypair, payeeNpub: String) {
        self.utxos = utxos
        self.originalPsbt = originalPsbt
        self.payeeNpub = payeeNpub
        self.sendersKeypair = sendersKeypair
    }
    
    var body: some View {
        List {
            ForEach(utxos, id: \.self) { utxo in
                UtxoSelectionCell(utxo: utxo, selectedUtxo: self.$selectedUtxo)
            }
        }
        .frame(minHeight: CGFloat(utxos.count) * 40)
        
        Section("Add Output") {
            TextField("Address", text: $additionalOutputAddress)
            TextField("Amount", text: $additionalOutputAmount)
        }
        
        Button("Create Payjoin Proposal") {
            print("add output: \(additionalOutputAddress + ":" + additionalOutputAmount)")
            let decodePsbtParam = Decode_Psbt(["psbt": originalPsbt.description])
            BitcoinCoreRPC.shared.btcRPC(method: .decodepsbt(param: decodePsbtParam)) { (response, errorDesc) in
                guard let response = response as? [String: Any] else { return }
                let decodedPsbt = DecodedPsbt(response)
                var inputsForParams: [[String:Any]] = []
                // add senders inputs
                for input in decodedPsbt.txInputs {
                    var inputDict: [String: Any] = [:]
                    inputDict["txid"] = input["txid"] as! String
                    inputDict["vout"] = input["vout"] as! Int
                    inputsForParams.append(inputDict)
                }
                // add our inputs
                if let selectedUtxo = selectedUtxo {
                    var ourInputDict: [String: Any] = [:]
                    ourInputDict["txid"] = selectedUtxo.txid
                    ourInputDict["vout"] = selectedUtxo.vout
                }
                // add the outputs
                let ourOutput = [additionalOutputAddress: additionalOutputAmount]
                var outputsForParams: [[String: Any]] = []
                outputsForParams.append(ourOutput)
                
                for output in originalPsbt.outputs {
                    var outputDict: [String: Any] = [:]
                    outputDict[output.txOutput.address!] = "\(Double(output.txOutput.amount) / 100000000.0)"
                    outputsForParams.append(outputDict)
                }
                
                let options = ["add_inputs": true]
                let p = Wallet_Create_Funded_Psbt(["inputs": inputsForParams, "outputs": outputsForParams, "options": options, "bip32_derivs": false])
                BitcoinCoreRPC.shared.btcRPC(method: .walletcreatefundedpsbt(param: p)) { (response, errorDesc) in
                    guard let response = response as? [String: Any], let payjoinProposalPsbt = response["psbt"] as? String else { return }
                    
                    Signer.sign(psbt: payjoinProposalPsbt, passphrase: nil) { (psbt, rawTx, errorMessage) in
                        guard let signedPayjoinProposal = psbt else {
                            print("no signed psbt")
                            return
                        }
                        
                        // send encrypted signedPayjoinProposal to the sender
                        guard let encPsbt = encryptedMessage(sendersKeypair: sendersKeypair, receiversNpub: payeeNpub, message: signedPayjoinProposal) else {
                            print("failed encrytping payjoin proposal")
                            return
                        }
                        
                        StreamManager.shared.writeEvent(content: encPsbt, recipientNpub: payeeNpub)
                    }
                }
            }
        }
    }
    
    private func encryptedMessage(sendersKeypair: Keypair, receiversNpub: String, message: String) -> String? {
        guard let receiversPubKey = PublicKey(npub: receiversNpub) else {
            return nil
        }
        
        guard let encryptedMessage = try? encrypt(content: message, privateKey: sendersKeypair.privateKey, publicKey: receiversPubKey) else { return nil }
        
        return encryptedMessage
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
        }   .onTapGesture {
            self.selectedUtxo = self.utxo
        }
    }
}


struct QRView: View {
    @State private var showCopiedAlert = false
    let url: String
    
    init(url: String) {
        self.url = url
    }
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
            ShareLink(item: Image(nsImage: image), preview: SharePreview("", image: image))
            
            Button("", systemImage: "doc.on.doc") {
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







