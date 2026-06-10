import XCTest
@testable import UsageCore

final class UsageClientTests: XCTestCase {
    private static let sampleJson =
        "{\"five_hour\":{\"utilization\":52.0,\"resets_at\":\"2026-06-10T16:40:00.627509+00:00\"},"
        + "\"seven_day\":{\"utilization\":27.0,\"resets_at\":\"2026-06-13T11:00:00.627529+00:00\"},"
        + "\"seven_day_oauth_apps\":null,\"seven_day_opus\":null,"
        + "\"seven_day_sonnet\":{\"utilization\":0.0,\"resets_at\":null},"
        + "\"seven_day_cowork\":null,\"seven_day_omelette\":null,\"tangelo\":null,"
        + "\"iguana_necktie\":null,\"omelette_promotional\":null,\"cinder_cove\":null,"
        + "\"extra_usage\":{\"is_enabled\":false,\"monthly_limit\":null,\"used_credits\":null,"
        + "\"utilization\":null,\"currency\":null,\"disabled_reason\":null}}"

    /// Closure transport that records the request and returns a canned status/body.
    private func makeClient(
        status: Int,
        body: String,
        captured: CapturedBox = CapturedBox()
    ) -> (UsageClient, CapturedBox) {
        let client = UsageClient(transport: ClosureTransport { request in
            captured.request = request
            return (Data(body.utf8), status)
        })
        return (client, captured)
    }

    func testFetchParsesSampleJson() async throws {
        let (client, _) = makeClient(status: 200, body: Self.sampleJson)
        let snapshot = try await client.fetch(accessToken: "tok")

        XCTAssertNotNil(snapshot.fiveHour)
        XCTAssertEqual(snapshot.fiveHour!.utilization, 52.0)

        let expected = ISO8601DateParsing.parse("2026-06-10T16:40:00.627509+00:00")
        XCTAssertNotNil(expected)
        XCTAssertEqual(snapshot.fiveHour!.resetsAt!.timeIntervalSince1970,
                       expected!.timeIntervalSince1970, accuracy: 0.001)

        XCTAssertNotNil(snapshot.sevenDay)
        XCTAssertEqual(snapshot.sevenDay!.utilization, 27.0)

        XCTAssertNil(snapshot.sevenDayOpus)

        XCTAssertNotNil(snapshot.sevenDaySonnet)
        XCTAssertEqual(snapshot.sevenDaySonnet!.utilization, 0.0)
        XCTAssertNil(snapshot.sevenDaySonnet!.resetsAt)
    }

    func testFetchSendsRequiredHeaders() async throws {
        let (client, captured) = makeClient(status: 200, body: Self.sampleJson)
        _ = try await client.fetch(accessToken: "tok")

        let req = try XCTUnwrap(captured.request)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
        XCTAssertEqual(req.value(forHTTPHeaderField: "User-Agent"), "claude-code/2.1.170")
        XCTAssertTrue(req.value(forHTTPHeaderField: "User-Agent")!.contains("claude-code"))
        XCTAssertEqual(req.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testFetch401ThrowsAuthError() async {
        let (client, _) = makeClient(status: 401, body: "{}")
        await assertThrows(client, expecting: .auth(401))
    }

    func testFetch403ThrowsAuthError() async {
        let (client, _) = makeClient(status: 403, body: "{}")
        await assertThrows(client, expecting: .auth(403))
    }

    func testFetch429ThrowsRateLimitError() async {
        let (client, _) = makeClient(status: 429, body: "{}")
        await assertThrows(client, expecting: .rateLimited)
    }

    func testFetch500ThrowsGenericError() async {
        let (client, _) = makeClient(status: 500, body: "{}")
        do {
            _ = try await client.fetch(accessToken: "tok")
            XCTFail("expected error")
        } catch UsageError.generic {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testFetchNullWindowProducesAllNullSnapshot() async throws {
        let (client, _) = makeClient(status: 200, body: "{\"five_hour\":null}")
        let snapshot = try await client.fetch(accessToken: "tok")

        XCTAssertNil(snapshot.fiveHour)
        XCTAssertNil(snapshot.sevenDay)
        XCTAssertNil(snapshot.sevenDayOpus)
        XCTAssertNil(snapshot.sevenDaySonnet)
    }

    func testFetchParsesPlainIso8601WithoutFractionalSeconds() async throws {
        let (client, _) = makeClient(
            status: 200,
            body: "{\"five_hour\":{\"utilization\":10.0,\"resets_at\":\"2026-06-10T16:40:00Z\"}}")
        let snapshot = try await client.fetch(accessToken: "tok")
        XCTAssertNotNil(snapshot.fiveHour!.resetsAt)
    }

    // MARK: - helpers

    private func assertThrows(
        _ client: UsageClient,
        expecting expected: UsageError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await client.fetch(accessToken: "tok")
            XCTFail("expected error", file: file, line: line)
        } catch let error as UsageError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("unexpected error: \(error)", file: file, line: line)
        }
    }
}

/// Reference box so the @Sendable closure can write back the captured request.
final class CapturedBox: @unchecked Sendable {
    var request: URLRequest?
}
