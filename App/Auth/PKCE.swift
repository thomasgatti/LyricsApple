import CryptoKit
import Foundation
import Security

/// Proof Key for Code Exchange (RFC 7636): permette l'OAuth senza client secret nell'app.
enum PKCE {
    /// Stringa casuale URL-safe. 64 byte -> 86 caratteri (il limite RFC è 43...128).
    static func makeVerifier(byteCount: Int = 64) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        if status != errSecSuccess {
            var generator = SystemRandomNumberGenerator()
            bytes = (0..<byteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        }
        return base64URLEncode(Data(bytes))
    }

    /// code_challenge = BASE64URL(SHA256(verifier))
    static func challenge(for verifier: String) -> String {
        base64URLEncode(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Codifica application/x-www-form-urlencoded (RFC 3986 unreserved).
enum FormEncoder {
    private static let allowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    static func encode(_ parameters: [String: String]) -> String {
        parameters
            .sorted { $0.key < $1.key }
            .map { key, value in "\(escape(key))=\(escape(value))" }
            .joined(separator: "&")
    }

    static func escape(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
}
