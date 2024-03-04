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

import SwiftUI
import CoreImage.CIFilterBuiltins


struct ReceiveView: View {
    @State private var amount = ""
    @State private var address = ""
    @State private var relayUrl = ""
    
    var body: some View {
        List() {
                Section("Create a PayJoin BIP21 Invoice") {
                    TextField("Amount in btc", text: $amount)
                    HStack {
                        TextField("Recipient address", text: $address)
                        Button("From wallet") {
                            print("fetch an address with bitcoin core")
                            fetchAddress()
                        }
                    }
                    TextField("Nostr relay", text: $relayUrl)
                    QRView()
                }
        }
        .onAppear {
            print("receive view")
        }
    }
    
    private func fetchAddress() {
        let p: Get_New_Address = .init(["address_type": "bech32"])
        BitcoinCoreRPC.shared.btcRPC(method: .getnewaddress(param: p)) { (response, errorDesc) in
            guard let response = response else { return }
            
            address = response as! String
        }
    }
    
    
    
}

struct QRView: View {
#if os(iOS)
    var body: some View {
        Image(uiImage: generateQRCode(from: "test"))
            .resizable()
            .scaledToFit()
            .frame(width: 200, height: 200)
    }
    #elseif os(macOS)
    var body: some View {
        Image(nsImage: generateQRCode(from: "test"))
            .resizable()
            .scaledToFit()
            .frame(width: 200, height: 200)
    }
    #endif
    
    #if os(iOS)
    func generateQRCode(from string: String) -> UIImage {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)

        if let outputImage = filter.outputImage {
            if let cgImage = context.createCGImage(outputImage, from: outputImage.extent) {
                return UIImage(cgImage: cgImage)
            }
        }

        return UIImage(systemName: "xmark.circle") ?? UIImage()
    }
    #elseif os(macOS)
    private func generateQRCode(from string: String) -> NSImage {
        let data = "hello".data(using: .ascii)
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







