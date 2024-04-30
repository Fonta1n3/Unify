//
//  HomeView.swift
//  Pay Join
//
//  Created by Peter Denton on 2/13/24.
//

import SwiftUI
import PhotosUI
import NostrSDK
import SwiftUICoreImage
import LibWally

struct SendView: View, DirectMessageEncrypting {
    @State private var uploadedInvoice: Invoice?
    @State private var invoiceUploaded = false
    @State private var showUtxos = false
    @State private var utxos: [Utxo] = []
    @State private var showNoUtxosMessage = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var selectedImage: Image?
    @State private var isShowingScanner = false
    @State private var invoiceIncomplete = false
    
    var body: some View {
        Spacer()
        Label("Send", systemImage: "bitcoinsign")
        List() {
            if !invoiceUploaded {
                Section("Upload a BIP21 Invoice") {
                    HStack {
                        VStack {
                            PhotosPicker("Upload", selection: $pickerItem, matching: .images)
                                .onChange(of: pickerItem) {
                                    Task {
                                        selectedImage = try await pickerItem?.loadTransferable(type: Image.self)
                                        #if os(macOS)
                                        let ciImage: CIImage = CIImage(nsImage: selectedImage!.renderAsImage()!)
                                        #elseif os(iOS)
                                        let ciImage: CIImage = CIImage(uiImage: selectedImage!.asUIImage())
                                        #endif
                                        uploadedInvoice = invoiceFromQrImage(ciImage: ciImage)
                                        invoiceUploaded = uploadedInvoice != nil
                                    }
                                }
                        }
                        #if os(iOS)
                        // Can't scan QR on macOS with SwiftUI...
                        Button("", systemImage: "qrcode.viewfinder") {}
                            .onTapGesture {
                                print("scan qr")
                                isShowingScanner = true
                            }
                            .sheet(isPresented: $isShowingScanner) {
                                CodeScannerView(codeTypes: [.qr], simulatedData: "", completion: handleScan)
                            }
                        #endif
                        
                        Button("", systemImage: "doc.on.clipboard") {}
                            .onTapGesture {
                                print("paste")
                                uploadedInvoice = handlePaste()
                                invoiceUploaded = uploadedInvoice != nil
                                print("invoiceUploaded: \(invoiceUploaded)")
                            }
                    }
                }
                .alert("Invoice incomplete!", isPresented: $invoiceIncomplete) {
                    Button("OK", role: .cancel) { }
                }
                
            } else {
                Section("Invoice Address") {
                    Label(uploadedInvoice!.address!, systemImage: "qrcode")
                }
                Section("Invoice Amount") {
                    Label("\(uploadedInvoice!.amount!) btc", systemImage: "bitcoinsign.circle")
                }
                Button("Clear invoice") {
                    uploadedInvoice = nil
                    invoiceUploaded = false
                }
            }
            
            if showUtxos {
                SpendableUtxosView(utxos: utxos, uploadedInvoice: uploadedInvoice)
            } else {
                Section("UTXOs") {
                    Text("No spendable utxos.")
                }
            }
        }
        .onAppear {
            getUtxos()
            //decodePsbts()
            // subscribe to nostr peer to see if any invoices have been sent
            subscribe()
        }
    }
    
    private func subscribe() {
        DataManager.retrieve(entityName: "Credentials") { dict in
            guard let dict = dict, let encPrivKey = dict["nostrPrivkey"] as? Data else { return }
            guard let decPrivkey = Crypto.decrypt(encPrivKey) else { return }
            let sendersKeypair = Keypair(privateKey: PrivateKey(dataRepresentation: decPrivkey)!)!
            let urlString = UserDefaults.standard.string(forKey: "nostrRelay") ?? "wss://relay.damus.io"
            
            StreamManager.shared.openWebSocket(relayUrlString: urlString)
            
            StreamManager.shared.eoseReceivedBlock = { _ in
                print("eos received :)")
                
            }
            
            StreamManager.shared.errorReceivedBlock = { nostrError in
                print("nostr received error: \(nostrError)")
                
//                showNostrError = true
//                errorToShow = nostrError
//                nostrConnected = false
            }
            
            StreamManager.shared.onDoneBlock = { nostrResponse in
                guard let response = nostrResponse.response as? String else {
                    print("nostr response error: \(nostrResponse.errorDesc ?? "unknown error")")
                    return
                }
                
                guard let peerNpub = UserDefaults.standard.object(forKey: "peerNpub") as? String else  {
                    return
                }
                
                guard let decryptedMessage = try? decrypt(encryptedContent: response, privateKey: sendersKeypair.privateKey, publicKey: PublicKey(npub: peerNpub)!) else {
                    print("failed decrypting")
                    return
                }
                
                print("decryptedMessage: \(decryptedMessage)")
                
                let invoice = Invoice(decryptedMessage)
                if let _ = invoice.address,
                      let _ = invoice.amount,
                      let _ = invoice.recipientsNpub {
                    uploadedInvoice = invoice
                    invoiceUploaded = true
                }
                
            }
        }
        
        
    }
    
#if os(iOS)
func handleScan(result: Result<ScanResult, ScanError>) {
    isShowingScanner = false
    switch result {
    case .success(let result):
        let invoice = Invoice(result.string)
        guard let _ = invoice.address,
              let _ = invoice.amount,
              let _ = invoice.recipientsNpub else {
            return
        }
        uploadedInvoice = invoice
        invoiceUploaded = true
        
    case .failure(let error):
        print("Scanning failed: \(error.localizedDescription)")
    }
}
#endif
    
    private func invoiceFromQrImage(ciImage: CIImage) -> Invoice? {
        var qrCodeText = ""
        let detector: CIDetector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])!
        let features = detector.features(in: ciImage)
        for feature in features as! [CIQRCodeFeature] {
            qrCodeText += feature.messageString!
        }
        let invoice = Invoice(qrCodeText)
        guard let _ = invoice.address, let _ = invoice.recipientsNpub, let _ = invoice.amount else {
            return nil
        }
        return invoice
    }
    
    private func handlePaste() -> Invoice? {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        guard let url = pasteboard.pasteboardItems?.first?.string(forType: .string) else {
            let type = NSPasteboard.PasteboardType.tiff
            guard let imgData = pasteboard.data(forType: type) else { return nil }
            let ciImage: CIImage = CIImage(nsImage: NSImage(data: imgData)!)
            return invoiceFromQrImage(ciImage: ciImage)
        }
        
        let invoice = Invoice(url)
        guard let _ = invoice.address, let _ = invoice.amount, let _ = invoice.recipientsNpub else { return nil }
        return invoice
                                
        #elseif os(iOS)
        let pasteboard = UIPasteboard.general
        guard let image = pasteboard.image else {
            guard let text = pasteboard.string else { return nil }
            let invoice = Invoice(text)
            guard let _ = invoice.address, let _ = invoice.amount, let _ = invoice.recipientsNpub else { return nil }
            return invoice
        }
        guard let ciImage = image.ciImage, let invoice = invoiceFromQrImage(ciImage: ciImage) else { return nil }
        return invoice
        #endif
    }
    
    private func getUtxos() {
        let p = List_Unspent([:])
        BitcoinCoreRPC.shared.btcRPC(method: .listunspent(p)) { (response, errorDesc) in
            guard let response = response as? [[String: Any]] else {
                // else prompt to import a psbt or a utxo
                showNoUtxosMessage = true
                return
            }
            
            var spendable = false
            showNoUtxosMessage = response.count == 0
            
            for item in response {
                let utxo = Utxo(item)
                if let confs = utxo.confs, let solvable = utxo.solvable, confs > 0 && solvable {
                    spendable = true
                    utxos.append(utxo)
                }
            }
            if spendable {
                // prompt to import a psbt to send or select a utxo
                showUtxos = true
            }
        }
    }
}




#if os(macOS)
extension View {
    func renderAsImage() -> NSImage? {
        let view = NoInsetHostingView(rootView: self)
        view.setFrameSize(view.fittingSize)
        return view.bitmapImage()
    }
}

class NoInsetHostingView<V>: NSHostingView<V> where V: View {
    override var safeAreaInsets: NSEdgeInsets {
        return .init()
    }
}

public extension NSView {
    
    func bitmapImage() -> NSImage? {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }
        cacheDisplay(in: bounds, to: rep)
        guard let cgImage = rep.cgImage else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: bounds.size)
    }
}
#endif

#if os(iOS)
extension View {
    // This function changes our View to UIView, then calls another function
    // to convert the newly-made UIView to a UIImage.
    public func asUIImage() -> UIImage {
        let controller = UIHostingController(rootView: self)
        
        // Set the background to be transparent incase the image is a PNG, WebP or (Static) GIF
        controller.view.backgroundColor = .clear
        
        controller.view.frame = CGRect(x: 0, y: CGFloat(Int.max), width: 1, height: 1)
        UIApplication.shared.windows.first!.rootViewController?.view.addSubview(controller.view)
        
        let size = controller.sizeThatFits(in: UIScreen.main.bounds.size)
        controller.view.bounds = CGRect(origin: .zero, size: size)
        controller.view.sizeToFit()
        
        // here is the call to the function that converts UIView to UIImage: `.asUIImage()`
        let image = controller.view.asUIImage()
        controller.view.removeFromSuperview()
        return image
    }
}

extension UIView {
    // This is the function to convert UIView to UIImage
    public func asUIImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { rendererContext in
            layer.render(in: rendererContext.cgContext)
        }
    }
}
#endif

struct NostConnectionView: View {
    @State private var urlString = UserDefaults.standard.string(forKey: "nostrRelay") ?? "wss://relay.damus.io"
    
    let nostrConnected: Bool
    
    init(nostrConnected: Bool) {
        self.nostrConnected = nostrConnected
    }
    
    var body: some View {
        Section("Nostr Connection") {
            HStack() {
                if nostrConnected {
                    Image(systemName: "circle.fill")
                        .colorMultiply(.green)
                    
                    Label("Connected to \(urlString)", systemImage: "circle.fill")
                        .labelStyle(.titleOnly)
                    
                } else {
                    Image(systemName: "circle.fill")
                        .colorMultiply(.red)
                    
                    Label("Not connected to \(urlString)", systemImage: "circle.fill")
                        .labelStyle(.titleOnly)
                }
            }
        }
    }
}


struct SpendableUtxosView: View, DirectMessageEncrypting {
    @State private var urlString = UserDefaults.standard.string(forKey: "nostrRelay") ?? "wss://relay.damus.io"
    @State private var nostrConnected = false
    @State private var showNostrError = false
    @State private var errorToShow = ""
    @State private var spendableBalance = 0.0
    //@State private var nostrPubkey = ""
    @State private var sendersKeypair: Keypair?
    
    let utxos: [Utxo]
    let uploadedInvoice: Invoice?
    
    init(utxos: [Utxo], uploadedInvoice: Invoice?) {
        self.utxos = utxos
        self.uploadedInvoice = uploadedInvoice
    }
    
    var body: some View {
        Section("Spendable UTXOs") {
           ForEach(Array(utxos.enumerated()), id: \.offset) { (index, utxo) in
               if let address = utxo.address, let amount = utxo.amount, let confs = utxo.confs, confs > 0 {
                   let textLabel = address + ": " + "\(amount)" + " btc"
                   HStack {
                       Text(textLabel)
                       
                       if let uploadedInvoice = uploadedInvoice {
                           Button("Pay Join this UTXO") {
                               payInvoice(invoice: uploadedInvoice, utxo: utxo)
                           }
                           .disabled(amount < uploadedInvoice.amount!)
                       }
                       
                   }
                   .onAppear {
                       spendableBalance += utxo.amount ?? 0.0
                   }
               }
           }
       }
        Section("Total Spendable Balance") {
            Text("\(spendableBalance) btc")
        }
        NostConnectionView(nostrConnected: nostrConnected)
        
//        .onAppear {
//            subscribe()
//        }
    }
    
    
    
    private func payInvoice(invoice: Invoice, utxo: Utxo) {
        // first get info on the input address
        let desc = utxo.desc!
        print("desc: \(desc)")
        // use desc to sign locally if needed
        //
        let inputs = [["txid": utxo.txid, "vout": utxo.vout, "sequence": 0]]
        let outputs = [[invoice.address!: "\(invoice.amount!)"]]
        var options:[String:Any] = [:]
        options["includeWatching"] = true
        options["replaceable"] = true
        options["add_inputs"] = true
        let dict: [String:Any] = ["inputs": inputs, "outputs": outputs, "options": options, "bip32_derivs": false]
        let p = Wallet_Create_Funded_Psbt(dict)
        BitcoinCoreRPC.shared.btcRPC(method: .walletcreatefundedpsbt(param: p)) { (response, errorDesc) in
            guard let response = response as? [String: Any], let psbt = response["psbt"] as? String else {
                print("error from btc core")
                return
            }
            // sign the psbt :)
            Signer.sign(psbt: psbt, passphrase: nil, completion: { (signedPsbt, rawTx, errorMessage) in
//                print("signed psbt: \(psbt)")
//                print("raw tx: \(String(describing: rawTx))")
//                print("errorMessage: \(String(describing: errorMessage))")
                guard let signedPsbt = signedPsbt else { return }
                let param = Test_Mempool_Accept(["rawtxs":[rawTx]])
                BitcoinCoreRPC.shared.btcRPC(method: .testmempoolaccept(param)) { (response, errorDesc) in
                    guard let response = response as? [[String: Any]], let allowed = response[0]["allowed"] as? Bool, allowed else { 
                        return
                    }
                    
                    print("allowed")
                    
                    DataManager.retrieve(entityName: "Credentials") { dict in
                        guard let dict = dict, let encPrivKey = dict["nostrPrivkey"] as? Data else { return }
                        guard let decPrivkey = Crypto.decrypt(encPrivKey) else { return }
                        let sendersKeypair = Keypair(privateKey: PrivateKey(dataRepresentation: decPrivkey)!)!
                        
                        guard let recipientsNpub = invoice.recipientsNpub else {
                            print("unable to init our keypair or recipient npub")
                            return
                        }
                        
                        guard let encPsbt = encryptedMessage(sendersKeypair: sendersKeypair, receiversNpub: recipientsNpub, message: signedPsbt) else {
                            print("psbt encryption failed")
                            return
                        }
                        
                        guard let _ = PublicKey(npub: recipientsNpub) else { return }
                        
                        
                        
                        
                        
                        let urlString = UserDefaults.standard.string(forKey: "nostrRelay") ?? "wss://relay.damus.io"
                        
                        StreamManager.shared.openWebSocket(relayUrlString: urlString)
                        
                        StreamManager.shared.eoseReceivedBlock = { _ in
                            print("eos received :)")
                            StreamManager.shared.writeEvent(content: encPsbt, recipientNpub: recipientsNpub)
                        }
                        
                        StreamManager.shared.errorReceivedBlock = { nostrError in
                            print("nostr received error: \(nostrError)")
                            
            //                showNostrError = true
            //                errorToShow = nostrError
            //                nostrConnected = false
                        }
                        
                        StreamManager.shared.onDoneBlock = { nostrResponse in
                            guard let response = nostrResponse.response as? String else {
                                print("nostr response error: \(nostrResponse.errorDesc ?? "unknown error")")
                                return
                            }
                            
                            guard let peerNpub = UserDefaults.standard.object(forKey: "peerNpub") as? String else  {
                                return
                            }
                            
                            guard let decryptedMessage = try? decrypt(encryptedContent: response, privateKey: sendersKeypair.privateKey, publicKey: PublicKey(npub: peerNpub)!) else {
                                print("failed decrypting")
                                return
                            }
                            
                            print("decryptedMessage: \(decryptedMessage)")
                            
                            if let payjoinProposal = try? PSBT(psbt: decryptedMessage, network: .testnet) {
                                print("sender payjoinProposal: \(payjoinProposal.description)")
                                // now we inpsect it and sign it.
                            }
                        }
                    }
                }
            })
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
