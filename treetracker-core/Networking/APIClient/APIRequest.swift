import Foundation

protocol APIRequest {
    var method: HTTPMethod { get }
    var endpoint: Endpoint { get }
    associatedtype ResponseType: Decodable
    associatedtype Parameters: Encodable
    var parameters: Parameters? { get }
}

extension APIRequest {

    func urlRequest(rootURL: URL, headers: [String: String]) -> URLRequest {

        let url = URL(string: endpoint.getPath(), relativeTo: rootURL) ?? rootURL

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.rawValue

        switch method {
        case .GET: encodeGet(request: &urlRequest)
        case .POST: encodePost(request: &urlRequest)
        }

        for header in headers {
            urlRequest.setValue(header.value, forHTTPHeaderField: header.key)
        }

        return urlRequest
    }

    private func encodeGet(request: inout URLRequest) {
        guard let parameters else { return }
        
        let encodedURL: URL? = {

            var urlComponents = URLComponents(url: request.url!, resolvingAgainstBaseURL: true)
            urlComponents?.queryItems = Mirror(reflecting: parameters)
                .children
                .map({ (label, value) in
                    // Map any dates to ISO8601 format
                    guard let date = value as? Date else {
                        return (label, value)
                    }
                    let dateFormatter = ISO8601DateFormatter()
                    dateFormatter.formatOptions = [
                        .withInternetDateTime,
                        .withFractionalSeconds
                    ]
                     let formattedDate = dateFormatter.string(from: date)
                    return (label, formattedDate)
                })
                .compactMap({ (label, value) in
                    // If we need to pass boolean value here we can decide with the API team how best to represent
                    // This should do for 'most' cases though
                    guard let label else {
                        return nil
                    }
                    return URLQueryItem(name: label, value: "\(value)")
                })

            return urlComponents?.url
        }()

        if let encodedURL {
            request.url = encodedURL
        }
    }

    private func encodePost(request: inout URLRequest) {
        guard let parameters else { return }
        
        let jsonEncoder = JSONEncoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        jsonEncoder.dateEncodingStrategy = .custom({ date, encoder in
            var container = encoder.singleValueContainer()
            let dateString = formatter.string(from: date)
            try container.encode(dateString)
        })
        request.httpBody = try? jsonEncoder.encode(parameters)
    }

}
