//
//  PostMessagesRequest.swift
//  Treetracker-Core
//
//  Created by Frédéric Helfer on 03/05/23.
//

import Foundation

struct PostMessagesRequest: APIRequest {

    struct Parameters: Encodable {
        let id: String?
        let authorHandle: String?
        let recipientHandle: String?
        let type: String?
        let body: String?
        let composedAt: Date?
        let surveyResponse: [String]?
        let surveyId: String?
        
        private enum CodingKeys: String, CodingKey {
            case id
            case authorHandle = "author_handle"
            case recipientHandle = "recipient_handle"
            case type
            case body
            case composedAt = "composed_at"
            case surveyResponse = "survey_response"
            case surveyId = "survey_id"
        }
    }

    let endpoint: Endpoint = .messages
    let method: HTTPMethod = .POST
    typealias ResponseType = PostMessagesResponse

    let parameters: Parameters?

    init(message: MessageEntity) {
        self.parameters = Parameters(
            id: message.messageId,
            authorHandle: message.planterIdentification?.planterDetail?.firstName, // TODO: Change to identifier!!!!
            recipientHandle: message.to,
            type: message.type,
            body: message.body,
            composedAt: message.composedAt,
            surveyResponse: message.surveyResponse,
            surveyId: message.survey?.uuid
        )
    }
}
