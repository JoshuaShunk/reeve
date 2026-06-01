import CryptoKit
import Foundation
import ReeveModels

#if canImport(Security)
import Security
#endif

/// A `URLSession` delegate that applies a per-host `TLSPolicy`, so a single
/// session can talk to multiple Proxmox servers each with their own trust rule
/// (system / allow-insecure / pinned SHA-256). Thread-safe; the session may
/// invoke the auth challenge on a background queue.
public final class ProxmoxTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var policies: [String: TLSPolicy] = [:]

    public func setPolicy(_ policy: TLSPolicy, forHost host: String) {
        lock.lock(); defer { lock.unlock() }
        policies[host] = policy
    }

    private func policy(forHost host: String) -> TLSPolicy {
        lock.lock(); defer { lock.unlock() }
        return policies[host] ?? .system
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        switch policy(forHost: challenge.protectionSpace.host) {
        case .system:
            completionHandler(.performDefaultHandling, nil)
        case .allowInsecure:
            completionHandler(.useCredential, URLCredential(trust: trust))
        case .pinnedSHA256(let expected):
            if let fingerprint = Self.leafFingerprint(trust),
               fingerprint.caseInsensitiveCompare(expected) == .orderedSame {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }
    }

    /// Lowercase hex SHA-256 of the leaf certificate's DER bytes, the value to
    /// show the user during trust-on-first-use and store for pinning.
    public static func leafFingerprint(_ trust: SecTrust) -> String? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first
        else { return nil }
        let der = SecCertificateCopyData(leaf) as Data
        return SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
    }
}
