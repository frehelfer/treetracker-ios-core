//
//  GetNextMessagesRequest.swift
//  Treetracker-Core
//
//  Created by Frédéric Helfer on 31/05/23.
//

import Foundation

struct GetNextMessagesRequest: APIRequest {

    let endpoint: Endpoint
    let method: HTTPMethod = .GET
    typealias ResponseType = GetMessagesResponse

    var parameters: String? = nil

    init(path: String) {
        self.endpoint = .nextMessages(path: path)
    }
}
