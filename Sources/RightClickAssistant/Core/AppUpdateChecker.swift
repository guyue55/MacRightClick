import Foundation

public struct SemanticVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.first == "v" || trimmed.first == "V"
            ? String(trimmed.dropFirst())
            : trimmed
        let components = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let major = Int(components[0]),
              let minor = Int(components[1]),
              let patch = Int(components[2]) else { return nil }

        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

public enum UpdateAvailability: Equatable, Sendable {
    case upToDate
    case updateAvailable(version: String, releaseURL: URL)
}

public enum UpdateCheckFailure: Error, Equatable, Sendable {
    case network
    case httpStatus(Int)
    case invalidResponse
}

public struct AppUpdateChecker: Sendable {
    public typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, Int)

    public static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/guyue55/MacRightClick/releases/latest"
    )!

    private let dataLoader: DataLoader

    public init() {
        self.dataLoader = { request in
            try await Self.load(request)
        }
    }

    public init(dataLoader: @escaping DataLoader) {
        self.dataLoader = dataLoader
    }

    public func check(
        currentVersion: String
    ) async -> Result<UpdateAvailability, UpdateCheckFailure> {
        guard let current = SemanticVersion(currentVersion) else {
            return .failure(.invalidResponse)
        }

        var request = URLRequest(url: Self.latestReleaseURL)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("RightClickAssistant-UpdateChecker", forHTTPHeaderField: "User-Agent")

        let data: Data
        let statusCode: Int
        do {
            (data, statusCode) = try await dataLoader(request)
        } catch {
            return .failure(.network)
        }

        guard (200..<300).contains(statusCode) else {
            return .failure(.httpStatus(statusCode))
        }
        guard let release = try? JSONDecoder().decode(LatestRelease.self, from: data),
              let latest = SemanticVersion(release.tagName),
              let releaseURL = URL(string: release.htmlURL),
              let scheme = releaseURL.scheme,
              ["https", "http"].contains(scheme.lowercased()) else {
            return .failure(.invalidResponse)
        }

        if current < latest {
            return .success(.updateAvailable(
                version: latest.description,
                releaseURL: releaseURL
            ))
        }
        return .success(.upToDate)
    }

    private static func load(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw UpdateCheckFailure.invalidResponse
        }
        return (data, response.statusCode)
    }

    private struct LatestRelease: Decodable {
        let tagName: String
        let htmlURL: String

        private enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }
}
