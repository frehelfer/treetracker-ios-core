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
        let author_handle: String?
        let recipient_handle: String?
        let type: String?
        let body: String?
        let composed_at: Date?
        let survey_response: [String]?
        let survey_id: String?
    }

    let endpoint: Endpoint = .messages
    let method: HTTPMethod = .POST
    typealias ResponseType = PostMessagesResponse

    let parameters: Parameters?

    init(message: MessageEntity) {
        self.parameters = Parameters(
            id: message.messageId,
            author_handle: message.planterIdentification?.planterDetail?.firstName, // TODO: Change to identifier!!!!
            recipient_handle: message.to,
            type: message.type,
            body: message.body,
            composed_at: message.composedAt,
            survey_response: message.surveyResponse,
            survey_id: message.survey?.uuid
        )
    }
}
