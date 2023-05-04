//
//  MessagingService.swift
//  Pods
//
//  Created by Alex Cornforth on 03/04/2023.
//

import Foundation
import CoreData

public protocol MessagingService {
    func getMessages(planter: Planter, completion: @escaping (Result<[MessageEntity], Error>) -> Void)
    func getUnreadMessagesCount(for planter: Planter, completion: @escaping (Int) -> Void)
    func getSavedMessages(planter: Planter) -> [MessageEntity]
    func updateUnreadMessages(messages: [MessageEntity]) -> [MessageEntity]
    func createMessage(planter: Planter, text: String) throws -> MessageEntity
}

// MARK: - Errors
public enum MessagingServiceError: Swift.Error {
    case missingPlanterIdentifier
}

class RemoteMessagesService: MessagingService {

    private let apiService: APIServiceProtocol
    private let coreDataManager: CoreDataManaging

    init(apiService: APIServiceProtocol, coreDataManager: CoreDataManaging) {
        self.apiService = apiService
        self.coreDataManager = coreDataManager
    }

    // sync messages
    func getMessages(planter: Planter, completion: @escaping (Result<[MessageEntity], Error>) -> Void) {

        // TODO: change to planter.identifier
        guard let walletHandle = planter.firstName else {
            completion(.failure(MessagingServiceError.missingPlanterIdentifier))
            return
        }

        let request = GetMessagesRequest(
            walletHandle: walletHandle,
            lastSyncTime: .distantPast
        )

        apiService.performAPIRequest(request: request) { [weak self] result in
            switch result {
            case .success(let response):
                guard let self else { return }
                let allMessages = saveNewFetchedMessages(planter: planter, apiMessages: response.messages)
                completion(.success(allMessages))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func getUnreadMessagesCount(for planter: Planter, completion: @escaping (Int) -> Void) {
        
        getMessages(planter: planter) { [weak self] result in
            switch result {
            case .success(let allMessages):
                
                let count = allMessages.reduce(0) { $0 + ($1.unread ? 1 : 0) }
                completion(count)
                
            case .failure(_):
                
                guard
                    let self,
                    let planter = planter as? PlanterDetail,
                    let latestPlanterIdentification = planter.latestIdentification as? PlanterIdentification
                else {
                    completion(0)
                    return
                }
                
                if let messages = coreDataManager.perform(fetchRequest: messagesUnread(for: latestPlanterIdentification)) {
                    completion(messages.count)
                } else {
                    completion(0)
                }
            }
        }
    }

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

    func updateUnreadMessages(messages: [MessageEntity]) -> [MessageEntity] {
        messages.forEach({ $0.unread = false })
        coreDataManager.saveContext()
        return messages
    }
    
    func createMessage(planter: Planter, text: String) throws -> MessageEntity {
 
        // TODO: change to planter.identifier
        guard
            let handle = planter.firstName,
            let planter = planter as? PlanterDetail,
            let latestPlanterIdentification = planter.latestIdentification as? PlanterIdentification
        else {
            throw MessagingServiceError.missingPlanterIdentifier
        }

        let dateFormatter = ISO8601DateFormatter()
        let formattedDate = dateFormatter.string(from: Date())

        let newMessage = MessageEntity(context: coreDataManager.viewContext)
        newMessage.messageId = UUID().uuidString
        newMessage.type = "message"
        newMessage.parentMessageId = nil
        newMessage.from = handle
        newMessage.to = "admin"
        newMessage.subject = nil
        newMessage.body = text
        newMessage.composedAt = formattedDate
        newMessage.videoLink = nil

        newMessage.uploaded = false
        newMessage.unread = false

        latestPlanterIdentification.addToMessages(newMessage)

        coreDataManager.saveContext()
        return newMessage
    }

    // MARK: - Private actions
    private func saveNewFetchedMessages(planter: Planter, apiMessages: [Message]) -> [MessageEntity] {
        
        guard
            let planter = planter as? PlanterDetail,
            let latestPlanterIdentification = planter.latestIdentification as? PlanterIdentification
        else { return [] }

        var newMessages: [Message] = []
        var returnMessages: [MessageEntity] = []

        if let savedMessages = coreDataManager.perform(fetchRequest: allMessages(for: latestPlanterIdentification)) {
            returnMessages = savedMessages

            for apiMessage in apiMessages {
                if !savedMessages.contains(where: { $0.messageId == apiMessage.messageId }) {
                    newMessages.append(apiMessage)
                }
            }

        } else {
            newMessages = apiMessages
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

            latestPlanterIdentification.addToMessages(newMessage)
            // TODO: add survey & surverResponse variables to coredata.
            returnMessages.append(newMessage)
        }

        coreDataManager.saveContext()
        return returnMessages
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

    func messagesUnread(for planterIdentification: PlanterIdentification) -> NSFetchRequest<MessageEntity> {
        let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "planterIdentification == %@", planterIdentification),
            NSPredicate(format: "unread == true")
        ])
        return fetchRequest
    }

}
