//
//  HomeView.swift
//  Pay Join
//
//  Created by Peter Denton on 2/13/24.
//

import SwiftUI
import PhotosUI
import NostrSDK
#if os(macOS)

#endif
import SwiftUICoreImage

struct SendView: View, DirectMessageEncrypting {
    @State private var receiversNpub = ""
    @State private var address = ""
    @State private var amount = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var selectedImage: Image?
    @State private var invoiceIncomplete = false
    @State private var uploadedInvoice: Invoice?
    @State private var invoiceUploaded = false
    @State private var promptToSelectUtxo = false
    @State private var selectedUtxos: [Utxo] = []
    @State private var utxoSelected = false
    @State private var showUtxos = false
    @State private var utxos: [Utxo] = []
    @State private var spendableBalance = 0.0
    @State private var showNostrError = false
    @State private var errorToShow = ""
    @State private var nostrConnected = false
    @State private var urlString = UserDefaults.standard.string(forKey: "nostrRelay") ?? "wss://relay.damus.io"
    
    var body: some View {
        Spacer()
        Label("Send", systemImage: "bitcoinsign")
        List() {
        if !invoiceUploaded {
            Section("Upload a BIP21 Invoice") {
                HStack {
                    #if os(macOS)
                    VStack {
                        PhotosPicker("Upload QR", selection: $pickerItem, matching: .images)
                            .onChange(of: pickerItem) {
                                Task {
                                    selectedImage = try await pickerItem?.loadTransferable(type: Image.self)
                                    let ciImage: CIImage = CIImage(nsImage: selectedImage!.renderAsImage()!)
                                    guard let invoice = invoiceFromQrImage(ciImage: ciImage) else { return }
                                    uploadedInvoice = invoice
                                    invoiceUploaded = true
                                    // display the invoice amount and recipient address
                                    // ask user to select utxos to pay the invoice
                                    // create the initial psbt
                                }
                            }
                        
                    }
                    #elseif os(iOS)
                        VStack {
                            PhotosPicker("Upload", selection: $pickerItem, matching: .images)
                                .onChange(of: pickerItem) {
                                    Task {
                                        selectedImage = try await pickerItem?.loadTransferable(type: Image.self)
                                        let ciImage: CIImage = CIImage(uiImage: selectedImage!.asUIImage())
                                        guard let invoice = invoiceFromQrImage(ciImage: ciImage) else { return }
                                        print("invoice amount: \(invoice.amount!)")
                                        uploadedInvoice = invoice
                                        invoiceUploaded = true
                                        // display the invoice amount and recipient address
                                        // ask user to select utxos to pay the invoice
                                        // create the initial psbt
                                    }
                                }
                        }
                    
                    
                    // Scan QR
                    Button("", systemImage: "qrcode.viewfinder") {}
                    .onTapGesture {
                        print("scan qr")
                    }
                    
                    
                    
                    #endif
                    
                    Button("", systemImage: "doc.on.clipboard") {}
                    .onTapGesture {
                        print("paste")
                            
                        #if os(macOS)
                        let pasteboard = NSPasteboard.general
                        
                        guard let url = pasteboard.pasteboardItems?.first?.string(forType: .string) else {
                            let type = NSPasteboard.PasteboardType.tiff
                            guard let imgData = pasteboard.data(forType: type) else { return }
                            let ciImage: CIImage = CIImage(nsImage: NSImage(data: imgData)!)
                            guard let invoice = invoiceFromQrImage(ciImage: ciImage) else { return }
                            uploadedInvoice = invoice
                            invoiceUploaded = true
                            return
                        }
                        
                        print("url: \(url)")
                        //"bitcoin:tb1qk3xlyqptz4tgujfe5mamt2r4ftrwrt6sf9qawr?amount=0.0002?pj=nostr:npub1vkuquw8fsjggwgeuzdceyp8fsxu07dwtlgpt8zwfsqaw2u7sg45qj6m5jm"
                        let invoice = Invoice(url)
                        guard let _ = invoice.address, let _ = invoice.amount, let _ = invoice.recipientsNpub else { return }
                        uploadedInvoice = invoice
                        invoiceUploaded = true
                        
                        #elseif os(iOS)
                        let pasteboard = UIPasteboard.general
                        
                        guard let image = pasteboard.image else {
                            guard let text = pasteboard.string else { return }
                            let invoice = Invoice(text)
                            guard let _ = invoice.address, let _ = invoice.amount, let _ = invoice.recipientsNpub else { return }
                            uploadedInvoice = invoice
                            invoiceUploaded = true
                            return
                        }
                         
                        guard let ciImage = image.ciImage, let invoice = invoiceFromQrImage(ciImage: ciImage) else { return }
                        uploadedInvoice = invoice
                        invoiceUploaded = true
                        #endif
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
            Button("Clear") {
                uploadedInvoice = nil
                invoiceUploaded = false
            }
            .alert("Select a UTXO to pay with.", isPresented: $promptToSelectUtxo) {}
        }
        
        Spacer()
            if showUtxos {
                Section("Spendable UTXOs") {
                    ForEach(Array(utxos.enumerated()), id: \.offset) { index, utxo in
                        if let address = utxo.address, let amount = utxo.amount, let confs = utxo.confs, confs > 0 {
                            let textLabel = address + ": " + "\(amount)" + " btc"
                            HStack {
                                Text(textLabel)
                                
                                if let uploadedInvoice = uploadedInvoice {
                                    Button("Pay Join this UTXO") {
                                        print("pay using utxo: \(address)")
                                        //createpsbt
                                        payInvoice(invoice: uploadedInvoice, utxo: utxo)
                                    }
                                    .disabled(amount < uploadedInvoice.amount!)
                                }
                                
                            }
                                .onAppear {
                                    spendableBalance += utxo.amount ?? 0.0
                                    print("spendableBalance: \(spendableBalance)")
                                }
                        }
                    }
                }
                Section("Total Spendable Balance") {
                    Text("\(spendableBalance) btc")
                }
            }
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
        .onAppear {
            urlString = UserDefaults.standard.string(forKey: "nostrRelay") ?? "wss://relay.damus.io"
            getUtxos()            
        }
        .alert(errorToShow, isPresented: $showNostrError) {
            Button("OK", role: .cancel) { }
        }
    }
    
    
    private func payInvoice(invoice: Invoice, utxo: Utxo) {
        // first get info on the input address
        let desc = utxo.desc!
        print("desc: \(desc)")
        let inputs = [["txid": utxo.txid, "vout": utxo.vout, "sequence": 0]]
        let outputs = [[invoice.address!: "\(invoice.amount!)"]]
        var options:[String:Any] = [:]
        options["includeWatching"] = true
        options["replaceable"] = true
        options["add_inputs"] = true
        let dict: [String:Any] = ["inputs": inputs, "outputs": outputs, "options": options, "bip32derivs": false]
        let p = Wallet_Create_Funded_Psbt(dict)
        BitcoinCoreRPC.shared.btcRPC(method: .walletcreatefundedpsbt(param: p)) { (response, errorDesc) in
            guard let response = response as? [String: Any], let psbt = response["psbt"] as? String else { return }
            
            print("unsignedPsbt: \(psbt)")
            guard let sendersKeypair = Keypair(), let recipientsNpub = invoice.recipientsNpub else {
                return
            }
            
            guard let encPsbt = encryptedMessage(sendersKeypair: sendersKeypair, receiversNpub: recipientsNpub, message: psbt) else { return }
            
            guard let recipientPubkey = PublicKey(npub: recipientsNpub) else { return }
            
            StreamManager.shared.openWebSocket(subscribeTo: recipientPubkey.hex, relayUrlString: urlString)
            
            StreamManager.shared.eoseReceivedBlock = { _ in
                print("eos received :)")
                nostrConnected = true
                StreamManager.shared.writeEvent(content: encPsbt, pubkey: sendersKeypair.publicKey, privKey: sendersKeypair.privateKey)
            }
            
            StreamManager.shared.errorReceivedBlock = { nostrError in
                print("nostr received error")
                showNostrError = true
                errorToShow = nostrError
                nostrConnected = false
            }
            
            StreamManager.shared.onDoneBlock = { nostrResponse in
                if let errDesc = nostrResponse.errorDesc {
                    if errDesc != "" {
                        print("nostr response error: \(nostrResponse.errorDesc!)")
                    } else {
                        if nostrResponse.response != nil {
                            print("nostr response: \(nostrResponse.response!)")
                        }
                    }
                } else {
                    if nostrResponse.response != nil {
                        print("nostr response: \(nostrResponse.response!)")
                    }
                }
            }            
        }
    }
    
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
    
    
    private func encryptedMessage(sendersKeypair: Keypair, receiversNpub: String, message: String) -> String? {
        guard let receiversPubKey = PublicKey(npub: receiversNpub) else {
            return nil
        }
        
        guard let encryptedMessage = try? encrypt(content: message, privateKey: sendersKeypair.privateKey, publicKey: receiversPubKey) else { return nil }
        
        return encryptedMessage
    }
    
    
    private func getUtxos() {
        let p:List_Unspent = .init([:])
        BitcoinCoreRPC.shared.btcRPC(method: .listunspent(p)) { (response, errorDesc) in
            guard let response = response as? [[String: Any]] else {
                // else prompt to import a psbt or a utxo
                return
            }
            
            var sendable = false
            
            for item in response {
                let utxo: Utxo = .init(item)
                if let confs = utxo.confs, let solvable = utxo.solvable {
                    if confs > 0 && solvable {
                        sendable = true
                        utxos.append(utxo)
                    }
                }
            }
            if sendable {
                // prompt to import a psbt to send or select a utxo
                showUtxos = true
            }
        }
    }
}
////        let unfinalizedSignedPsbt = "cHNidP8BAHMCAAAAAY8nutGgJdyYGXWiBEb45Hoe9lWGbkxh/6bNiOJdCDuDAAAAAAD+////AtyVuAUAAAAAF6kUHehJ8GnSdBUOOv6ujXLrWmsJRDCHgIQeAAAAAAAXqRR3QJbbz0hnQ8IvQ0fptGn+votneofTAAAAAAEBIKgb1wUAAAAAF6kU3k4ekGHKWRNbA1rV5tR5kEVDVNCHAQQWABTHikVyU1WCjVZYB03VJg1fy2mFMCICAxWawBqg1YdUxLTYt9NJ7R7fzws2K09rVRBnI6KFj4UWRzBEAiB8Q+A6dep+Rz92vhy26lT0AjZn4PRLi8Bf9qoB/CMk0wIgP/Rj2PWZ3gEjUkTlhDRNAQ0gXwTO7t9n+V14pZ6oljUBIgYDFZrAGqDVh1TEtNi300ntHt/PCzYrT2tVEGcjooWPhRYYSFzWUDEAAIABAACAAAAAgAEAAAAAAAAAAAEAFgAURvYaK7pzgo7lhbSl/DeUan2MxRQiAgLKC8FYHmmul/HrXLUcMDCjfuRg/dhEkG8CO26cEC6vfBhIXNZQMQAAgAEAAIAAAACAAQAAAAEAAAAAAA=="
////        
////        let originalPsbt = "cHNidP8BAHMCAAAAAY8nutGgJdyYGXWiBEb45Hoe9lWGbkxh/6bNiOJdCDuDAAAAAAD+////AtyVuAUAAAAAF6kUHehJ8GnSdBUOOv6ujXLrWmsJRDCHgIQeAAAAAAAXqRR3QJbbz0hnQ8IvQ0fptGn+votneofTAAAAAAEBIKgb1wUAAAAAF6kU3k4ekGHKWRNbA1rV5tR5kEVDVNCHAQcXFgAUx4pFclNVgo1WWAdN1SYNX8tphTABCGsCRzBEAiB8Q+A6dep+Rz92vhy26lT0AjZn4PRLi8Bf9qoB/CMk0wIgP/Rj2PWZ3gEjUkTlhDRNAQ0gXwTO7t9n+V14pZ6oljUBIQMVmsAaoNWHVMS02LfTSe0e388LNitPa1UQZyOihY+FFgABABYAFEb2Giu6c4KO5YW0pfw3lGp9jMUUAAA="
////        
////        let payjoinProposal = "cHNidP8BAJwCAAAAAo8nutGgJdyYGXWiBEb45Hoe9lWGbkxh/6bNiOJdCDuDAAAAAAD+////jye60aAl3JgZdaIERvjkeh72VYZuTGH/ps2I4l0IO4MBAAAAAP7///8CJpW4BQAAAAAXqRQd6EnwadJ0FQ46/q6NcutaawlEMIcACT0AAAAAABepFHdAltvPSGdDwi9DR+m0af6+i2d6h9MAAAAAAAEBIICEHgAAAAAAF6kUyPLL+cphRyyI5GTUazV0hF2R2NWHAQcXFgAUX4BmVeWSTJIEwtUb5TlPS/ntohABCGsCRzBEAiBnu3tA3yWlT0WBClsXXS9j69Bt+waCs9JcjWtNjtv7VgIge2VYAaBeLPDB6HGFlpqOENXMldsJezF9Gs5amvDQRDQBIQJl1jz1tBt8hNx2owTm+4Du4isx0pmdKNMNIjjaMHFfrQAAAA=="
////        
////        let payjoinProposalFilledWithSendersInformation = "cHNidP8BAJwCAAAAAo8nutGgJdyYGXWiBEb45Hoe9lWGbkxh/6bNiOJdCDuDAAAAAAD+////jye60aAl3JgZdaIERvjkeh72VYZuTGH/ps2I4l0IO4MBAAAAAP7///8CJpW4BQAAAAAXqRQd6EnwadJ0FQ46/q6NcutaawlEMIcACT0AAAAAABepFHdAltvPSGdDwi9DR+m0af6+i2d6h9MAAAAAAQEgqBvXBQAAAAAXqRTeTh6QYcpZE1sDWtXm1HmQRUNU0IcBBBYAFMeKRXJTVYKNVlgHTdUmDV/LaYUwIgYDFZrAGqDVh1TEtNi300ntHt/PCzYrT2tVEGcjooWPhRYYSFzWUDEAAIABAACAAAAAgAEAAAAAAAAAAAEBIICEHgAAAAAAF6kUyPLL+cphRyyI5GTUazV0hF2R2NWHAQcXFgAUX4BmVeWSTJIEwtUb5TlPS/ntohABCGsCRzBEAiBnu3tA3yWlT0WBClsXXS9j69Bt+waCs9JcjWtNjtv7VgIge2VYAaBeLPDB6HGFlpqOENXMldsJezF9Gs5amvDQRDQBIQJl1jz1tBt8hNx2owTm+4Du4isx0pmdKNMNIjjaMHFfrQABABYAFEb2Giu6c4KO5YW0pfw3lGp9jMUUIgICygvBWB5prpfx61y1HDAwo37kYP3YRJBvAjtunBAur3wYSFzWUDEAAIABAACAAAAAgAEAAAABAAAAAAA="

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
