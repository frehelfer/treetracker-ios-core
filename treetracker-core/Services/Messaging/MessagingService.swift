//
//  MessagingService.swift
//  Pods
//
//  Created by Alex Cornforth on 03/04/2023.
//

import Foundation
import CoreData

public protocol MessagingService {
    func syncMessages(for planter: Planter)
    func getSavedMessages(planter: Planter) -> [MessageEntity]
    func getMessagesToPresent(planter: Planter, offset: Int) -> [MessageEntity]
    func updateUnreadMessages(messages: [MessageEntity]) -> [MessageEntity]
    func createMessage(planter: Planter, text: String) throws -> MessageEntity
}

// MARK: - Errors
public enum MessagingServiceError: Swift.Error {
    case missingPlanterIdentifier
    case noMessagesToUpload
}

class RemoteMessagesService: MessagingService {

    private let apiService: APIServiceProtocol
    private let coreDataManager: CoreDataManaging

    init(apiService: APIServiceProtocol, coreDataManager: CoreDataManaging) {
        self.apiService = apiService
        self.coreDataManager = coreDataManager
    }

    // MARK: - Sync Messages with Server
    func syncMessages(for planter: Planter) {

        // TODO: change to planter.identifier
        guard let walletHandle = planter.firstName,
            let planter = planter as? PlanterDetail,
            let planterIdentification = planter.latestIdentification as? PlanterIdentification else {
            return
        }

        let lastSyncMessage = coreDataManager.perform(fetchRequest: lastSyncMessage(for: planterIdentification))
        let lastSyncTime = lastSyncMessage?.first?.composedAt ?? .distantPast

        let request = GetMessagesRequest(
            walletHandle: walletHandle,
            lastSyncTime: lastSyncTime,
            limit: 50
        )

        apiService.performAPIRequest(request: request) { [weak self] result in
            switch result {
            case .success(let response):
                guard let self, let response else { return }
                saveMessages(planter: planter, newMessages: response.messages)
                print("🟢 Fetched \(response.messages.count) remote messages")

                if let nextPage = response.links.next {
                    getNextPageMessages(planter: planter, path: nextPage)
                } else {
                    postMessages()
                }

            case .failure(let error):
                print("🚨 Get remote message Error: \(error)")
            }
        }
    }

    private func getNextPageMessages(planter: Planter, path: String) {

        let request = GetNextMessagesRequest(path: path)

        apiService.performAPIRequest(request: request) { [weak self] result in
            switch result {
            case .success(let response):
                guard let self, let response else { return }
                saveMessages(planter: planter, newMessages: response.messages)
                print("🟢 Fetched \(response.messages.count) remote messages on next page.")

                if let nextPage = response.links.next {
                    getNextPageMessages(planter: planter, path: nextPage)
                } else {
                    postMessages()
                }

            case .failure(let error):
                print("🚨 Get remote next page message Error: \(error)")
            }
        }
    }

    private func postMessages() {

        guard let messagesToPost = coreDataManager.perform(fetchRequest: messagesToUpload),
              !messagesToPost.isEmpty else {
            print("✌️ no messages to upload")
            return
        }

        postMessage(messagesToPost: messagesToPost)
    }

    private func postMessage(messagesToPost: [MessageEntity]) {
        guard let message = messagesToPost.last else { return }
        var messages = messagesToPost

        let request = PostMessagesRequest(message: message)

        apiService.performAPIRequest(request: request) { [weak self] result in
            switch result {
            case .success(_):
                guard let self else { return }
                updateUploadedMessage(message)
                print("✅ Upload Messages Successfully")
                messages.removeLast()
                postMessage(messagesToPost: messages)
   
            case .failure(let error):
                print("🚨 Post Message Error: \(error)")
            }
        }
    }

    // MARK: - Update Messages on DB
    private func updateUploadedMessage(_ message: MessageEntity) {
        message.uploaded = true
        coreDataManager.saveContext()
    }

    func updateUnreadMessages(messages: [MessageEntity]) -> [MessageEntity] {
        messages.forEach { message in
            if message.unread == true {
                message.unread = false
            }
        }
        coreDataManager.saveContext()
        return messages
    }

    // MARK: - Save Messages on DB
    private func saveMessages(planter: Planter, newMessages: [Message]) {

        guard let planter = planter as? PlanterDetail,
              let planterIdentification = planter.latestIdentification as? PlanterIdentification else {
            return
        }

        for message in newMessages {
            let newMessage = MessageEntity(context: coreDataManager.viewContext)
            newMessage.messageId = message.messageId
            newMessage.parentMessageId = message.parentMessageId
            newMessage.from = message.from
            newMessage.to = message.to
            newMessage.subject = message.subject
            newMessage.body = message.body
            newMessage.type = message.type.rawValue
            newMessage.composedAt = message.composedAt
            newMessage.videoLink = message.videoLink

            newMessage.uploaded = true
            newMessage.unread = true

            planterIdentification.addToMessages(newMessage)
            // TODO: add survey & surverResponse variables to coredata.
        }

        coreDataManager.saveContext()
    }

    // MARK: - Get Messages from DB
    func getSavedMessages(planter: Planter) -> [MessageEntity] {

        guard
            let planter = planter as? PlanterDetail,
            let latestPlanterIdentification = planter.latestIdentification as? PlanterIdentification
        else {
            return []
        }

        if let messages = coreDataManager.perform(fetchRequest: allMessages(for: latestPlanterIdentification)) {
            return messages
        }

        return []
    }

    func getMessagesToPresent(planter: Planter, offset: Int) -> [MessageEntity] {

        guard let planter = planter as? PlanterDetail,
              let planterIdentification = planter.latestIdentification as? PlanterIdentification else {
            return []
        }

        if var messages = coreDataManager.perform(fetchRequest: messagesToPresent(for: planterIdentification, offset: offset)) {
            messages.reverse()
            return messages
        }

        return []

    }

    // MARK: - Create New Message
    func createMessage(planter: Planter, text: String) throws -> MessageEntity {
 
        // TODO: change to planter.identifier
        guard
            let handle = planter.firstName,
            let planter = planter as? PlanterDetail,
            let latestPlanterIdentification = planter.latestIdentification as? PlanterIdentification
        else {
            throw MessagingServiceError.missingPlanterIdentifier
        }

        let newMessage = MessageEntity(context: coreDataManager.viewContext)
        newMessage.messageId = UUID().uuidString.lowercased()
        newMessage.type = "message"
        newMessage.parentMessageId = nil
        newMessage.from = handle
        newMessage.to = "admin"
        newMessage.subject = nil
        newMessage.body = text
        newMessage.composedAt = Date()
        newMessage.videoLink = nil

        newMessage.uploaded = false
        newMessage.unread = false

        latestPlanterIdentification.addToMessages(newMessage)

        coreDataManager.saveContext()
        return newMessage
    }
}

// MARK: - Fetch Requests
extension MessagingService {

    func allMessages(for planterIdentification: PlanterIdentification) -> NSFetchRequest<MessageEntity> {
        let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "planterIdentification == %@", planterIdentification)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "composedAt", ascending: true)]
        return fetchRequest
    }

    func messagesToPresent(for planterIdentification: PlanterIdentification, offset: Int) -> NSFetchRequest<MessageEntity> {
        let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "planterIdentification == %@", planterIdentification),
            NSPredicate(format: "type == %@", "message")
        ])
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "composedAt", ascending: false)]
        fetchRequest.fetchLimit = 40
        fetchRequest.fetchOffset = offset
        return fetchRequest
    }

    func messagesUnread(for planterIdentification: PlanterIdentification) -> NSFetchRequest<MessageEntity> {
        let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "planterIdentification == %@", planterIdentification),
            NSPredicate(format: "unread == true")
        ])
        return fetchRequest
    }

    var messagesToUpload: NSFetchRequest<MessageEntity> {
        let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "uploaded == false")
        return fetchRequest
    }

    func lastSyncMessage(for planterIdentification: PlanterIdentification) -> NSFetchRequest<MessageEntity> {
        let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "planterIdentification == %@", planterIdentification),
            NSPredicate(format: "uploaded == true")
        ])
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "composedAt", ascending: false)]
        fetchRequest.fetchLimit = 1
        return fetchRequest
    }
}
