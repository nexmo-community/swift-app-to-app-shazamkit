//
//  ChatViewController.swift
//  AppToAppChat
//
//  Created by Abdulhakim Ajetunmobi on 20/07/2020.
//  Copyright © 2020 Vonage. All rights reserved.
//

import UIKit
import ShazamKit
import NexmoClient
import AVFoundation

class ChatViewController: UIViewController {
    
    let client = NXMClient.shared
    
    let user: User
    
    let inputField = UITextField()
    let conversationTextView = UITextView()
    
    let session = SHSession()
    let audioEngine = AVAudioEngine()
    var lastMatchID: String = ""
    
    var conversation: NXMConversation?
    var events: [NXMEvent]? {
        didSet {
            processEvents()
        }
    }
    
    init(user: User) {
        self.user = user
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        session.delegate = self
        
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Logout", style: .done, target: self, action: #selector(self.logout))
        title = "Conversation with \(user.chatPartnerName)"
        
        conversationTextView.text = ""
        conversationTextView.translatesAutoresizingMaskIntoConstraints = false
        conversationTextView.isUserInteractionEnabled = false
        conversationTextView.backgroundColor = .lightGray
        view.addSubview(conversationTextView)
        
        inputField.delegate = self
        inputField.layer.borderWidth = 1
        inputField.layer.borderColor = UIColor.lightGray.cgColor
        inputField.returnKeyType = .send
        inputField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputField)
        
        
        NSLayoutConstraint.activate([
            conversationTextView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            conversationTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            conversationTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            conversationTextView.bottomAnchor.constraint(equalTo: inputField.topAnchor, constant: -20),
            
            inputField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            inputField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            inputField.heightAnchor.constraint(equalToConstant: 40),
            inputField.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor, constant: -20)
        ])
        
        getConversation()
        startAnalysingAudio()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardWasShown), name: UIResponder.keyboardDidShowNotification, object: nil)
    }
    
    @objc func logout() {
        client.logout()
        stopAnalysingAudio()
        dismiss(animated: true, completion: nil)
    }
    
    @objc func keyboardWasShown(notification: NSNotification) {
        if let kbSize = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.size {
            view.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: kbSize.height - 20, right: 0)
        }
    }
    
    func getConversation() {
        client.getConversationWithUuid(user.conversationId) { [weak self] (error, conversation) in
            self?.conversation = conversation
            if conversation != nil {
                self?.getEvents()
            }
            conversation?.delegate = self
        }
    }
    
    func getEvents() {
        guard let conversation = self.conversation else { return }
        conversation.getEventsPage(withSize: 100, order: .asc) { (error, page) in
            self.events = page?.events
        }
    }
    
    func processEvents() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.conversationTextView.text = ""
            self.events?.forEach { event in
                if let memberEvent = event as? NXMMemberEvent {
                    self.showMemberEvent(event: memberEvent)
                }
                if let textEvent = event as? NXMTextEvent {
                    self.showTextEvent(event: textEvent)
                }
            }
        }
    }
    
    func showMemberEvent(event: NXMMemberEvent) {
        switch event.state {
        case .invited:
            addConversationLine("\(event.member.user.name) was invited.")
        case .joined:
            addConversationLine("\(event.member.user.name) joined.")
        case .left:
            addConversationLine("\(event.member.user.name) left.")
        @unknown default:
            fatalError("Unknown member event state.")
        }
    }
    
    func showTextEvent(event: NXMTextEvent) {
        if let message = event.text {
            addConversationLine("\(event.fromMember?.user.name ?? "A user") said: '\(message)'")
        }
    }
    
    func addConversationLine(_ line: String) {
        if let text = conversationTextView.text, text.count > 0 {
            conversationTextView.text = "\(text)\n\(line)"
        } else {
            conversationTextView.text = line
        }
    }

    
    func send(message: String) {
        inputField.isEnabled = false
        conversation?.sendText(message, completionHandler: { [weak self] (error) in
            DispatchQueue.main.async { [weak self] in
                self?.inputField.isEnabled = true
            }
        })
    }

    func startAnalysingAudio() {
        let inputNode = audioEngine.inputNode
        let bus = 0
        inputNode.installTap(onBus: bus, bufferSize: 2048, format: inputNode.inputFormat(forBus: bus)) { (buffer: AVAudioPCMBuffer!, time: AVAudioTime!) -> Void in
            self.session.matchStreamingBuffer(buffer, at: time)
        }
        
        audioEngine.prepare()
        try! audioEngine.start()
    }
    
    func stopAnalysingAudio() {
        let inputNode = audioEngine.inputNode
        let bus = 0
        inputNode.removeTap(onBus: bus)
        self.audioEngine.stop()
    }

}

extension ChatViewController: SHSessionDelegate {
    func session(_ session: SHSession, didFind match: SHMatch) {
        if let matchedItem = match.mediaItems.first,
           let title = matchedItem.title,
           let artist = matchedItem.artist,
           let matchId = matchedItem.shazamID, matchId != lastMatchID {
            lastMatchID = matchId
            DispatchQueue.main.async {
                self.send(message: "I am currently listening to: \(title) by \(artist) - Via ShazamKit")
            }
        }
    }
    
    func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: Error?) {
        if error != nil {
            print(error as Any)
        }
    }
}

extension ChatViewController: NXMConversationDelegate {
    func conversation(_ conversation: NXMConversation, didReceive error: Error) {
        NSLog("Conversation error: \(error.localizedDescription)")
    }
    
    func conversation(_ conversation: NXMConversation, didReceive event: NXMTextEvent) {
        self.events?.append(event)
    }
}

extension ChatViewController: UITextFieldDelegate {
    func textFieldDidEndEditing(_ textField: UITextField) {
        view.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if let text = textField.text {
            send(message: text)
        }
        textField.text = ""
        textField.resignFirstResponder()
        return true
    }
    
}
