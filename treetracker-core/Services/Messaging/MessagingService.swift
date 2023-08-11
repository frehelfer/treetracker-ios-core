//
//  MessagingService.swift
//  Pods
//
//  Created by Alex Cornforth on 03/04/2023.
//

import Foundation
import CoreData

public protocol MessagingService {
    func syncMessages(for planter: Planter, completion: @escaping (Result<Void, Error>) -> Void)
    func updateUnreadMessages(messages: [MessageEntity])
    func getUnreadMessagesCount(for planter: Planter) -> Int
    func getChatListMessages(planter: Planter) -> [MessageEntity]
    func getMessagesToPresent(planter: Planter, offset: Int) -> [MessageEntity]
    func createMessage(planter: Planter, text: String) throws -> MessageEntity
    func createSurveyResponse(planter: Planter, surveyId: String, surveyResponse: [String])
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
    func syncMessages(for planter: Planter, completion: @escaping (Result<Void, Error>) -> Void) {

        guard let walletHandle = planter.identifier,
            let planter = planter as? PlanterDetail,
            let planterIdentification = planter.latestIdentification as? PlanterIdentification else {
            completion(.failure(MessagingServiceError.missingPlanterIdentifier))
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

                // just to debug - it removes the survey_response
                var messages: [Message] = []
                for message in response.messages {
                    if let surveyResponse = message.survey?.response {
                        if surveyResponse == false {
                            messages.append(message)
                        }
                    } else {
                        messages.append(message)
                    }
                }

                saveMessages(planter: planter, newMessages: messages)
                
                Logger.log("🟢 Fetched \(response.messages.count) remote messages")

                if let nextPage = response.links.next {
                    getNextPageMessages(planter: planter, path: nextPage) { result in
                        completion(result)
                    }
                } else {
                    postMessages { result in
                        completion(result)
                    }
                }

            case .failure(let error):
                Logger.log("🚨 Get remote message Error: \(error)")
                completion(.failure(error))
            }
        }
    }

    private func getNextPageMessages(planter: Planter, path: String, completion: @escaping (Result<Void, Error>) -> Void) {

        let request = GetNextMessagesRequest(path: path)

        apiService.performAPIRequest(request: request) { [weak self] result in
            switch result {
            case .success(let response):
                guard let self, let response else { return }

                // just to debug - it removes the survey_response
                var messages: [Message] = []
                for message in response.messages {
                    if let surveyResponse = message.survey?.response {
                        if surveyResponse == false {
                            messages.append(message)
                        }
                    } else {
                        messages.append(message)
                    }
                }

                saveMessages(planter: planter, newMessages: messages)
                Logger.log("🟢 Fetched \(response.messages.count) remote messages on next page.")

                if let nextPage = response.links.next {
                    getNextPageMessages(planter: planter, path: nextPage) { result in
                        completion(result)
                    }
                } else {
                    postMessages { result in
                        completion(result)
                    }
                }

            case .failure(let error):
                Logger.log("🚨 Get remote next page message Error: \(error)")
                completion(.failure(error))
            }
        }
    }

    private func postMessages(completion: @escaping (Result<Void, Error>) -> Void) {

        guard let messagesToPost = coreDataManager.perform(fetchRequest: messagesToUpload),
              !messagesToPost.isEmpty else {
            Logger.log("✌️ no messages to upload")
            completion(.success(()))
            return
        }

        postMessage(messagesToPost: messagesToPost) { result in
            completion(result)
        }
    }

    private func postMessage(messagesToPost: [MessageEntity], completion: @escaping (Result<Void, Error>) -> Void) {
        guard let message = messagesToPost.last else {
            completion(.success(()))
            return
        }
        var messages = messagesToPost

        let request = PostMessagesRequest(message: message)

        apiService.performAPIRequest(request: request) { [weak self] result in
            switch result {
            case .success(_):
                guard let self else { return }
                updateUploadedMessage(message)
                Logger.log("✅ Upload Messages Successfully")
                messages.removeLast()
                postMessage(messagesToPost: messages) { result in
                    completion(result)
                }
            case .failure(let error):
                Logger.log("🚨 Post Message Error: \(error)")
                completion(.failure(error))
            }
        }
    }

    // MARK: - Update Messages on DB
    private func updateUploadedMessage(_ message: MessageEntity) {
        message.uploaded = true
        coreDataManager.saveContext()
    }

    func updateUnreadMessages(messages: [MessageEntity]) {
        messages.forEach { message in
            if message.unread == true {
                message.unread = false
            }
        }
        coreDataManager.saveContext()
    }

    // MARK: - Save Messages on DB
    private func saveMessages(planter: Planter, newMessages: [Message]) {

        guard let planter = planter as? PlanterDetail,
              let planterIdentification = planter.latestIdentification as? PlanterIdentification,
              !newMessages.isEmpty else {
            return
        }

        planterIdentification.addToMessages(NSSet(array: newMessages.map({ message in
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
            newMessage.surveyResponse = message.surveyResponse
            newMessage.uploaded = true
            newMessage.unread = true
            newMessage.isHidden = false

            if let survey = message.survey {
                let newSurvey = SurveyEntity(context: coreDataManager.viewContext)
                newSurvey.uuid = survey.surveyId
                newSurvey.title = survey.title
                newSurvey.response = survey.response
                newSurvey.addToQuestions(NSOrderedSet(array: survey.questions.map { question in
                    let newSurveyQuestion = SurveyQuestion(context: coreDataManager.viewContext)
                    newSurveyQuestion.prompt = question.prompt
                    newSurveyQuestion.choices = question.choices
                    return newSurveyQuestion
                }))
                newMessage.survey = newSurvey
            }

            return newMessage
        })))

        // checks whether the survey has been answered and hides it
        if let surveyMessages: [MessageEntity] = coreDataManager.perform(fetchRequest: allSurveyMessages(for: planterIdentification)) {
            for currentMessage in surveyMessages {
                if !currentMessage.isHidden {
                    let currentUUID = currentMessage.survey?.uuid

                    for otherMessage in surveyMessages {
                        if currentMessage != otherMessage {

                            if otherMessage.survey?.uuid == currentUUID {
                                currentMessage.isHidden = true
                                currentMessage.unread = false
                                otherMessage.isHidden = true
                                otherMessage.unread = false
                                break
                            }
                        }
                    }
                }
            }
        }

        coreDataManager.saveContext()
    }

    // MARK: - Get Messages from DB
    func getChatListMessages(planter: Planter) -> [MessageEntity] {

        guard let planter = planter as? PlanterDetail,
              let planterIdentification = planter.latestIdentification as? PlanterIdentification else {
            return []
        }

        var otherTypeMessages: NSFetchRequest<MessageEntity> {
            let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
            fetchRequest.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "planterIdentification == %@", planterIdentification),
                    NSPredicate(format: "type == %@", "message"),
                    NSPredicate(format: "unread == true"),
                ]),
                NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "planterIdentification == %@", planterIdentification),
                    NSPredicate(format: "type != %@", "message"),
                    NSPredicate(format: "isHidden == false")
                ])
            ])
            return fetchRequest
        }

        var oneMessageOfTypeMessage: NSFetchRequest<MessageEntity> {
            let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "planterIdentification == %@", planterIdentification),
                NSPredicate(format: "type == %@", "message")
            ])
            fetchRequest.fetchLimit = 1
            return fetchRequest
        }

        let firstFetch = coreDataManager.perform(fetchRequest: otherTypeMessages) ?? []
        if !firstFetch.contains(where: { $0.type == "message" }) {
            let secondFetch = coreDataManager.perform(fetchRequest: oneMessageOfTypeMessage) ?? []
            return firstFetch + secondFetch
        }
        return firstFetch
    }

    func getMessagesToPresent(planter: Planter, offset: Int) -> [MessageEntity] {

        guard let planter = planter as? PlanterDetail,
              let planterIdentification = planter.latestIdentification as? PlanterIdentification else {
            return []
        }

        return coreDataManager.perform(fetchRequest: messagesToPresent(for: planterIdentification, offset: offset))?.reversed() ?? []
    }
    
    func getUnreadMessagesCount(for planter: Planter) -> Int {

        guard let planter = planter as? PlanterDetail,
              let planterIdentification = planter.latestIdentification as? PlanterIdentification else {
            return 0
        }

        let messages = coreDataManager.perform(fetchRequest: unreadMessages(for: planterIdentification)) ?? []
        return messages.count
    }

    // MARK: - Create New Message
    func createMessage(planter: Planter, text: String) throws -> MessageEntity {

        guard let handle = planter.identifier,
              let planter = planter as? PlanterDetail,
              let planterIdentification = planter.latestIdentification as? PlanterIdentification else {
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
        newMessage.isHidden = false

        planterIdentification.addToMessages(newMessage)

        coreDataManager.saveContext()
        return newMessage
    }
    
    func createSurveyResponse(planter: Planter, surveyId: String, surveyResponse: [String]) {

        guard let handle = planter.identifier,
              let planter = planter as? PlanterDetail,
              let planterIdentification = planter.latestIdentification as? PlanterIdentification else {
            return
        }

        guard let response = coreDataManager.perform(fetchRequest: surveyMessage(for: planterIdentification, surveyID: surveyId)),
              let message = response.first,
              let survey = message.survey else {
            return
        }

        message.isHidden = true

        let newMessage = MessageEntity(context: coreDataManager.viewContext)
        newMessage.messageId = UUID().uuidString.lowercased()
        newMessage.type = "survey_response"
        newMessage.from = handle
        newMessage.to = "admin"
        newMessage.subject = message.subject
        newMessage.body = message.body
        newMessage.composedAt = Date()
        newMessage.videoLink = message.videoLink

        newMessage.uploaded = false
        newMessage.unread = false
        newMessage.isHidden = true

        let newSurvey = SurveyEntity(context: coreDataManager.viewContext)
        newSurvey.uuid = surveyId
        newSurvey.title = survey.title
        newSurvey.response = true

        if let questions = survey.questions?.array as? [SurveyQuestion] {
            newSurvey.addToQuestions(NSOrderedSet(array: questions.map { returnedQuestion in
                let question = SurveyQuestion(context: coreDataManager.viewContext)
                question.prompt = returnedQuestion.prompt
                question.choices = returnedQuestion.choices
                return question
            }))
        }

        newMessage.survey = newSurvey
        newMessage.surveyResponse = surveyResponse

        planterIdentification.addToMessages(newMessage)
        coreDataManager.saveContext()
    }
}

// MARK: - Fetch Requests
extension MessagingService {

    func allSurveyMessages(for planterIdentification: PlanterIdentification) -> NSFetchRequest<MessageEntity> {
        let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "planterIdentification == %@", planterIdentification),
            NSPredicate(format: "survey != nil")
        ])
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

    func unreadMessages(for planterIdentification: PlanterIdentification) -> NSFetchRequest<MessageEntity> {
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

    func surveyMessage(for planterIdentification: PlanterIdentification, surveyID: String) -> NSFetchRequest<MessageEntity> {
        let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "planterIdentification == %@", planterIdentification),
            NSPredicate(format: "survey.uuid == %@", surveyID),
            NSPredicate(format: "survey.response == false")
        ])
        fetchRequest.fetchLimit = 1
        return fetchRequest
    }
}
