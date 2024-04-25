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
    let urlString = UserDefaults.standard.string(forKey: "nostrRelay") ?? "wss://relay.damus.io"
    
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
                Section("Add Utxos") {
                    if showUtxosView {
                        UtxosView(utxos: utxosToPotentiallyConsume)
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
//        .sheet(isPresented: $showUtxosView) {
//            //CodeScannerView(codeTypes: [.qr], simulatedData: "", completion: handleScan)
//            UtxosView(utxos: utxosToPotentiallyConsume)
//        }
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
             let psbtData = Data(base64Encoded: decryptedMessage, options: .ignoreUnknownCharacters)
             guard let psbt = try? PSBT(psbt: decryptedMessage, network: .testnet) else { return }
             var scriptPubkeyTypesMatch = true
             let invoiceAddress = try! Address(string: address)
             let invoiceSPKType = invoiceAddress.scriptPubKey.type!
             print("invoiceSPKType: \(invoiceSPKType)")
             
             var allInputsSegwit = false
             for input in psbt.inputs {
                 print("input.isSegwit: \(input.isSegwit)")
                 if input.isSegwit {
                     allInputsSegwit = true
                 }
             }
             
             var allOutputsSegwit = false
             for output in psbt.outputs {
                 print("output script type: \(output.txOutput.scriptPubKey.type!)")
                 print("output amount: \(output.txOutput.amount)")
                 if output.txOutput.scriptPubKey.type == .payToWitnessPubKeyHash {
                     allOutputsSegwit = true
                 }
             }
             
             guard allOutputsSegwit, allInputsSegwit, let finalizedPsbt = try? psbt.finalized() else {
                 print("something not segwit...")
                 return
             }
                 
            print("yea it was finalized locally: \(finalizedPsbt.transaction.description!)")
             
             
             // ignore invoices in the receive view, handle next step for psbt payjoin process which should be ?
             
             // check to see if its a psbt then decode it and parse it
//             BitcoinCoreRPC.shared.btcRPC(method: .decodepsbt(param: Decode_Psbt(["psbt": decryptedMessage]))) { (response, errorDesc) in
//                 guard let originalPsbt = response as? String else {
//                     return
//                 }
//                 
//                 print("originalPsbt: \(originalPsbt)")
                 // we add our inputs and outputs
                 
//                  Receiver's original PSBT checklist
//
//                  The receiver needs to do some check on the original PSBT before proceeding:
//
//                  Non-interactive receivers (like a payment processor) need to check that the original PSBT is broadcastable. *
             
             //BitcoinCoreRPC.shared.btcRPC(method: .finalizepsbt(Finalize_Psbt(["psbt": decryptedMessage]))) { (response, errorDesc) in
                 //guard let response = response as? [String: Any], let complete = response["complete"] as? Bool, complete else { return }
                 //print("finalized psbt: \(response)")
                 
                 //                  If the sender included inputs in the original PSBT owned by the receiver, the receiver must either return error original-psbt-rejected or make sure they do not sign those inputs in the payjoin proposal.
                 
                 /// prompt user to select additional inputs or outputs, first check utxos
                 BitcoinCoreRPC.shared.btcRPC(method: .listunspent(List_Unspent([:]))) { (response, errorDesc) in
                     guard let utxos = response as? [[String: Any]] else { return }
                     
                     print("utxos: \(utxos)")
                     for (i, utxo) in utxos.enumerated() {
                         let utxo = Utxo(utxo)
                         if let confs = utxo.confs, confs > 0, let solvable = utxo.solvable, solvable {
                             if let address = utxo.address, ((try? Address(string: address).scriptPubKey.type == .payToWitnessPubKeyHash)!) {
                                 utxosToPotentiallyConsume.append(utxo)
                             }
                             
                             // should present a modal view that prompts user to select utxos to add
                             
                             
                             // then outputs
                         }
                         if i + 1 == utxos.count && utxosToPotentiallyConsume.count > 0 {
                             showUtxosView = true
                             print("showUtxosView = true")
                         } else {
                             // no suitable inputs to pay join in this psbt...
                         }
                     }
                 }
                 
                 //                  If the sender's inputs are all from the same scriptPubKey type, the receiver must match the same type. If the receiver can't match the type, they must return error unavailable.
                                  
                                  
                                  
                 //                  Make sure that the inputs included in the original transaction have never been seen before.
                 //                  This prevent probing attacks.
                 //                  This prevent reentrant payjoin, where a sender attempts to use payjoin transaction as a new original transaction for a new payjoin.
                 //                  *: Interactive receivers are not required to validate the original PSBT because they are not exposed to probing attacks.
             //}
                 

                 
                 

                 

                  
             //}
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

struct UtxosView: View {
    @State private var utxosToConsume: [Utxo] = []
    @State private var multiSelection = Set<UUID>()
    let utxos: [Utxo]
    
    init(utxos: [Utxo]) {
        self.utxos = utxos
    }
    
    var body: some View {
//        ForEach(Array(utxos.enumerated()), id: \.offset) { (index, utxo) in
//            if let address = utxo.address, let amount = utxo.amount, let confs = utxo.confs, confs > 0 {
//                let textLabel = address + ": " + "\(amount)" + " btc"
//                HStack {
//                    Text(textLabel)
//                    Button("Add") {
//                        print("add input \(address):\(amount)")
//                        utxosToConsume.append(utxo)
//                    }
//                    
//                    
//                    
//                }
//            }
//        }
            VStack {
                List(utxos, selection: $multiSelection) { utxo in
                    if let address = utxo.address, let amount = utxo.amount {
                        let textLabel = address + ": " + "\(amount)" + " btc"
                            Text(textLabel)
                            .onTapGesture {
                                print("add input \(address):\(amount)")
                                utxosToConsume.append(utxo)
                            }
                            
                            
                            
                    }
                    
                }
                .frame(minHeight: CGFloat(utxos.count) * 20)
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
            ShareLink(item: Image(nsImage: image), preview: SharePreview("Share", image: image))
            
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







