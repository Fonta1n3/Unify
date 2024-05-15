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
    //@State private var invoiceIncomplete = false
    
    var body: some View {
        Spacer()
        Label("Send", systemImage: "bitcoinsign")
        Form() {
            if !invoiceUploaded {
                Section("Invoice") {
                    UploadInvoiceView(uploadedInvoice: $uploadedInvoice, invoiceUploaded: $invoiceUploaded)
                }
            } else {
                    Section("Invoice") {
                        if let uploadedInvoice = uploadedInvoice {
                            Label("Address: \(uploadedInvoice.address!)", systemImage: "qrcode")
                            Label("Amount: \(uploadedInvoice.amount!) btc", systemImage: "bitcoinsign")
                        }
                        Button("Clear") {
                            uploadedInvoice = nil
                            invoiceUploaded = false
                        }
                        .buttonStyle(.bordered)
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
        .formStyle(.grouped)
        .multilineTextAlignment(.leading)
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
        .onAppear {
            getUtxos()
            subscribe()
        }
    }
    
    private func subscribe() {
        DataManager.retrieve(entityName: "Credentials") { dict in
            guard let dict = dict, let encPrivKey = dict["nostrPrivkey"] as? Data else { return }
            guard let decPrivkey = Crypto.decrypt(encPrivKey) else { return }
            let ourKeypair = Keypair(privateKey: PrivateKey(dataRepresentation: decPrivkey)!)!
            let urlString = UserDefaults.standard.string(forKey: "nostrRelay") ?? "wss://relay.damus.io"
            StreamManager.shared.openWebSocket(relayUrlString: urlString)
            StreamManager.shared.eoseReceivedBlock = { _ in }
            StreamManager.shared.errorReceivedBlock = { nostrError in
                print("nostr received error: \(nostrError)")
            }
            StreamManager.shared.onDoneBlock = { nostrResponse in
                guard let response = nostrResponse.response as? String else {
                    print("nostr response error: \(nostrResponse.errorDesc ?? "unknown error")")
                    return
                }
                guard let peerNpub = UserDefaults.standard.object(forKey: "peerNpub") as? String else  {
                    return
                }
                
                guard let decryptedMessage = try? decrypt(encryptedContent: response,
                                                          privateKey: ourKeypair.privateKey,
                                                          publicKey: PublicKey(npub: peerNpub)!) else {
                    print("failed decrypting")
                    return
                }
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
//    func handleScan(result: Result<ScanResult, ScanError>) {
//        isShowingScanner = false
//        switch result {
//        case .success(let result):
//            let invoice = Invoice(result.string)
//            guard let _ = invoice.address,
//                  let _ = invoice.amount,
//                  let _ = invoice.recipientsNpub else {
//                return
//            }
//            uploadedInvoice = invoice
//            invoiceUploaded = true
//            
//        case .failure(let error):
//            print("Scanning failed: \(error.localizedDescription)")
//        }
//    }
#endif
    
//    private func invoiceFromQrImage(ciImage: CIImage) -> Invoice? {
//        var qrCodeText = ""
//        let detector: CIDetector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])!
//        let features = detector.features(in: ciImage)
//        for feature in features as! [CIQRCodeFeature] {
//            qrCodeText += feature.messageString!
//        }
//        let invoice = Invoice(qrCodeText)
//        guard let _ = invoice.address, let _ = invoice.recipientsNpub, let _ = invoice.amount else {
//            return nil
//        }
//        return invoice
//    }
    
//    private func handlePaste() -> Invoice? {
//#if os(macOS)
//        let pasteboard = NSPasteboard.general
//        guard let url = pasteboard.pasteboardItems?.first?.string(forType: .string) else {
//            let type = NSPasteboard.PasteboardType.tiff
//            guard let imgData = pasteboard.data(forType: type) else { return nil }
//            let ciImage: CIImage = CIImage(nsImage: NSImage(data: imgData)!)
//            return invoiceFromQrImage(ciImage: ciImage)
//        }
//        
//        let invoice = Invoice(url)
//        guard let _ = invoice.address, let _ = invoice.amount, let _ = invoice.recipientsNpub else { return nil }
//        return invoice
//        
//#elseif os(iOS)
//        let pasteboard = UIPasteboard.general
//        guard let image = pasteboard.image else {
//            guard let text = pasteboard.string else { return nil }
//            let invoice = Invoice(text)
//            guard let _ = invoice.address, let _ = invoice.amount, let _ = invoice.recipientsNpub else { return nil }
//            return invoice
//        }
//        guard let ciImage = image.ciImage, let invoice = invoiceFromQrImage(ciImage: ciImage) else { return nil }
//        return invoice
//#endif
//    }
    
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
                if let confs = utxo.confs, confs > 0,
                   let solvable = utxo.solvable, solvable {
                    spendable = true
                    utxos.append(utxo)
                }
            }
            if spendable {
                showUtxos = true
            }
        }
    }
}


struct UploadInvoiceView: View {
    @State private var isShowingScanner = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var selectedImage: Image?
    
    @Binding var uploadedInvoice: Invoice?
    @Binding var invoiceUploaded: Bool
        
    var body: some View {
        HStack {
            PhotosPicker("Photo Library", selection: $pickerItem, matching: .images)
                .onChange(of: pickerItem) {
                    Task {
                        selectedImage = try await pickerItem?.loadTransferable(type: Image.self)
                        #if os(macOS)
                        let ciImage: CIImage = CIImage(nsImage: selectedImage!.renderAsImage()!)
                        #elseif os(iOS)
                        let ciImage: CIImage = CIImage(uiImage: selectedImage!.asUIImage())
                        #endif
                        uploadedInvoice = invoiceFromQrImage(ciImage: ciImage)
                        invoiceUploaded = true
                    }
                }
            #if os(iOS)
            // Can't scan QR on macOS with SwiftUI...
            Button("Scan QR", systemImage: "qrcode.viewfinder") {
                isShowingScanner = true
            }
//                .onTapGesture {
//                    
//                }
                .sheet(isPresented: $isShowingScanner) {
                    CodeScannerView(codeTypes: [.qr], simulatedData: "", completion: handleScan)
                }
            #endif
            Button("Paste", systemImage: "doc.on.clipboard") {
                uploadedInvoice = handlePaste()
                invoiceUploaded = true
            }
        }
        .buttonStyle(.bordered)
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
    
}


struct SpendableUtxosView: View, DirectMessageEncrypting {
    private let urlString = UserDefaults.standard.string(forKey: "nostrRelay") ?? "wss://relay.damus.io"
    @State private var spendableBalance = 0.0
    @State private var signedRawTx: String?
    @State private var txid: String?
    @State private var copied = false
    
    let utxos: [Utxo]
    let uploadedInvoice: Invoice?
    
    init(utxos: [Utxo], uploadedInvoice: Invoice?) {
        self.utxos = utxos
        self.uploadedInvoice = uploadedInvoice
    }
    
    var body: some View {
        Section("Spendable UTXOs") {
            ForEach(Array(utxos.enumerated()), id: \.offset) { (index, utxo) in
                if let address = utxo.address, let amount = utxo.amount,
                    let confs = utxo.confs, confs > 0 {
                    let textLabel = address + ": " + "\(amount)" + " btc"
                    HStack {
                        Text(textLabel)
                        
                        if let uploadedInvoice = uploadedInvoice {
                            Button("Pay Join this UTXO") {
                                payInvoice(invoice: uploadedInvoice, utxo: utxo, utxos: utxos)
                            }
                            .buttonStyle(.bordered)
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
        if let signedRawTx = signedRawTx {
            Section("Signed Tx") {
                Text(signedRawTx)
                ShareLink(" ", item: signedRawTx)
                Button(" ", systemImage: "doc.on.doc") {
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(signedRawTx, forType: .string)
                    #elseif os(iOS)
                    UIPasteboard.general.string = signedRawTx
                    #endif
                    copied = true
                }
                
                Button("Broadcast") {
                    let p = Send_Raw_Transaction(["hexstring": signedRawTx])
                    BitcoinCoreRPC.shared.btcRPC(method: .sendrawtransaction(p)) { (response, errorDesc) in
                        guard let response = response as? String else {
                            print("error sending")
                            return
                        }
                        txid = response
                    }
                }
            }
            .buttonStyle(.bordered)
            .alert("Copied ✓", isPresented: $copied) {}
            
            if let txid = txid {
                Text("Transaction sent ✓")
                Text("txid: \(txid)")
            }
                
        }
            
    }
    
    
    private func payInvoice(invoice: Invoice, utxo: Utxo, utxos: [Utxo]) {
        let inputs = [["txid": utxo.txid, "vout": utxo.vout]]
        let outputs = [[invoice.address!: "\(invoice.amount!)"]]
        var options:[String:Any] = [:]
        options["includeWatching"] = true
        options["replaceable"] = true
        options["add_inputs"] = true
        let dict: [String:Any] = ["inputs": inputs, "outputs": outputs, "options": options, "bip32derivs": false]
        let p = Wallet_Create_Funded_Psbt(dict)
        BitcoinCoreRPC.shared.btcRPC(method: .walletcreatefundedpsbt(param: p)) { (response, errorDesc) in
            guard let response = response as? [String: Any], let psbt = response["psbt"] as? String else {
                print("error from btc core")
                return
            }
            Signer.sign(psbt: psbt, passphrase: nil, completion: { (signedPsbt, rawTx, errorMessage) in
                guard let signedPsbt = signedPsbt else {
                    print("psbt not signed")
                    return
                }
                let param = Test_Mempool_Accept(["rawtxs":[rawTx]])
                BitcoinCoreRPC.shared.btcRPC(method: .testmempoolaccept(param)) { (response, errorDesc) in
                    guard let response = response as? [[String: Any]],
                          let allowed = response[0]["allowed"] as? Bool, allowed else {
                        return
                    }
                    DataManager.retrieve(entityName: "Credentials") { dict in
                        guard let dict = dict, let encPrivKey = dict["nostrPrivkey"] as? Data else { return }
                        guard let decPrivkey = Crypto.decrypt(encPrivKey) else { return }
                        let ourKeypair = Keypair(privateKey: PrivateKey(dataRepresentation: decPrivkey)!)!
                        guard let recipientsNpub = invoice.recipientsNpub else {
                            print("unable to init our keypair or recipient npub")
                            return
                        }
                        guard let encPsbt = encryptedMessage(ourKeypair: ourKeypair,
                                                             receiversNpub: recipientsNpub,
                                                             message: signedPsbt) else {
                            print("psbt encryption failed")
                            return
                        }
                        guard let _ = PublicKey(npub: recipientsNpub) else { return }
                        let urlString = UserDefaults.standard.string(forKey: "nostrRelay") ?? "wss://relay.damus.io"
                        StreamManager.shared.closeWebSocket()
                        StreamManager.shared.openWebSocket(relayUrlString: urlString)
                        StreamManager.shared.eoseReceivedBlock = { _ in
                            StreamManager.shared.writeEvent(content: encPsbt, recipientNpub: recipientsNpub)
                        }
                        StreamManager.shared.errorReceivedBlock = { nostrError in
                            print("nostr received error: \(nostrError)")
                        }
                        StreamManager.shared.onDoneBlock = { nostrResponse in
                            guard let response = nostrResponse.response as? String else {
                                print("nostr response error: \(nostrResponse.errorDesc ?? "unknown error")")
                                return
                            }
                            guard let peerNpub = UserDefaults.standard.object(forKey: "peerNpub") as? String else  {
                                return
                            }
                            guard let decryptedMessage = try? decrypt(encryptedContent: response,
                                                                      privateKey: ourKeypair.privateKey,
                                                                      publicKey: PublicKey(npub: peerNpub)!) else {
                                print("failed decrypting")
                                return
                            }
                            if let payjoinProposal = try? PSBT(psbt: decryptedMessage, network: .testnet),
                                let originalPsbt = try? PSBT(psbt: psbt, network: .testnet) {
                                // now we inpsect it and sign it.
                                // Verify that the absolute fee of the payjoin proposal is equals or higher than the original PSBT.
                                let payjoinProposalAbsoluteFee = Double(payjoinProposal.fee!) / 100000000.0
                                let originalPsbtAbsFee = Double(originalPsbt.fee!) / 100000000.0
                                guard payjoinProposalAbsoluteFee >= originalPsbtAbsFee else {
                                    print("fee is smaller then original psbt, ignore.")
                                    return
                                }
                                let paramProposal = Decode_Psbt(["psbt": payjoinProposal.description])
                                BitcoinCoreRPC.shared.btcRPC(method: .decodepsbt(param: paramProposal)) { (responseProp, errorDesc) in
                                    guard let responseProp = responseProp as? [String: Any] else { return }
                                    let decodedPayjoinProposal = DecodedPsbt(responseProp)
                                    let paramOrig = Decode_Psbt(["psbt": originalPsbt.description])
                                    BitcoinCoreRPC.shared.btcRPC(method: .decodepsbt(param: paramOrig)) { (responseOrig, errorDesc) in
                                        guard let responseOrig = responseOrig as? [String: Any] else { return }
                                        let decodedOriginalPsbt = DecodedPsbt(responseOrig)
                                        guard decodedPayjoinProposal.txLocktime == decodedOriginalPsbt.txLocktime else {
                                            print("locktimes don't match.")
                                            return
                                        }
                                        guard decodedOriginalPsbt.psbtVersion == decodedPayjoinProposal.psbtVersion else {
                                            print("psbt versions don't match.")
                                            return
                                        }
                                        var proposedPsbtIncludesOurInput = false
                                        var additionaInputPresent = false
                                        for proposedInput in decodedPayjoinProposal.txInputs {
                                            if proposedInput["txid"] as! String == utxo.txid && proposedInput["vout"] as! Int == utxo.vout {
                                                proposedPsbtIncludesOurInput = true
                                            }
                                            // loop utxos to ensure no other inputs belong to us.
                                            for ourUtxo in utxos {
                                                if ourUtxo.txid != utxo.txid,
                                                   ourUtxo.vout != utxo.vout,
                                                   ourUtxo.txid == proposedInput["txid"] as! String,
                                                   ourUtxo.vout == proposedInput["vout"] as! Int {
                                                    additionaInputPresent = true
                                                }
                                            }
                                        }
                                        guard !additionaInputPresent else {
                                            print("yikes, this psbt is trying to get us to sign inputs we didn't add...")
                                            return
                                        }
                                        guard proposedPsbtIncludesOurInput else {
                                            print("proposedPsbt does not include the original input.")
                                            return
                                        }
                                        // Check that the sender's inputs' sequence numbers are unchanged.
                                        var sendersSeqNumUnChanged = true
                                        var sameSeqNums = true
                                        var prevSeqNum: Int? = nil
                                        for originalInput in decodedOriginalPsbt.txInputs {
                                            for proposedInput in decodedPayjoinProposal.txInputs {
                                                let seqNum = proposedInput["sequence"] as! Int
                                                if let prevSeqNum = prevSeqNum {
                                                    if !(prevSeqNum == seqNum) {
                                                        sameSeqNums = false
                                                    }
                                                } else {
                                                    prevSeqNum = seqNum
                                                }
                                                if originalInput["txid"] as! String == proposedInput["txid"] as! String,
                                                   originalInput["vout"] as! Int == proposedInput["vout"] as! Int {
                                                    if !(originalInput["sequence"] as! Int == proposedInput["sequence"] as! Int) {
                                                        sendersSeqNumUnChanged = false
                                                    } else {
                                                        print("seq number unchanged")
                                                    }
                                                }
                                            }
                                        }
                                        guard sameSeqNums else {
                                            print("sequence numbers not similiar")
                                            return
                                        }
                                        guard sendersSeqNumUnChanged else {
                                            print("Sequence numbers changed.")
                                            return
                                        }
                                        var inputsAreSegwit = true
                                        for input in payjoinProposal.inputs {
                                            if !input.isSegwit {
                                                inputsAreSegwit = false
                                            }
                                        }
                                        var outputsAreSegwit = true
                                        var originalOutputChanged = true
                                        for proposedOutput in payjoinProposal.outputs {
                                            if !(proposedOutput.txOutput.scriptPubKey.type == .payToWitnessPubKeyHash) {
                                                outputsAreSegwit = false
                                            }
                                            if proposedOutput.txOutput.address == invoice.address!,
                                               Double(proposedOutput.txOutput.amount) / 100000000.0 == invoice.amount! {
                                                originalOutputChanged = false
                                            }
                                        }
                                        var originalOutputsIncluded = false
                                        for (i, originalOutput) in originalPsbt.outputs.enumerated() {
                                            var outputsMatch = false
                                            
                                            for proposedOutput in payjoinProposal.outputs {
                                                if proposedOutput.txOutput.amount == originalOutput.txOutput.amount,
                                                   proposedOutput.txOutput.address == originalOutput.txOutput.address {
                                                    outputsMatch = true
                                                }
                                            }
                                            
                                            if outputsMatch && i + 1 == originalPsbt.outputs.count {
                                                originalOutputsIncluded = outputsMatch
                                            }
                                        }
                                        guard originalOutputsIncluded else {
                                            print("not all original outputs included")
                                            return
                                        }
                                        guard !originalOutputChanged else {
                                            print("yikes, someone altered the original invoice output")
                                            return
                                        }
                                        guard inputsAreSegwit, outputsAreSegwit else {
                                            print("something not segwit")
                                            return
                                        }
                                        Signer.sign(psbt: payjoinProposal.description, passphrase: nil) { (psbt, rawTx, errorMessage) in
                                            let p = Test_Mempool_Accept(["rawtxs": [rawTx]])
                                            BitcoinCoreRPC.shared.btcRPC(method: .testmempoolaccept(p)) { (response, errorDesc) in
                                                guard let response = response as? [[String: Any]], let allowed = response[0]["allowed"] as? Bool, allowed else {
                                                    print("not accepted by mempool")
                                                    return
                                                }
                                                signedRawTx = rawTx
                                            }
                                        }
                                    }
                                }
                                /*
                                 For each inputs in the proposal:
                                 Verify that no keypaths is in the PSBT input
                                 Verify that no partial signature has been filled
                                 
                                 If it is one of the sender's input
                                 Verify that input's sequence is unchanged.
                                 Verify the PSBT input is not finalized
                                 Verify that non_witness_utxo and witness_utxo are not specified.
                                 
                                 If it is one of the receiver's input
                                 Verify the PSBT input is finalized
                                 Verify that non_witness_utxo or witness_utxo are filled in.
                                 Verify that the payjoin proposal did not introduced mixed input's sequence.
                                 Verify that the payjoin proposal did not introduced mixed input's type.
                                 Verify that all of sender's inputs from the original PSBT are in the proposal.
                                 
                                 If the receiver's BIP21 signalled pjos=0, disable payment output substitution.
                                 
                                 For each outputs in the proposal:
                                 Verify that no keypaths is in the PSBT output
                                 If the output is the fee output:
                                 The amount that was substracted from the output's value is less than or equal to maxadditionalfeecontribution. Let's call this amount actual contribution.
                                 Make sure the actual contribution is only paying fee: The actual contribution is less than or equals to the difference of absolute fee between the payjoin proposal and the original PSBT.
                                 Make sure the actual contribution is only paying for fee incurred by additional inputs: actual contribution is less than or equals to originalPSBTFeeRate * vsize(sender_input_type) * (count(payjoin_proposal_inputs) - count(original_psbt_inputs)). (see Fee output section)
                                 If the output is the payment output and payment output substitution is allowed.
                                 Do not make any check
                                 Else
                                 Make sure the output's value did not decrease.
                                 Verify that all sender's outputs (ie, all outputs except the output actually paid to the receiver) from the original PSBT are in the proposal.
                                 Once the proposal is signed, if minfeerate was specified, check that the fee rate of the payjoin transaction is not less than this value.
                                 The sender must be careful to only sign the inputs that were present in the original PSBT and nothing else.
                                 Note:
                                 
                                 The sender must allow the receiver to add/remove or modify the receiver's own outputs. (if payment output substitution is disabled, the receiver's outputs must not be removed or decreased in value)
                                 The sender should allow the receiver to not add any inputs. This is useful for the receiver to change the paymout output scriptPubKey type.
                                 If no input have been added, the sender's wallet implementation should accept the payjoin proposal, but not mark the transaction as an actual payjoin in the user interface.
                                 Our method of checking the fee allows the receiver and the sender to batch payments in the payjoin transaction. It also allows the receiver to pay the fee for batching adding his own outputs.
                                 */
                            }
                        }
                    }
                }
            })
        }
    }
    
    
    private func encryptedMessage(ourKeypair: Keypair, receiversNpub: String, message: String) -> String? {
        guard let receiversPubKey = PublicKey(npub: receiversNpub) else {
            return nil
        }
        guard let encryptedMessage = try? encrypt(content: message,
                                                  privateKey: ourKeypair.privateKey,
                                                  publicKey: receiversPubKey) else { return nil }
        return encryptedMessage
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
