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
                print("Downloaded: \(response.messages.count) messages")
                let allMessages = saveNewFetchedMessages(planter: planter, apiMessages: response.messages)
                completion(.success(allMessages))
            case .failure(let error):
                print("Networking Error: \(error.localizedDescription)")
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
                
                guard let self else { return }
                if let messages = coreDataManager.perform(fetchRequest: messagesUnread(for: planter)) {
                    completion(messages.count)
                } else {
                    completion(0)
                }
            }
        }
    }

    func getSavedMessages(planter: Planter) -> [MessageEntity] {
        if let messages = coreDataManager.perform(fetchRequest: allMessages(for: planter)) {
            return messages
        }

        return []
    }

    // MARK: - Private actions
    private func saveNewFetchedMessages(planter: Planter, apiMessages: [Message]) -> [MessageEntity] {

        var newMessages: [Message] = []
        var returnMessages: [MessageEntity] = []

        if let savedMessages = coreDataManager.perform(fetchRequest: allMessages(for: planter)) {
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

            // TODO: Get planterIdentification and delete this entity bellow? Make the link in coreData?
            newMessage.identifier = planter.identifier
            newMessage.unread = true

            // TODO: add survey & surverResponse variables to coredata.
            returnMessages.append(newMessage)
        }

        coreDataManager.saveContext()
        
        return returnMessages
    }
}

// MARK: - Fetch Requests
extension MessagingService {

    func allMessages(for planter: Planter) -> NSFetchRequest<MessageEntity> {
        let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "identifier == %@", planter.identifier ?? "")
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "composedAt", ascending: true)]
        return fetchRequest
    }

    func messagesUnread(for planter: Planter) -> NSFetchRequest<MessageEntity> {
        let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "identifier == %@", planter.identifier ?? ""),
            NSPredicate(format: "unread == true")
        ])
        return fetchRequest
    }

}
