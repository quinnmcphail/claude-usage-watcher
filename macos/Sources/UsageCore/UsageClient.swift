import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum UsageError: Error, Equatable {
    case auth(Int)
    case rateLimited
    case generic(String)
}

/// Abstracts the HTTP round-trip so tests can supply a canned response without
/// touching the network. Returns the body plus the HTTP status code.
public protocol UsageTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

/// Default transport backed by URLSession.
public struct URLSessionTransport: UsageTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, status)
    }
}

/// Closure-backed transport, convenient for tests.
public struct ClosureTransport: UsageTransport {
    private let handler: @Sendable (URLRequest) async throws -> (Data, Int)

    public init(_ handler: @escaping @Sendable (URLRequest) async throws -> (Data, Int)) {
        self.handler = handler
    }

    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try await handler(request)
    }
}

public final class UsageClient {
    public static let endpoint = "https://api.anthropic.com/api/oauth/usage"
    public static let userAgent = "claude-code/2.1.170"
    public static let anthropicBeta = "oauth-2025-04-20"

    private let transport: UsageTransport

    public init(transport: UsageTransport) {
        self.transport = transport
    }

    public func fetch(accessToken: String) async throws -> UsageSnapshot {
        guard let url = URL(string: Self.endpoint) else {
            throw UsageError.generic("Invalid endpoint URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.anthropicBeta, forHTTPHeaderField: "anthropic-beta")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, status) = try await transport.send(request)

        if status == 401 || status == 403 {
            throw UsageError.auth(status)
        }

        if status == 429 {
            throw UsageError.rateLimited
        }

        if status < 200 || status >= 300 {
            throw UsageError.generic("Request failed (\(status)).")
        }

        do {
            let dto = try JSONDecoder().decode(UsageDto.self, from: data)
            return Self.map(dto)
        } catch {
            throw UsageError.generic("Failed to parse usage response.")
        }
    }

    private static func map(_ dto: UsageDto) -> UsageSnapshot {
        UsageSnapshot(
            fiveHour: mapWindow(dto.fiveHour),
            sevenDay: mapWindow(dto.sevenDay),
            sevenDayOpus: mapWindow(dto.sevenDayOpus),
            sevenDaySonnet: mapWindow(dto.sevenDaySonnet),
            fetchedAt: Date()
        )
    }

    private static func mapWindow(_ dto: WindowDto?) -> UsageWindow? {
        guard let dto else { return nil }
        return UsageWindow(utilization: dto.utilization, resetsAt: dto.resetsAt)
    }
}

// MARK: - Wire DTOs

private struct UsageDto: Decodable {
    let fiveHour: WindowDto?
    let sevenDay: WindowDto?
    let sevenDayOpus: WindowDto?
    let sevenDaySonnet: WindowDto?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // decodeIfPresent treats an explicit JSON null the same as a missing key,
        // so windows reported as null map to nil, like the C# nullable DTO.
        fiveHour = try c.decodeIfPresent(WindowDto.self, forKey: .fiveHour)
        sevenDay = try c.decodeIfPresent(WindowDto.self, forKey: .sevenDay)
        sevenDayOpus = try c.decodeIfPresent(WindowDto.self, forKey: .sevenDayOpus)
        sevenDaySonnet = try c.decodeIfPresent(WindowDto.self, forKey: .sevenDaySonnet)
    }
}

private struct WindowDto: Decodable {
    let utilization: Double
    let resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        utilization = try c.decode(Double.self, forKey: .utilization)
        if let raw = try c.decodeIfPresent(String.self, forKey: .resetsAt) {
            resetsAt = ISO8601DateParsing.parse(raw)
        } else {
            resetsAt = nil
        }
    }
}

/// ISO-8601 parsing that tolerates both fractional-second and plain forms.
enum ISO8601DateParsing {
    static func parse(_ s: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: s) {
            return d
        }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }
}
