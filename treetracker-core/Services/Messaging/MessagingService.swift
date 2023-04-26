//
//  MessagingService.swift
//  Pods
//
//  Created by Alex Cornforth on 03/04/2023.
//

import Foundation
import CoreData

public protocol MessagingService {
    func getMessages(planter: Planter, completion: @escaping (Result<[Message], Error>) -> Void)
    func getUnreadMessagesCount(planter: Planter) -> Int?
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

    func getMessages(planter: Planter, completion: @escaping (Result<[Message], Error>) -> Void) {

        guard let walletHandle = planter.identifier else {
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
                self?.saveNewFetchedMessages(planter: planter, apiMessages: response.messages)
                completion(.success(response.messages))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func getUnreadMessagesCount(planter: Planter) -> Int? {

        if let messages = coreDataManager.perform(fetchRequest: messagesUnread(for: planter)) {
            return messages.count
        } else {
            return nil
        }

    }

    func getSavedMessages(planter: Planter) -> [MessageEntity] {
        if let messages = coreDataManager.perform(fetchRequest: allMessages(for: planter)) {
            return messages
        }

        return []
    }

    // MARK: - Private actions
    private func saveNewFetchedMessages(planter: Planter, apiMessages: [Message]) {

        var newMessages: [Message] = []

        if let savedMessages = coreDataManager.perform(fetchRequest: allMessages(for: planter)) {

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
        }

        coreDataManager.saveContext()
    }
}

// MARK: - Fetch Requests
extension MessagingService {

    func allMessages(for planter: Planter) -> NSFetchRequest<MessageEntity> {
        let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "identifier == %@", planter.identifier ?? "")
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
