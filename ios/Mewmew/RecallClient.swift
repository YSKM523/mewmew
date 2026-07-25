import Foundation

struct RecallResult: Equatable {
    let answer: String
    let citedIDs: [String]
}

protocol RecallServing: Sendable {
    func recall(question: String, memories: [Memory]) async -> RecallResult?
}

actor RecallClient: RecallServing {
    static let shared = RecallClient()

    static let defaultEndpoint = URL(
        string: "https://mewmew-api.pp-account.workers.dev/v1/recall"
    )!

    private let token: String?
    private let endpoint: URL
    private let session: URLSession

    init(
        token: String? = ParseClient.resolvedToken(),
        endpoint: URL = RecallClient.defaultEndpoint,
        session: URLSession? = nil
    ) {
        self.token = token
        self.endpoint = endpoint

        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 10
            configuration.timeoutIntervalForResource = 10
            self.session = URLSession(configuration: configuration)
        }
    }

    func recall(question: String, memories: [Memory]) async -> RecallResult? {
        guard let token else { return nil }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "X-Mewmew-Token")

        do {
            request.httpBody = try JSONEncoder().encode(
                RecallRequest(
                    question: question,
                    memories: memories.map(RecallMemory.init)
                )
            )
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse,
                response.statusCode == 200
            else {
                return nil
            }
            let decoded = try JSONDecoder().decode(RecallResponse.self, from: data)
            return RecallResult(
                answer: decoded.answer,
                citedIDs: decoded.citedIDs
            )
        } catch {
            return nil
        }
    }
}

private struct RecallRequest: Encodable {
    let question: String
    let memories: [RecallMemory]
}

private struct RecallMemory: Encodable {
    let id: String
    let kind: String
    let title: String
    let rawText: String
    let createdAt: Int64

    init(_ memory: Memory) {
        id = memory.id
        kind = memory.kind.apiValue
        title = memory.title
        rawText = memory.rawText
        createdAt = memory.createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case rawText = "raw_text"
        case createdAt = "created_at"
    }
}

private struct RecallResponse: Decodable {
    let answer: String
    let citedIDs: [String]

    enum CodingKeys: String, CodingKey {
        case answer
        case citedIDs = "cited_ids"
    }
}

private extension MemoryKind {
    var apiValue: String {
        switch self {
        case .reminder:
            "reminder"
        case .card:
            "card"
        case .note:
            "note"
        }
    }
}
