import Foundation
import Security

/// The GitHub token, kept only in the Keychain. Never written to defaults, the session, or logs.
public enum GitHubKeychain {
    private static let service = (Bundle.main.bundleIdentifier ?? "com.joshoettinger.nano") + ".github"
    private static let account = "oauth-token"

    public static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public static func save(_ token: String) -> Bool {
        delete()
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(token.utf8),
        ]
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    public static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// GitHub's OAuth device flow: show a code, the user approves it on github.com, Nano polls
/// for the token. Needs only a client ID (no secret), so nothing sensitive ships in the app.
public struct GitHubDeviceFlow: Sendable {
    public struct Code: Decodable, Sendable, Equatable {
        public let deviceCode: String
        public let userCode: String
        public let verificationURI: URL
        public let expiresIn: Int
        public let interval: Int

        enum CodingKeys: String, CodingKey {
            case deviceCode = "device_code", userCode = "user_code", verificationURI = "verification_uri"
            case expiresIn = "expires_in", interval
        }
    }

    public enum Failure: Error, Equatable, Sendable {
        case denied, expired, misconfigured(String), network
    }

    public let clientID: String
    public static let scopes = "repo read:org"
    private let session: URLSession

    public init(clientID: String, session: URLSession = .shared) {
        self.clientID = clientID
        self.session = session
    }

    public func requestCode() async throws -> Code {
        let data = try await post("https://github.com/login/device/code", ["client_id": clientID, "scope": Self.scopes])
        if let error = try? JSONDecoder().decode(ErrorBody.self, from: data) {
            throw Failure.misconfigured(error.errorDescription ?? error.error)
        }
        return try JSONDecoder().decode(Code.self, from: data)
    }

    /// Polls until the user approves, denies, or the code expires. Cancellable.
    public func waitForToken(_ code: Code) async throws -> String {
        var interval = max(5, code.interval)
        let deadline = Date().addingTimeInterval(TimeInterval(code.expiresIn))
        while Date() < deadline {
            try await Task.sleep(for: .seconds(interval))
            let data = try await post("https://github.com/login/oauth/access_token", [
                "client_id": clientID, "device_code": code.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])
            if let token = try? JSONDecoder().decode(TokenBody.self, from: data) { return token.accessToken }
            let error = try JSONDecoder().decode(ErrorBody.self, from: data)
            switch error.error {
            case "authorization_pending": continue
            case "slow_down": interval += 5
            case "access_denied": throw Failure.denied
            case "expired_token": throw Failure.expired
            default: throw Failure.misconfigured(error.errorDescription ?? error.error)
            }
        }
        throw Failure.expired
    }

    private func post(_ url: String, _ form: [String: String]) async throws -> Data {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? value)"
        }.joined(separator: "&").data(using: .utf8)
        guard let (data, _) = try? await session.data(for: request) else { throw Failure.network }
        return data
    }

    private struct TokenBody: Decodable {
        let accessToken: String
        enum CodingKeys: String, CodingKey { case accessToken = "access_token" }
    }

    private struct ErrorBody: Decodable {
        let error: String
        let errorDescription: String?
        enum CodingKeys: String, CodingKey { case error, errorDescription = "error_description" }
    }
}
