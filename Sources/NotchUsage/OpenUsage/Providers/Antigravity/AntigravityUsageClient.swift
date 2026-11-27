// SPDX-License-Identifier: MIT
// Adapted from OpenUsage (https://github.com/robinebers/openusage) at 4ce7887.
// Copyright (c) Robin Ebers and contributors. MIT License; see THIRD_PARTY_NOTICES.md.
// swift-format-ignore-file

import CryptoKit
import Darwin
import Foundation

/// Outcome of a Cloud Code call, split so the orchestrator can tell a genuine auth failure (refresh)
/// apart from a transient outage (try the next base URL / strategy, don't refresh).
enum CloudCodeOutcome: Sendable {
    case ok(Data)
    case authFailed
    case unavailable
}

/// Result of a Google OAuth token refresh, split so a dead refresh token reads as expired auth while a
/// 5xx/network failure reads as a transient outage.
enum TokenRefreshOutcome: Sendable {
    case refreshed(accessToken: String, expiresIn: Double)
    case authFailed
    case unavailable
}

/// Public Google installed-app OAuth client pair extracted at runtime from the local Antigravity app.
struct AntigravityOAuthCredentials: Sendable, Equatable {
    var clientID: String
    var clientSecret: String
}

/// Reads Antigravity's installed-app OAuth client credentials from the locally installed
/// `Antigravity.app` bundle (`Contents/Resources/bin/language_server`) so the repository stays free of
/// credential literals. Results are cached in memory per binary size + modification timestamp.
enum AntigravityAppOAuthExtractor {
    private static let clientIDSuffix = Array(".apps.googleusercontent.com".utf8)
    private static let clientSecretPrefix = Array("GOCSPX-".utf8)
    private static let standardSecretLength = 35
    private static let maxCandidatePairs = 9

    /// One-way SHA-256 tie-breakers for ordering Antigravity's primary OAuth pair first when the
    /// Go binary contains multiple Google OAuth client entries.
    private static let preferredClientIDSHA256 = "bf00c418024ba6bf606ccdc37120976e41bc429dd1d46ecf16a729aa532626ea"
    private static let preferredClientSecretSHA256 = "1d2f041093fd95aa8995a038c711d50a7960da09a505381c09a745d6ad0ecc60"

    private final class Cache: @unchecked Sendable {
        struct Entry {
            var path: String
            var fileSize: UInt64
            var modifiedAt: Date?
            var credentials: [AntigravityOAuthCredentials]
        }

        private let lock = NSLock()
        private var entry: Entry?
        private var lastWorking: AntigravityOAuthCredentials?

        func cached(path: String, fileSize: UInt64, modifiedAt: Date?) -> [AntigravityOAuthCredentials]? {
            lock.lock()
            defer { lock.unlock() }
            guard let entry,
                  entry.path == path,
                  entry.fileSize == fileSize,
                  entry.modifiedAt == modifiedAt
            else {
                return nil
            }
            return prioritize(entry.credentials, preferred: lastWorking)
        }

        func store(path: String, fileSize: UInt64, modifiedAt: Date?, credentials: [AntigravityOAuthCredentials]) -> [AntigravityOAuthCredentials] {
            lock.lock()
            defer { lock.unlock() }
            entry = Entry(path: path, fileSize: fileSize, modifiedAt: modifiedAt, credentials: credentials)
            return prioritize(credentials, preferred: lastWorking)
        }

        func recordWorking(_ credentials: AntigravityOAuthCredentials) {
            lock.lock()
            defer { lock.unlock() }
            lastWorking = credentials
        }

        private func prioritize(_ list: [AntigravityOAuthCredentials], preferred: AntigravityOAuthCredentials?) -> [AntigravityOAuthCredentials] {
            guard let preferred, let index = list.firstIndex(of: preferred), index > 0 else {
                return list
            }
            var reordered = list
            reordered.remove(at: index)
            reordered.insert(preferred, at: 0)
            return reordered
        }
    }

    private static let cache = Cache()

    static func defaultBinaryPaths() -> [String] {
        [
            "/Applications/Antigravity.app/Contents/Resources/bin/language_server",
            (NSHomeDirectory() as NSString).appendingPathComponent("Applications/Antigravity.app/Contents/Resources/bin/language_server")
        ]
    }

    /// Blocking file read — call off the main actor.
    static func loadCredentials(binaryPaths: [String] = defaultBinaryPaths()) -> [AntigravityOAuthCredentials] {
        let fm = FileManager.default
        for path in binaryPaths {
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let fileSize = (attrs[.size] as? NSNumber)?.uint64Value,
                  fileSize > 0
            else {
                continue
            }
            let modifiedAt = attrs[.modificationDate] as? Date
            if let cached = cache.cached(path: path, fileSize: fileSize, modifiedAt: modifiedAt) {
                return cached
            }
            let url = URL(fileURLWithPath: path)
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { continue }
            let extracted = extractCredentials(from: data)
            if !extracted.isEmpty {
                return cache.store(path: path, fileSize: fileSize, modifiedAt: modifiedAt, credentials: extracted)
            }
        }
        return []
    }

    static func recordWorking(_ credentials: AntigravityOAuthCredentials) {
        cache.recordWorking(credentials)
    }

    /// Pure byte-level extractor for Go binaries whose `.rodata` string literals are stored
    /// back-to-back without NUL terminators.
    static func extractCredentials(from data: Data) -> [AntigravityOAuthCredentials] {
        let (clientIDs, clientSecrets) = data.withUnsafeBytes { buffer -> ([String], [String]) in
            (extractClientIDs(in: buffer), extractClientSecrets(in: buffer))
        }
        guard !clientIDs.isEmpty, !clientSecrets.isEmpty else { return [] }

        let orderedIDs = orderByPreferredSHA256(clientIDs, targetHex: preferredClientIDSHA256)
        let orderedSecrets = orderByPreferredSHA256(clientSecrets, targetHex: preferredClientSecretSHA256)

        var pairs: [AntigravityOAuthCredentials] = []
        pairs.reserveCapacity(min(orderedIDs.count * orderedSecrets.count, maxCandidatePairs))
        for clientID in orderedIDs {
            for clientSecret in orderedSecrets {
                pairs.append(AntigravityOAuthCredentials(clientID: clientID, clientSecret: clientSecret))
                if pairs.count >= maxCandidatePairs { return pairs }
            }
        }
        return pairs
    }

    private static func extractClientIDs(in buffer: UnsafeRawBufferPointer) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        for suffixStart in findOccurrences(of: clientIDSuffix, in: buffer) {
            let suffixEnd = suffixStart + clientIDSuffix.count
            var hashStart = suffixStart
            let hashLimit = max(0, suffixStart - 64)
            while hashStart > hashLimit, isLowerAlphaNum(buffer[hashStart - 1]) {
                hashStart -= 1
            }
            let hashLength = suffixStart - hashStart
            guard hashLength >= 16, hashStart > 0, buffer[hashStart - 1] == UInt8(ascii: "-") else {
                continue
            }
            let dashIndex = hashStart - 1
            var digitsStart = dashIndex
            let digitsLimit = max(0, dashIndex - 20)
            while digitsStart > digitsLimit, isDigit(buffer[digitsStart - 1]) {
                digitsStart -= 1
            }
            let digitCount = dashIndex - digitsStart
            guard digitCount >= 10 else { continue }

            let candidate: String
            if digitCount <= 13 {
                candidate = String(decoding: buffer[digitsStart..<suffixEnd], as: UTF8.self)
            } else {
                let candidate13 = String(decoding: buffer[(dashIndex - 13)..<suffixEnd], as: UTF8.self)
                let candidate12 = String(decoding: buffer[(dashIndex - 12)..<suffixEnd], as: UTF8.self)
                if sha256Hex(candidate13) == preferredClientIDSHA256 {
                    candidate = candidate13
                } else if sha256Hex(candidate12) == preferredClientIDSHA256 {
                    candidate = candidate12
                } else {
                    candidate = candidate13
                }
            }
            if seen.insert(candidate).inserted {
                result.append(candidate)
            }
        }
        return result
    }

    private static func extractClientSecrets(in buffer: UnsafeRawBufferPointer) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        for start in findOccurrences(of: clientSecretPrefix, in: buffer) {
            var end = start + clientSecretPrefix.count
            let limit = min(buffer.count, start + 64)
            while end < limit, isSecretChar(buffer[end]) {
                end += 1
            }
            let length = end - start
            guard length >= 27 else { continue }
            // Go `.rodata` packs string literals back-to-back without NUL bytes; clamp to Google's
            // fixed 35-character `GOCSPX-` secret length so adjacent strings never bleed in.
            let sliceEnd = length >= standardSecretLength ? start + standardSecretLength : end
            let candidate = String(decoding: buffer[start..<sliceEnd], as: UTF8.self)
            if seen.insert(candidate).inserted {
                result.append(candidate)
            }
        }
        return result
    }

    private static func findOccurrences(of needle: [UInt8], in buffer: UnsafeRawBufferPointer) -> [Int] {
        guard !needle.isEmpty, let base = buffer.baseAddress, buffer.count >= needle.count else {
            return []
        }
        var offsets: [Int] = []
        var offset = 0
        while offset <= buffer.count - needle.count {
            let found = needle.withUnsafeBytes { needleBuffer -> UnsafeMutableRawPointer? in
                guard let needleBase = needleBuffer.baseAddress else { return nil }
                return memmem(base.advanced(by: offset), buffer.count - offset, needleBase, needle.count)
            }
            guard let found else { break }
            let matchOffset = base.distance(to: UnsafeRawPointer(found))
            offsets.append(matchOffset)
            offset = matchOffset + needle.count
        }
        return offsets
    }

    private static func orderByPreferredSHA256(_ values: [String], targetHex: String) -> [String] {
        guard let preferredIndex = values.firstIndex(where: { sha256Hex($0) == targetHex }), preferredIndex > 0 else {
            return values
        }
        var reordered = values
        let preferred = reordered.remove(at: preferredIndex)
        reordered.insert(preferred, at: 0)
        return reordered
    }

    private static func sha256Hex(_ value: String) -> String {
        let hexDigits = Array("0123456789abcdef".utf8)
        var out: [UInt8] = []
        out.reserveCapacity(64)
        for byte in SHA256.hash(data: Data(value.utf8)) {
            out.append(hexDigits[Int(byte >> 4)])
            out.append(hexDigits[Int(byte & 0x0f)])
        }
        return String(decoding: out, as: UTF8.self)
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
    }

    private static func isLowerAlphaNum(_ byte: UInt8) -> Bool {
        isDigit(byte) || (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z"))
    }

    private static func isSecretChar(_ byte: UInt8) -> Bool {
        isLowerAlphaNum(byte)
            || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z"))
            || byte == UInt8(ascii: "_")
            || byte == UInt8(ascii: "-")
    }
}

/// Outcome of querying a Cloud Code endpoint across all configured hosts in priority order.
enum CloudCodeAllHostsOutcome: Sendable {
    case ok([Data])
    case authFailed
    case unavailable
}

/// All network I/O for Antigravity: the local language-server RPC (loopback HTTPS, self-signed), the
/// Google Cloud Code endpoints, and the Google OAuth token refresh.
struct AntigravityUsageClient: Sendable {
    static let lsService = "exa.language_server_pb.LanguageServerService"
    // Daily first for quota reads so active Gemini counters win; production fills missing buckets.
    static let cloudCodeURLs = [
        "https://daily-cloudcode-pa.googleapis.com",
        "https://cloudcode-pa.googleapis.com"
    ]
    // Plan and project lookups prefer production.
    static let loadCodeAssistURLs = [
        "https://cloudcode-pa.googleapis.com",
        "https://daily-cloudcode-pa.googleapis.com"
    ]
    static let fetchModelsPath = "/v1internal:fetchAvailableModels"
    static let loadCodeAssistPath = "/v1internal:loadCodeAssist"
    static let retrieveQuotaPath = "/v1internal:retrieveUserQuota"
    static let quotaSummaryPath = "/v1internal:retrieveUserQuotaSummary"
    static let googleOAuthURL = "https://oauth2.googleapis.com/token"
    static let lsMetadata = ["ideName": "antigravity", "extensionName": "antigravity", "ideVersion": "unknown", "locale": "en"]
    static let clientUserAgent: String = {
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "amd64"
        #endif
        return "antigravity/2.24.0 (aidev_client; os_type=darwin; arch=\(arch))"
    }()
    static let loadCodeAssistPayload = Data(
        #"{"metadata":{"ideType":"ANTIGRAVITY","platform":"PLATFORM_UNSPECIFIED","pluginType":"GEMINI"}}"#.utf8
    )

    /// Loopback session that trusts the LS's self-signed cert; remote calls use full validation.
    var lsHTTP: HTTPClient
    var http: HTTPClient
    /// Resolves installed-app OAuth client pairs (defaults to scanning local `Antigravity.app`).
    var oauthCredentials: @Sendable () -> [AntigravityOAuthCredentials]

    init(
        lsHTTP: HTTPClient = URLSessionHTTPClient(allowsInsecureLoopback: true),
        http: HTTPClient = URLSessionHTTPClient(),
        oauthCredentials: @escaping @Sendable () -> [AntigravityOAuthCredentials] = { AntigravityAppOAuthExtractor.loadCredentials() }
    ) {
        self.lsHTTP = lsHTTP
        self.http = http
        self.oauthCredentials = oauthCredentials
    }

    /// Call a language-server RPC method. Returns nil on a transport failure (port not the live one).
    func callLS(scheme: String, port: Int, csrf: String, method: String) async -> HTTPResponse? {
        guard let url = URL(string: "\(scheme)://127.0.0.1:\(port)/\(Self.lsService)/\(method)") else { return nil }
        let body = try? JSONSerialization.data(withJSONObject: ["metadata": Self.lsMetadata])
        let request = HTTPRequest(
            method: "POST",
            url: url,
            headers: [
                "Content-Type": "application/json",
                "Connect-Protocol-Version": "1",
                "x-codeium-csrf-token": csrf
            ],
            body: body,
            timeout: 10
        )
        return try? await lsHTTP.send(request)
    }

    /// `loadCodeAssist` with Antigravity's client metadata so Google returns `currentTier`/`paidTier`
    /// and `cloudaicompanionProject` instead of only `allowedTiers`.
    func loadCodeAssist(token: String) async -> CloudCodeOutcome {
        await cloudCode(
            path: Self.loadCodeAssistPath,
            urls: Self.loadCodeAssistURLs,
            token: token,
            userAgent: Self.clientUserAgent,
            payload: Self.loadCodeAssistPayload
        )
    }

    /// POST a Cloud Code endpoint, trying each base URL in turn. A 401/403 short-circuits to `.authFailed`
    /// (same token would fail on the other base); other non-2xx / transport errors fall through to the
    /// next base and finally `.unavailable`.
    func cloudCode(path: String, token: String, userAgent: String, body: [String: String]) async -> CloudCodeOutcome {
        let payload = (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8)
        return await cloudCode(path: path, urls: Self.cloudCodeURLs, token: token, userAgent: userAgent, payload: payload)
    }

    /// POST a Cloud Code endpoint on each base URL in order and return every 2xx body in host order.
    /// `daily-cloudcode-pa` can omit the Gemini group while `cloudcode-pa` includes it; stopping early
    /// only when the first host already returned a complete summary merges missing buckets without
    /// extra round-trips when the first host is complete.
    func cloudCodeAllHosts(
        path: String,
        token: String,
        userAgent: String,
        body: [String: String],
        isComplete: (Data) -> Bool = { _ in false }
    ) async -> CloudCodeAllHostsOutcome {
        let payload = (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8)
        var responses: [HTTPResponse] = []
        for (index, base) in Self.cloudCodeURLs.enumerated() {
            guard let url = URL(string: base + path) else { continue }
            let request = Self.cloudCodeRequest(url: url, token: token, userAgent: userAgent, payload: payload)
            guard let response = try? await http.send(request) else { continue }
            responses.append(response)
            if index == 0, (200..<300).contains(response.statusCode), isComplete(response.body) { break }
        }
        let bodies = responses.filter { (200..<300).contains($0.statusCode) }.map(\.body)
        if !bodies.isEmpty { return .ok(bodies) }
        if responses.contains(where: { $0.statusCode == 401 || $0.statusCode == 403 }) { return .authFailed }
        return .unavailable
    }

    private func cloudCode(
        path: String,
        urls: [String],
        token: String,
        userAgent: String,
        payload: Data
    ) async -> CloudCodeOutcome {
        for base in urls {
            guard let url = URL(string: base + path) else { continue }
            let request = Self.cloudCodeRequest(url: url, token: token, userAgent: userAgent, payload: payload)
            guard let response = try? await http.send(request) else { continue }
            if response.statusCode == 401 || response.statusCode == 403 { return .authFailed }
            if (200..<300).contains(response.statusCode) { return .ok(response.body) }
        }
        return .unavailable
    }

    private static func cloudCodeRequest(url: URL, token: String, userAgent: String, payload: Data) -> HTTPRequest {
        HTTPRequest(
            method: "POST",
            url: url,
            headers: [
                "Accept": "application/json",
                "Content-Type": "application/json",
                "Authorization": "Bearer \(token)",
                "User-Agent": userAgent
            ],
            body: payload,
            timeout: 15
        )
    }

    /// Exchange a Google refresh token for a fresh access token using installed-app credentials read
    /// from the local `Antigravity.app`. `invalid_grant` can mean the token belongs to another client,
    /// so try the remaining client pairs before reporting expired auth. Transient failures (5xx /
    /// network / 429) remain "temporarily unavailable" even after an earlier candidate was rejected.
    func refreshGoogleToken(_ refreshToken: String) async -> TokenRefreshOutcome {
        guard let url = URL(string: Self.googleOAuthURL) else { return .unavailable }
        let credentialsList = await loadOffMainActor(oauthCredentials)
        guard !credentialsList.isEmpty else {
            AppLog.warn(LogTag.auth("antigravity"), "Antigravity.app OAuth client credentials not found; skipping token refresh")
            return .authFailed
        }

        for credentials in credentialsList {
            let form = [
                "client_id=\(credentials.clientID.urlFormEncoded)",
                "client_secret=\(credentials.clientSecret.urlFormEncoded)",
                "refresh_token=\(refreshToken.urlFormEncoded)",
                "grant_type=refresh_token"
            ].joined(separator: "&")
            let request = HTTPRequest(
                method: "POST",
                url: url,
                headers: ["Content-Type": "application/x-www-form-urlencoded"],
                body: Data(form.utf8),
                timeout: 15
            )
            guard let response = try? await http.send(request) else { return .unavailable }
            switch response.statusCode {
            case 200..<300:
                guard let decoded = try? JSONDecoder().decode(GoogleTokenResponse.self, from: response.body),
                      let access = decoded.accessToken?.nilIfEmpty
                else {
                    return .unavailable // 2xx but undecodable / empty — treat as transient
                }
                AntigravityAppOAuthExtractor.recordWorking(credentials)
                return .refreshed(accessToken: access, expiresIn: decoded.expiresIn ?? 3600)
            case 408, 429:
                return .unavailable // request timeout / rate limited — transient, not a revoked token
            case 400..<500:
                if let oauthError = try? JSONDecoder().decode(GoogleOAuthErrorResponse.self, from: response.body),
                   oauthError.error == "invalid_client" || oauthError.error == "unauthorized_client"
                    || oauthError.error == "invalid_grant" {
                    continue // the client pair or token/client binding may differ; try next candidate
                }
                return .authFailed
            default:
                return .unavailable // 5xx and anything else — transient
            }
        }
        return .authFailed
    }
}

struct GoogleTokenResponse: Decodable {
    let accessToken: String?
    let expiresIn: Double?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
    }
}

private struct GoogleOAuthErrorResponse: Decodable {
    let error: String?
}
