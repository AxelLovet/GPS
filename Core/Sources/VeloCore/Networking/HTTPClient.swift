import Foundation

#if canImport(FoundationNetworking)
// Sous Linux, URLSession vit dans un module distinct. Cet import permet de
// compiler et de tester VeloCore hors macOS.
import FoundationNetworking
#endif

/// Une requête HTTP, décrite indépendamment d'`URLSession`.
public struct HTTPRequest: Sendable, Hashable {
    public enum Method: String, Sendable { case get = "GET", post = "POST" }

    public var url: URL
    public var method: Method
    public var headers: [String: String]
    public var body: Data?
    public var timeout: TimeInterval

    public init(
        url: URL,
        method: Method = .get,
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval = 30
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }
}

/// Réponse HTTP brute.
public struct HTTPResponse: Sendable, Hashable {
    public let statusCode: Int
    public let data: Data

    public init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        self.data = data
    }
}

/// Abstraction du transport réseau.
///
/// Elle existe pour une raison précise : les tests du client de routage doivent
/// pouvoir rejouer des réponses figées, sans réseau et **sans clé API réelle**
/// (cahier des charges §17).
public protocol HTTPClient: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// Implémentation `URLSession` utilisée en production.
public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = request.timeout
        for (field, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }

        do {
            let (data, response) = try await session.veloData(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw VeloError.invalidRoutingResponse(reason: "réponse non HTTP")
            }
            return HTTPResponse(statusCode: httpResponse.statusCode, data: data)
        } catch let error as VeloError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                throw VeloError.noInternetConnection
            case .timedOut:
                throw VeloError.requestTimedOut
            default:
                throw VeloError.routingEngineUnavailable(statusCode: nil)
            }
        } catch {
            throw VeloError.routingEngineUnavailable(statusCode: nil)
        }
    }
}

extension URLSession {
    /// `data(for:)` disponible partout.
    ///
    /// La version `async` d'`URLSession` n'est pas exposée par
    /// swift-corelibs-foundation sur toutes les versions de Linux ; ce pont
    /// garantit que VeloCore compile aussi bien pour iOS que pour la plateforme
    /// d'intégration continue.
    func veloData(for request: URLRequest) async throws -> (Data, URLResponse) {
        #if canImport(FoundationNetworking)
        return try await withCheckedThrowingContinuation { continuation in
            let task = dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, let response {
                    continuation.resume(returning: (data, response))
                } else {
                    continuation.resume(
                        throwing: VeloError.invalidRoutingResponse(reason: "réponse vide")
                    )
                }
            }
            task.resume()
        }
        #else
        return try await data(for: request)
        #endif
    }
}
