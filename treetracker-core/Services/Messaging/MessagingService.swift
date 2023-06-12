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
        newMessage.isHidden = false

        latestPlanterIdentification.addToMessages(newMessage)

        coreDataManager.saveContext()
        return newMessage
    }
    
    func createSurveyResponse(planter: Planter, surveyId: String, surveyResponse: [String]) {

        // TODO: change to planter.identifier
        guard
            let handle = planter.firstName,
            let planter = planter as? PlanterDetail,
            let planterIdentification = planter.latestIdentification as? PlanterIdentification
        else {
            print(MessagingServiceError.missingPlanterIdentifier)
            return
        }

        var surveyMessage: NSFetchRequest<MessageEntity> {
            let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "planterIdentification == %@", planterIdentification),
                NSPredicate(format: "survey.uuid == %@", surveyId),
                NSPredicate(format: "survey.response == false")
            ])
            fetchRequest.fetchLimit = 1
            return fetchRequest
        }

        guard let response = coreDataManager.perform(fetchRequest: surveyMessage),
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

    func allMessages(for planterIdentification: PlanterIdentification) -> NSFetchRequest<MessageEntity> {
        let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "planterIdentification == %@", planterIdentification),
            NSPredicate(format: "isHidden == false")
        ])
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "composedAt", ascending: true)]
        return fetchRequest
    }

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
