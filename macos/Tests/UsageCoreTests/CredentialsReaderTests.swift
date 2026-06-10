import XCTest
@testable import UsageCore

final class CredentialsReaderTests: XCTestCase {
    // Hermetic env lookup so host machine variables can't affect tests.
    private func noEnv(_ name: String) -> String? { nil }

    private func writeTemp(_ content: String) -> String {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("cuw-test-\(UUID().uuidString).json")
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    func testTryReadValidFileParsesTokenAndExpiry() {
        let path = writeTemp(
            "{\"claudeAiOauth\":{\"accessToken\":\"sk-ant-oat01-abc\","
            + "\"refreshToken\":\"r\",\"expiresAt\":1781120644269,"
            + "\"scopes\":[\"a\"],\"subscriptionType\":\"max\"}}")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let reader = CredentialsReader(path: path, getEnvironmentVariable: noEnv, keychain: NullKeychainReader())
        let creds = reader.tryRead()

        XCTAssertNotNil(creds)
        XCTAssertEqual(creds!.accessToken, "sk-ant-oat01-abc")
        XCTAssertEqual(creds!.expiresAt, Date(timeIntervalSince1970: 1781120644269.0 / 1000.0))
    }

    func testTryReadMissingFileReturnsNull() {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("cuw-missing-\(UUID().uuidString).json")
        let reader = CredentialsReader(path: path, getEnvironmentVariable: noEnv, keychain: NullKeychainReader())
        XCTAssertNil(reader.tryRead())
    }

    func testTryReadMalformedJsonReturnsNull() {
        let path = writeTemp("{ not valid json ")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let reader = CredentialsReader(path: path, getEnvironmentVariable: noEnv, keychain: NullKeychainReader())
        XCTAssertNil(reader.tryRead())
    }

    func testTryReadMissingAccessTokenReturnsNull() {
        let path = writeTemp("{\"claudeAiOauth\":{\"refreshToken\":\"r\",\"expiresAt\":123}}")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let reader = CredentialsReader(path: path, getEnvironmentVariable: noEnv, keychain: NullKeychainReader())
        XCTAssertNil(reader.tryRead())
    }

    func testTryReadEnvTokenWinsOverFile() {
        let path = writeTemp("{\"claudeAiOauth\":{\"accessToken\":\"file-token\",\"expiresAt\":123}}")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let reader = CredentialsReader(
            path: path,
            getEnvironmentVariable: { $0 == "CLAUDE_CODE_OAUTH_TOKEN" ? " env-token " : nil },
            keychain: NullKeychainReader())
        let creds = reader.tryRead()

        XCTAssertNotNil(creds)
        XCTAssertEqual(creds!.accessToken, "env-token") // trimmed
        XCTAssertEqual(creds!.expiresAt, Date.distantFuture)
    }

    func testTryReadEnvTokenWorksWithoutAnyFile() {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("cuw-missing-\(UUID().uuidString).json")
        let reader = CredentialsReader(
            path: path,
            getEnvironmentVariable: { $0 == "CLAUDE_CODE_OAUTH_TOKEN" ? "env-token" : nil },
            keychain: NullKeychainReader())

        let creds = reader.tryRead()
        XCTAssertNotNil(creds)
        XCTAssertEqual(creds!.accessToken, "env-token")
    }

    func testTryReadWhitespaceEnvTokenFallsBackToFile() {
        let path = writeTemp("{\"claudeAiOauth\":{\"accessToken\":\"file-token\",\"expiresAt\":123}}")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let reader = CredentialsReader(
            path: path,
            getEnvironmentVariable: { $0 == "CLAUDE_CODE_OAUTH_TOKEN" ? "   " : nil },
            keychain: NullKeychainReader())
        let creds = reader.tryRead()

        XCTAssertNotNil(creds)
        XCTAssertEqual(creds!.accessToken, "file-token")
    }

    func testTryReadClaudeConfigDirResolvesCredentialsFile() {
        let dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("cuw-cfg-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = (dir as NSString).appendingPathComponent(".credentials.json")
        try? "{\"claudeAiOauth\":{\"accessToken\":\"cfg-token\",\"expiresAt\":1781120644269}}"
            .write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let reader = CredentialsReader(
            path: nil,
            getEnvironmentVariable: { $0 == "CLAUDE_CONFIG_DIR" ? dir : nil },
            keychain: NullKeychainReader())
        let creds = reader.tryRead()

        XCTAssertNotNil(creds)
        XCTAssertEqual(creds!.accessToken, "cfg-token")
    }

    func testTryReadExplicitPathWinsOverClaudeConfigDir() {
        let explicitPath = writeTemp(
            "{\"claudeAiOauth\":{\"accessToken\":\"explicit-token\",\"expiresAt\":123}}")
        defer { try? FileManager.default.removeItem(atPath: explicitPath) }

        let reader = CredentialsReader(
            path: explicitPath,
            getEnvironmentVariable: { $0 == "CLAUDE_CONFIG_DIR" ? "/nonexistent-dir" : nil },
            keychain: NullKeychainReader())
        let creds = reader.tryRead()

        XCTAssertNotNil(creds)
        XCTAssertEqual(creds!.accessToken, "explicit-token")
    }

    // MARK: - Keychain fallback (injected layer, shares the file JSON shape)

    func testTryReadKeychainFallbackWhenNoFile() {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("cuw-missing-\(UUID().uuidString).json")
        let keychain = StubKeychain(
            secret: "{\"claudeAiOauth\":{\"accessToken\":\"kc-token\",\"expiresAt\":1781120644269}}")

        let reader = CredentialsReader(path: path, getEnvironmentVariable: noEnv, keychain: keychain)
        let creds = reader.tryRead()

        XCTAssertNotNil(creds)
        XCTAssertEqual(creds!.accessToken, "kc-token")
        XCTAssertEqual(keychain.requestedService, CredentialsReader.keychainService)
    }

    func testTryReadFileWinsOverKeychain() {
        let path = writeTemp("{\"claudeAiOauth\":{\"accessToken\":\"file-token\",\"expiresAt\":123}}")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let keychain = StubKeychain(
            secret: "{\"claudeAiOauth\":{\"accessToken\":\"kc-token\",\"expiresAt\":456}}")

        let reader = CredentialsReader(path: path, getEnvironmentVariable: noEnv, keychain: keychain)
        let creds = reader.tryRead()

        XCTAssertNotNil(creds)
        XCTAssertEqual(creds!.accessToken, "file-token")
    }

    func testTryReadMalformedKeychainSecretReturnsNull() {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("cuw-missing-\(UUID().uuidString).json")
        let keychain = StubKeychain(secret: "{ not json")

        let reader = CredentialsReader(path: path, getEnvironmentVariable: noEnv, keychain: keychain)
        XCTAssertNil(reader.tryRead())
    }

    func testTryReadKeychainMissingExpiresAtUsesDistantPast() {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("cuw-missing-\(UUID().uuidString).json")
        let keychain = StubKeychain(secret: "{\"claudeAiOauth\":{\"accessToken\":\"kc-token\"}}")

        let reader = CredentialsReader(path: path, getEnvironmentVariable: noEnv, keychain: keychain)
        let creds = reader.tryRead()

        XCTAssertNotNil(creds)
        XCTAssertEqual(creds!.expiresAt, Date.distantPast)
    }
}

private final class StubKeychain: KeychainReader, @unchecked Sendable {
    let secret: String?
    var requestedService: String?

    init(secret: String?) { self.secret = secret }

    func readSecret(service: String) -> String? {
        requestedService = service
        return secret
    }
}
