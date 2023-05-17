import Foundation

protocol APIServiceProtocol {
    func performAPIRequest<Request: APIRequest>(request: Request, completion: @escaping (Result<Request.ResponseType?, Error>) -> Void)
}

class APIService: APIServiceProtocol {

    private let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    private var headers: [String: String] {
        return [
            "Content-Type": "application/json"
        ]
    }

    func performAPIRequest<Request: APIRequest>(request: Request, completion: @escaping (Result<Request.ResponseType?, Error>) -> Void) {

        let urlRequest = request.urlRequest(rootURL: rootURL, headers: headers)

        let task = URLSession.shared.dataTask(with: urlRequest) { (data, response, error) in

            DispatchQueue.main.async {

                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let response = response as? HTTPURLResponse,
                    200...299 ~= response.statusCode else {
                    completion(.failure(APIServiceError.badHTTPURLResponse))
                    return
                }

                guard let data, !data.isEmpty else {
                    completion(.success(nil))
                    return
                }

                do {
                    let jsonDecoder = JSONDecoder()
                    let dateFormatter = ISO8601DateFormatter()
                    dateFormatter.formatOptions = [
                        .withInternetDateTime,
                        .withFractionalSeconds
                    ]
                    
                    jsonDecoder.dateDecodingStrategy = .custom({ decoder in
                        let container = try decoder.singleValueContainer()
                        let dateString = try container.decode(String.self)
                        
                        if let date = dateFormatter.date(from: dateString) {
                            return date
                        }
                        
                        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string \(dateString)")
                    })
                    
                    let decodedObject = try jsonDecoder.decode(Request.ResponseType.self, from: data)
                    completion(.success(decodedObject))
                } catch {
                    completion(.failure(error))
                }
            }
        }

        task.resume()
    }
}

// MARK: - Errors
enum APIServiceError: Swift.Error {
    case missingRootURL
    case badHTTPURLResponse
}
