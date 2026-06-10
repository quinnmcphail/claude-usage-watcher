import Foundation

#if canImport(Security)
import Security
#endif

/// Reads the JSON secret stored by Claude Code in the macOS Keychain for a given
/// service name. Returns nil on any failure. Injectable so tests never touch the
/// real keychain.
public protocol KeychainReader: Sendable {
    func readSecret(service: String) -> String?
}

#if canImport(Security)
/// Default keychain reader: a generic-password lookup via SecItemCopyMatching.
/// On macOS, Claude Code stores its credentials JSON under the service
/// "Claude Code-credentials", which is why that's the default service name.
public struct SystemKeychainReader: KeychainReader {
    public init() {}

    public func readSecret(service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
#endif

/// A keychain reader that always returns nil, for platforms/tests without Security.
public struct NullKeychainReader: KeychainReader {
    public init() {}
    public func readSecret(service: String) -> String? { nil }
}

public final class CredentialsReader {
    public static let keychainService = "Claude Code-credentials"

    private let path: String
    private let getEnv: (String) -> String?
    private let keychain: KeychainReader

    /// - Parameters:
    ///   - path: Explicit credentials file path; overrides CLAUDE_CONFIG_DIR resolution.
    ///   - getEnvironmentVariable: Environment lookup, injectable for tests.
    ///   - keychain: Keychain layer, injectable for tests.
    public init(
        path: String? = nil,
        getEnvironmentVariable: ((String) -> String?)? = nil,
        keychain: KeychainReader? = nil
    ) {
        let env = getEnvironmentVariable ?? { ProcessInfo.processInfo.environment[$0] }
        self.getEnv = env
        self.path = path ?? Self.defaultPath(env)
        if let keychain {
            self.keychain = keychain
        } else {
            #if canImport(Security)
            self.keychain = SystemKeychainReader()
            #else
            self.keychain = NullKeychainReader()
            #endif
        }
    }

    private static func defaultPath(_ getEnv: (String) -> String?) -> String {
        // Claude Code honors CLAUDE_CONFIG_DIR as the home of its .credentials.json;
        // fall back to the standard ~/.claude location.
        let configDir = getEnv("CLAUDE_CONFIG_DIR")
        let dir: String
        if let configDir, !configDir.trimmingCharacters(in: .whitespaces).isEmpty {
            dir = configDir
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            dir = (home as NSString).appendingPathComponent(".claude")
        }
        return (dir as NSString).appendingPathComponent(".credentials.json")
    }

    public func tryRead() -> ClaudeCredentials? {
        // 1. An explicit token in the environment wins over any file (CI / non-standard
        // setups). No expiry is knowable for it; the 401 path handles a dead token.
        if let envToken = getEnv("CLAUDE_CODE_OAUTH_TOKEN"),
           !envToken.trimmingCharacters(in: .whitespaces).isEmpty {
            return ClaudeCredentials(
                accessToken: envToken.trimmingCharacters(in: .whitespaces),
                expiresAt: Date.distantFuture
            )
        }

        // 2. The credentials file.
        if let fileJson = try? String(contentsOfFile: path, encoding: .utf8),
           let creds = Self.parse(json: fileJson) {
            return creds
        }

        // 3. macOS Keychain fallback: Claude Code stores the same JSON shape there
        // by default on macOS, so a missing file isn't the end of the line.
        if let secret = keychain.readSecret(service: Self.keychainService),
           let creds = Self.parse(json: secret) {
            return creds
        }

        return nil
    }

    /// Parses the `{ "claudeAiOauth": { accessToken, expiresAt } }` shape shared by
    /// the file and the keychain secret. Returns nil on any structural problem.
    static func parse(json: String) -> ClaudeCredentials? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty else {
            return nil
        }

        // Missing/invalid expiresAt mirrors DateTimeOffset.MinValue from the C#.
        var expiresAt = Date.distantPast
        if let ms = oauth["expiresAt"] as? Double {
            expiresAt = Date(timeIntervalSince1970: ms / 1000.0)
        } else if let ms = oauth["expiresAt"] as? Int {
            expiresAt = Date(timeIntervalSince1970: Double(ms) / 1000.0)
        }

        return ClaudeCredentials(accessToken: token, expiresAt: expiresAt)
    }
}
