//
//  StreamManager.swift
//  Pay Join
//
//  Created by Peter Denton on 2/14/24.
//

import Foundation
import NostrSDK

class StreamManager: NSObject {
        
    static let shared = StreamManager()
    var webSocket: URLSessionWebSocketTask?
    var opened = false
    var eoseReceivedBlock: (((Bool)) -> Void)?
    var errorReceivedBlock: (((String)) -> Void)?
    var pongReceivedBlock: (((Bool)) -> Void)?
    var onDoneBlock: (((response: Any?, errorDesc: String?)) -> Void)?
    let subId = Crypto.randomKey
    var connected = false
    var timer = Timer()
    
    
    private override init() {}
    
    
    func receive() {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard let webSocket = self.webSocket else { print("websocket is nil"); return }
            webSocket.receive(completionHandler: { [weak self] result in
                guard let self = self else { return }
                self.timer.invalidate()
                switch result {
                case .success(let message):
                    self.processMessage(message: message)
                case .failure(let error):
                    print("Error Receiving \(error)")
                }
                self.receive()
            })
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }
    
    
    private func processMessage(message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let strMessgae):
            let data = strMessgae.data(using: .utf8)!
            do {
                if let jsonArray = try JSONSerialization.jsonObject(with: data, options : .allowFragments) as? NSArray
                {
                    #if DEBUG
                    print("received: \(strMessgae)")
                    #endif
                    switch jsonArray[0] as? String {
                    case "EOSE":
                        parseEose(arr: jsonArray)
                    case "EVENT":
                        parseEventDict(arr: jsonArray)
                    case "OK":
                        onDoneBlock!((nil, jsonArray[3] as? String))
                    case "NOTICE":
                        guard let noticeDesc = jsonArray[1] as? String else { return }
                        errorReceivedBlock!(noticeDesc)
                    default:
                        break
                    }
                }
            } catch let error as NSError {
                print(error)
            }
        default:
            break
        }
    }
    
    
    private func parseEose(arr: NSArray) {
        guard let recievedSubId = arr[1] as? String else { print("subid not recieved"); return }
        guard self.subId == recievedSubId else { print("subid does not match"); return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.connected = true
            self.eoseReceivedBlock!(true)
        }
    }
    
    
    private func parseEventDict(arr: NSArray) {
        if let dict = arr[2] as? [String:Any], let created_at = dict["created_at"] as? Int, let _ = dict["id"] as? String {
            let now = NSDate().timeIntervalSince1970
            let diff = (now - TimeInterval(created_at))
            guard diff < 5.0 else { print("diff > 5, ignoring."); return }
            guard let ev = self.parseEvent(event: dict) else {
                self.onDoneBlock!((nil,"Nostr event parsing failed..."))
                #if DEBUG
                print("event parsing failed")
                #endif
                return
            }
            // decrypt and sort here, return psbt type so we know how to handle it?
            onDoneBlock!((ev.content, nil))
        }        
    }
    
    
    private func jsonFromDict(dict: [String:Any]) -> Data? {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted) else {
            #if DEBUG
            print("converting to jsonData failing...")
            #endif
            return nil
        }
        return jsonData
    }
    
    
    func subscribe() {
        print("subscribe")
        if let peerNpub = UserDefaults.standard.object(forKey: "peerNpub") as? String,
            let publicKey = PublicKey(npub: peerNpub) {
            
            let filter: NostrFilter = NostrFilter.filter_authors([publicKey.hex])
            let encoder = JSONEncoder()
            var req = "[\"REQ\",\"\(self.subId)\","
            guard let filter_json = try? encoder.encode(filter) else {
                #if DEBUG
                print("converting to jsonData failing...")
                #endif
                return
            }
            let filter_json_str = String(decoding: filter_json, as: UTF8.self)
            req += filter_json_str
            req += "]"
            print("req: \(req)")
            self.sendMsg(string: req)
        }
    }
    
    
    public func writeEvent(content: String, recipientNpub: String) {
        DataManager.retrieve(entityName: "Credentials") { dict in
            guard let dict = dict, let encNostrPrivkey = dict["nostrPrivkey"] as? Data else {
                return
            }
            
            guard let decPrivkey = Crypto.decrypt(encNostrPrivkey) else { return }
            
            guard let keypair = Keypair(privateKey: PrivateKey(dataRepresentation: decPrivkey)!) else { return }
            
            let pubkey = keypair.publicKey.hex
            let privkey = decPrivkey
            let recipientPubkey = PublicKey(npub: recipientNpub)!
            
            let ev = NostrEvent(content: content,
                                pubkey: pubkey,
                                kind: 4,
                                tags: [["p, \(recipientPubkey.hex)"]])
            
            print("send ev: \(ev)")
            ev.calculate_id()
            ev.sign(privkey: privkey)
            guard !ev.too_big else {
                self.onDoneBlock!((nil, "Nostr event is too big to send..."))
                #if DEBUG
                print("event too big: \(content.count)")
                #endif
                return
            }
            guard ev.validity == .ok else {
                self.onDoneBlock!((nil, "Nostr event is invalid!"))
                #if DEBUG
                print("event invalid")
                #endif
                return
            }
            let encoder = JSONEncoder()
            let event_data = try! encoder.encode(ev)
            let event = String(decoding: event_data, as: UTF8.self)
            let encoded = "[\"EVENT\",\(event)]"
            self.sendMsg(string: encoded)
        }
    }
    
    
    private func sendMsg(string: String) {
        let msg:URLSessionWebSocketTask.Message = .string(string)
        guard let ws = self.webSocket else { print("no websocket"); return }
        ws.send(msg, completionHandler: { [weak self] sendError in
            guard let self = self else { return }
            guard let sendError = sendError else {
                var seconds = 0
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { _ in
                        seconds += 1
                        self.updateCounting(seconds: seconds)
                    })
                }
                self.receive()
                return
            }
            #if DEBUG
            print("sendError: \(sendError.localizedDescription)")
            #endif
        })
    }
    
    
    private func parseEvent(event: [String:Any]) -> NostrEvent? {
        guard let content = event["content"] as? String else { return nil }
        guard let id = event["id"] as? String else { return nil }
        guard let kind = event["kind"] as? Int else { return nil }
        guard let pubkey = event["pubkey"] as? String else { return nil }
        guard let sig = event["sig"] as? String else { return nil }
        guard let tags = event["tags"] as? [[String]] else { return nil }
        let ev = NostrEvent(content: content,
                            pubkey: pubkey,
                            kind: kind,
                            tags: tags)
        ev.sig = sig
        ev.id = id
        return ev
    }
    
    
    private func updateCounting(seconds: Int) {
        if seconds == 30 {
            self.timer.invalidate()
            self.onDoneBlock!((nil, "Timed out after \(seconds) seconds, no response from your nostr relay..."))
        }
    }
    
    
    func openWebSocket(relayUrlString: String) {
        print("openWebSocket url: \(relayUrlString)")
        if let url = URL(string: relayUrlString) {
            let request = URLRequest(url: url)
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            self.webSocket = session.webSocketTask(with: request)
            self.opened = true
            self.webSocket?.resume()
        }
    }
    
    func closeWebSocket() {
        self.webSocket?.cancel(with: .goingAway, reason: nil)
        self.webSocket = nil
        self.opened = false
    }
    
    func pingWebsocket() {
        self.webSocket?.sendPing(pongReceiveHandler: { err in
            if err == nil {
                self.pongReceivedBlock!(true)
            } else {
                self.pongReceivedBlock!(false)
            }
        })
    }
}

extension StreamManager: URLSessionWebSocketDelegate {
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        opened = true
        subscribe()
    }
    
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("didCloseWith closeCode: \(closeCode)")
        webSocket = nil
        opened = false
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("DEBUG: didCompleteWithError called: error = \(error.localizedDescription)")
            closeWebSocket()
            errorReceivedBlock!(error.localizedDescription)
        }
    }
    
}
