import Foundation

protocol ParseServing: Sendable {
    func parse(
        text: String,
        timeZone: TimeZone,
        now: Date
    ) async -> ParseResult?
}

struct ParseResult: Decodable {
    let kind: ParseKind
    let title: String
    let dueAt: Int64?
    let question: String?
    let answer: String?
    let confidence: Double

    enum CodingKeys: String, CodingKey {
        case kind
        case title
        case dueAt = "due_at"
        case question
        case answer
        case confidence
    }
}

enum ParseKind: String, Decodable {
    case reminder
    case card
    case note

    var memoryKind: MemoryKind {
        switch self {
        case .reminder:
            return .reminder
        case .card:
            return .card
        case .note:
            return .note
        }
    }
}

actor ParseClient: ParseServing {
    static let shared = ParseClient()

    private static let endpoint = URL(
        string: "https://mewmew-api.pp-account.workers.dev/v1/parse"
    )!

    private let token: String?
    private let session: URLSession

    /// The build-injected token, or nil when the build shipped without one.
    /// Static so callers outside the actor can check configuration without
    /// awaiting; it only reads the bundle.
    static func resolvedToken() -> String? {
        let configured = BuildConfig.appToken
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return configured.isEmpty ? nil : configured
    }

    static var isConfigured: Bool { resolvedToken() != nil }

    init() {
        token = Self.resolvedToken()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        session = URLSession(configuration: configuration)
    }

    func parse(
        text: String,
        timeZone: TimeZone = .current,
        now: Date = Date()
    ) async -> ParseResult? {
        guard let token else { return nil }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "X-Mewmew-Token")

        do {
            request.httpBody = try JSONEncoder().encode(
                ParseRequest(
                    text: text,
                    tz: timeZone.identifier,
                    now: Self.localISO8601(now, timeZone: timeZone)
                )
            )
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200
            else {
                return nil
            }
            return try JSONDecoder().decode(ParseResult.self, from: data)
        } catch {
            return nil
        }
    }

    private static func localISO8601(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.string(from: date)
    }
}

private struct ParseRequest: Encodable {
    let text: String
    let tz: String
    let now: String
}
