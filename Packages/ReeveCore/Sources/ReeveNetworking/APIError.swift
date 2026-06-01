import Foundation

public enum APIError: Error, Sendable, Equatable, LocalizedError {
    case invalidURL
    case transport(String)
    case badStatus(Int, body: String?)
    case decoding(String)
    case untrustedCertificate(host: String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The server URL is invalid."
        case .transport(let m):
            "Network error: \(m)"
        case .badStatus(let code, let body):
            "Server returned HTTP \(code)\(body.map { ": \($0)" } ?? "")."
        case .decoding(let m):
            "Could not parse the server response: \(m)"
        case .untrustedCertificate(let host):
            "The TLS certificate for \(host) is not trusted."
        }
    }
}
