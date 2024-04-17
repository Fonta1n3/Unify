//
//  ReceiveView.swift
//  Pay Join
//
//  Created by Peter Denton on 2/14/24.
//

#if os(iOS)
import UIKit
#elseif os(macOS)
import Cocoa
#endif

import NostrSDK
import SwiftUI
import CoreImage.CIFilterBuiltins


struct ReceiveView: View {
    @State private var amount = ""
    @State private var address = ""
    @State private var npub = ""
    @State private var showCopiedAlert = false
    @State private var payeeNpub = ""
    
    var body: some View {
        Spacer()
        Label("Receive", systemImage: "qrcode")
        List() {
            Section("Amount") {
                TextField("Amount in btc", text: $amount)
            }
            Section("Recipient Address") {
                TextField("Recipient address", text: $address)
            }
            
            if let amountDouble = Double(amount), amountDouble > 0 && address != "" {
                //if amountDouble > 0 && address != "" {
                Section("PayJoin Invoice") {
                    let url = "bitcoin:\($address.wrappedValue)?amount=\($amount.wrappedValue)&pj=nostr:\($npub.wrappedValue)"
                    QRView(url: url)
                    
                    Text(url)
                        .truncationMode(.middle)
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
                Section("Request") {
                    TextField("Payee Npub", text: $payeeNpub)
                    Button("Request") {
                        print("connect to nostr now and request...")
                        print("payee npub: \(payeeNpub)")
                    }
                }
            }
        }
        .onAppear {
            print("receive view")
            fetchAddress()
            npub = createOneTimeKeyPair() ?? ""
        }
        .alert("Invoice copied ✓", isPresented: $showCopiedAlert) {
            Button("OK", role: .cancel) { }
        }
    }
    
    private func createOneTimeKeyPair() -> String? {
        guard let receiversPrivKey = PrivateKey(hex: Crypto.privateKey) else {
            print("unable to init privkey")
            return nil
        }
        guard let receiversKeypair = Keypair(privateKey: receiversPrivKey) else {
            print("unable to get keypair")
            return nil
        }
        let receiversPubKey = receiversKeypair.publicKey
        let receiversNpub = receiversPubKey.npub
        return receiversNpub
    }
    
    private func fetchAddress() {
        let p: Get_New_Address = .init(["address_type": "bech32"])
        BitcoinCoreRPC.shared.btcRPC(method: .getnewaddress(param: p)) { (response, errorDesc) in
            guard let address = response as? String else { return }
            
            self.address = address
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







