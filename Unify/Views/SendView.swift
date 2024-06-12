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
    
    var body: some View {
        Spacer()
        
        Label("Send", systemImage: "arrow.up.forward.circle")
        
        Form() {
            if !invoiceUploaded {
                Section("Invoice") {
                    UploadInvoiceView(uploadedInvoice: $uploadedInvoice, invoiceUploaded: $invoiceUploaded)
                }
                
            } else {
                Section("Invoice") {
                    if let uploadedInvoice = uploadedInvoice {
                        Label("\(uploadedInvoice.address!)", systemImage: "arrow.up.forward.circle")
                        
                        Label(uploadedInvoice.amount!.btcBalanceWithSpaces, systemImage: "bitcoinsign.circle")
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
        }
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
            Button {
                isShowingScanner = true
            } label: {
                Image(systemName: "qrcode.viewfinder")
            }
            .sheet(isPresented: $isShowingScanner) {
                CodeScannerView(codeTypes: [.qr], simulatedData: "", completion: handleScan)
            }
            #endif
            
            Button {
                uploadedInvoice = handlePaste()
                invoiceUploaded = true
            } label: {
                Image(systemName: "doc.on.clipboard")
            }
        }
        .buttonStyle(.bordered)
        
        Text("Select a method to upload an invoice.")
            .foregroundStyle(.tertiary)
        
        
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
        
        guard let _ = invoice.address, let _ = invoice.amount, let _ = invoice.recipientsNpub else {
            return nil
        }
        
        return invoice
        
#elseif os(iOS)
        let pasteboard = UIPasteboard.general
        
        guard let image = pasteboard.image else {
            guard let text = pasteboard.string else { return nil }
            let invoice = Invoice(text)
            guard let _ = invoice.address, let _ = invoice.amount, let _ = invoice.recipientsNpub else {
                return nil
            }
            
            return invoice
        }
        
        guard let ciImage = image.ciImage, let invoice = invoiceFromQrImage(ciImage: ciImage) else {
            return nil
        }
        
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
    @State private var inputs: [PSBTInput] = []
    @State private var outputs: [PSBTOutput] = []
    @State private var fee = ""
    @State private var signedPsbt = ""
    @State private var showingSheet = false
    
    let utxos: [Utxo]
    let uploadedInvoice: Invoice?
    
    init(utxos: [Utxo], uploadedInvoice: Invoice?) {
        self.utxos = utxos
        self.uploadedInvoice = uploadedInvoice
    }
    
    var body: some View {
        Section("Total Spendable Balance") {
            Text(spendableBalance.btcBalanceWithSpaces)
                .foregroundStyle(.secondary)
        }
        
        Section("Spendable UTXOs") {
            ForEach(Array(utxos.enumerated()), id: \.offset) { (index, utxo) in
                if let address = utxo.address, let amount = utxo.amount,
                   let confs = utxo.confs, confs > 0 {
                    let formattedAmount = amount.btcBalanceWithSpaces
                    let textLabel = address + "\n" + "\(formattedAmount)"
                    
                    HStack {
                        Text(textLabel)
                            .foregroundStyle(.secondary)
                        
                        if let uploadedInvoice = uploadedInvoice {
                            Button("Pay Invoice") {
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
            
            Text("Once an invoice is uploaded you will be prompted to select a utxo to pay with.")
                .foregroundStyle(.tertiary)
        }
        
        if let signedRawTx = signedRawTx {
            Section("Signed Tx") {
                Label("Raw transaction hex", systemImage: "doc.plaintext")
                
                HStack() {
                    Text(signedRawTx)
                        .truncationMode(.middle)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.secondary)
                    
                    Button {
                        #if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(signedRawTx, forType: .string)
                        #elseif os(iOS)
                        UIPasteboard.general.string = signedRawTx
                        #endif
                        copied = true
                        
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }
                
                Label("Signed PSBT base64", systemImage: "doc.plaintext.fill")
                
                HStack() {
                    Text(signedPsbt)
                        .truncationMode(.middle)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.secondary)
                    
                    Button {
                        #if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(signedPsbt, forType: .string)
                        #elseif os(iOS)
                        UIPasteboard.general.string = signedPsbt
                        #endif
                        copied = true
                        
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }
                
                ForEach(Array(inputs.enumerated()), id: \.offset) { (index, input) in
                    let inputAmount = (Double(input.amount!) / 100000000.0).btcBalanceWithSpaces
                    
                    HStack() {
                        Label("Input", systemImage: "arrow.down.right.circle")
                        Spacer()
                        Text(inputAmount)
                    }
                }
                
                ForEach(Array(outputs.enumerated()), id: \.offset) { (index, output) in
                    let btcAmount = (Double(output.txOutput.amount) / 100000000.0)
                    let outputAmount = btcAmount.btcBalanceWithSpaces
                    
                    if let outputAddress = output.txOutput.address {
                        let outputText = "\(outputAddress)\n\(outputAmount)"
                        let bold = outputAddress == uploadedInvoice!.address && btcAmount == uploadedInvoice!.amount!
                        
                        HStack() {
                            Label("Output", systemImage: "arrow.up.right.circle")
                            
                            Spacer()
                            
                            VStack(alignment: .trailing) {
                                if bold {
                                    Text(outputAddress)
                                        .bold(bold)
                                        .foregroundStyle(.primary)
                                    
                                    Text(outputAmount)
                                        .bold(bold)
                                        .foregroundStyle(.primary)
                                    
                                } else {
                                    Text(outputAddress)
                                        .bold(bold)
                                        .foregroundStyle(.secondary)
                                    
                                    Text(outputAmount)
                                        .bold(bold)
                                        .foregroundStyle(.secondary)
                                    
                                }
                            }
                        }
                    }
                }
                
                HStack() {
                    Label("Fee", systemImage: "bitcoinsign")
                    
                    Spacer()
                    
                    Text(fee)
                }
                
                Button("Broadcast") {
                    showingSheet = true
                }
                
                #if os(iOS)
                .fullScreenCover(isPresented: $showingSheet) {
                    SheetView(hexstring: signedRawTx, invoice: uploadedInvoice!)
                }
                #else
                .sheet(isPresented: $showingSheet) {
                    SheetView(hexstring: signedRawTx, invoice: uploadedInvoice!)
                }
                #endif
            }
            .buttonStyle(.bordered)
            .alert("Copied ✓", isPresented: $copied) {}
        }
    }
    
    
    private func payInvoice(invoice: Invoice, utxo: Utxo, utxos: [Utxo]) {
        let inputs = [["txid": utxo.txid, "vout": utxo.vout]]
        let outputs = [[invoice.address!: "\(invoice.amount!)"]]
        
        var options:[String:Any] = [:]
        options["includeWatching"] = true
        options["replaceable"] = true
        options["add_inputs"] = true
        
        let dict: [String:Any] = [
            "inputs": inputs,
            "outputs": outputs,
            "options": options,
            "bip32derivs": false
        ]
        
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
                    
                    guard let ourKeypair = Keypair() else {
                        return
                    }
                    
                    guard let recipientsNpub = invoice.recipientsNpub else {
                        return
                    }
                                        
                    guard let recipientsPubkey = PublicKey(npub: recipientsNpub) else {
                        return
                    }
                                        
                    let unencryptedContent = [
                        "psbt": signedPsbt,
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
                        print("converting to json string failed")
                        return
                    }
                    
                    guard let encEvent = try? encrypt(content: jsonString,
                                                      privateKey: ourKeypair.privateKey,
                                                      publicKey: recipientsPubkey) else {
                        return
                    }
                    
                    let urlString = UserDefaults.standard.string(forKey: "nostrRelay") ?? "wss://relay.damus.io"
                    
                    StreamManager.shared.closeWebSocket()
                    
                    StreamManager.shared.openWebSocket(relayUrlString: urlString, peerNpub: recipientsNpub, p: nil)
                    
                    StreamManager.shared.eoseReceivedBlock = { _ in
                        StreamManager.shared.writeEvent(content: encEvent, recipientNpub: recipientsNpub, ourKeypair: ourKeypair)
                        print("SEND: \(encEvent)")
                    }
                    
                    StreamManager.shared.errorReceivedBlock = { nostrError in
                        print("nostr received error: \(nostrError)")
                    }
                    
                    StreamManager.shared.onDoneBlock = { nostrResponse in
                        guard let content = nostrResponse.content else {
                            print("nostr response error: \(nostrResponse.errorDesc ?? "unknown error")")
                            return
                        }
                        
                        guard let decryptedMessage = try? decrypt(encryptedContent: content,
                                                                  privateKey: ourKeypair.privateKey,
                                                                  publicKey: recipientsPubkey) else {
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
                        
                        guard let payjoinProposalBase64 = eventContent.psbt else {
                            return
                        }
                        
                        if let payjoinProposal = try? PSBT(psbt: payjoinProposalBase64, network: .testnet),
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
                                guard let responseProp = responseProp as? [String: Any] else {
                                    return
                                }
                                
                                let decodedPayjoinProposal = DecodedPsbt(responseProp)
                                let paramOrig = Decode_Psbt(["psbt": originalPsbt.description])
                                
                                BitcoinCoreRPC.shared.btcRPC(method: .decodepsbt(param: paramOrig)) { (responseOrig, errorDesc) in
                                    guard let responseOrig = responseOrig as? [String: Any] else {
                                        return
                                    }
                                    
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
                                                
                                                print("proposed input which we didnt add is present")
                                                print(ourUtxo.txid + ":" + "\(ourUtxo.vout)")
                                                additionaInputPresent = true
                                            }
                                        }
                                    }
                                    
                                    guard !additionaInputPresent else {
                                        print("yikes, this psbt is trying to get us to sign an input of ours that we didn't add...")
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
                                        guard let rawTx = rawTx, let signedPsbt = psbt else {
                                            return
                                        }
                                        
                                        let p = Test_Mempool_Accept(["rawtxs": [rawTx]])
                                        
                                        BitcoinCoreRPC.shared.btcRPC(method: .testmempoolaccept(p)) { (response, errorDesc) in
                                            guard let response = response as? [[String: Any]],
                                                  let allowed = response[0]["allowed"] as? Bool,
                                                  allowed else {
                                                print("not accepted by mempool")
                                                return
                                            }
                                            
                                            guard let signedPsbt = try? PSBT(psbt: signedPsbt, network: .testnet) else {
                                                return
                                            }
                                            
                                            self.inputs = signedPsbt.inputs
                                            self.outputs = signedPsbt.outputs
                                            
                                            guard let fee = signedPsbt.fee else {
                                                return
                                            }
                                            
                                            self.fee = (Double(fee) / 100000000.0).btcBalanceWithSpaces
                                            self.signedPsbt = signedPsbt.description
                                            self.signedRawTx = rawTx
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            })
        }
    }
    
    
    struct SheetView: View {
        @Environment(\.dismiss) var dismiss
        @State private var txid: String?
        @State private var sending = false
        
        let hexstring: String
        let invoice: Invoice
        
        init(hexstring: String, invoice: Invoice) {
            self.hexstring = hexstring
            self.invoice = invoice
        }
        
        var body: some View {
            if txid == nil {
                if sending {
                    VStack() {
                        ProgressView()
                    }
                } else {
                    Form() {
                        List() {
                            HStack() {
                                Label("Amount", systemImage: "bitcoinsign")
                                
                                Spacer()
                                
                                Text(invoice.amount!.btcBalanceWithSpaces)
                            }
                            
                            HStack() {
                                Label("Address", systemImage: "arrow.up.forward.circle")
                                
                                Spacer()
                                
                                Text(invoice.address!)
                            }
                            
                            Text("Tap confirm to broadcast the transaction, this is final.")
                                .foregroundStyle(.secondary)
                            
                            HStack() {
                                Button("Cancel") {
                                    dismiss()
                                }
                                .padding()
                                .buttonStyle(.bordered)
                                
                                Button("Confirm") {
                                    sending = true
                                    broadcast()
                                }
                                .padding()
                                .buttonStyle(.bordered)
                            }
                            
                            Spacer()
                        }
                    }
                }
            } else if let txid = txid {
                Spacer()
                
                Image(systemName: "checkmark.circle")
                    .resizable()
                    .foregroundStyle(.green)
                    .frame(width: 100.0, height: 100.0)
                    .aspectRatio(contentMode: .fit)
                
                Spacer()
                
                Text("Transaction sent ✓")
                    .foregroundStyle(.primary)
                
                Text(txid)
                    .foregroundStyle(.secondary)
                    .padding()
                    .truncationMode(.middle)
                    .lineLimit(1)
                
                Button {
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(txid, forType: .string)
                    #elseif os(iOS)
                    UIPasteboard.general.string = txid
                    #endif
                } label: {
                    Text("Copy")
                }
                
                Spacer()
                
                Button("Dismiss") {
                    dismiss()
                }
                
                Spacer()
            }
        }
        
        private func broadcast() {
            let p = Send_Raw_Transaction(["hexstring": hexstring])
            
            BitcoinCoreRPC.shared.btcRPC(method: .sendrawtransaction(p)) { (response, errorDesc) in
                guard let response = response as? String else {
                    print("error sending")
                    return
                }
                
                txid = response
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
