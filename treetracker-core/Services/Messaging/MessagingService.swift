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
    func getUnreadMessagesCount() -> Int?
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
                self?.saveNewFetchedMessages(apiMessages: response.messages)
                completion(.success(response.messages))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func getUnreadMessagesCount() -> Int? {
        if let messages = coreDataManager.perform(fetchRequest: messagesUnread) {
            return messages.count
        } else {
            return nil
        }
        
    }
    
    // MARK: - Private actions
    private func saveNewFetchedMessages(apiMessages: [Message]) {
        
        var newMessages: [Message] = []
        
        // fetch messagens from coreData
        if let savedMessages = coreDataManager.perform(fetchRequest: allMessages) {
            
            // check if downloaded messagens exists in coreData
            for apiMessage in apiMessages {
                if !savedMessages.contains(where: { $0.messageId == apiMessage.messageId }) {
                    newMessages.append(apiMessage)
                }
            }
            
        } else {
            newMessages = apiMessages
        }
        
        // save new messages on coreData
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
            
            newMessage.unread = true
            
            // TODO: add survey & surverResponse variables to coredata.
        }
        
        // save new messages
        coreDataManager.saveContext()
    }
}

// MARK: - Fetch Requests
extension MessagingService {
    
    var allMessages: NSFetchRequest<MessageEntity> {
        let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
        return fetchRequest
    }
    
    var messagesUnread: NSFetchRequest<MessageEntity> {
        let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "unread == true")
        return fetchRequest
    }
    
}
