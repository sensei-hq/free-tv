import Foundation
import Security

/// A Plex server found on the local network.
public struct DiscoveredServer: Sendable {
    public let name: String
    public let host: String
    public let port: Int
    public let identifier: String

    public var baseURL: URL {
        URL(string: "http://\(host):\(port)")!
    }
}

/// Parses one GDM (multicast discovery) reply body.
public func parseGDMResponse(_ text: String, host: String)
    -> DiscoveredServer? {
    var headers: [String: String] = [:]
    for line in text.components(separatedBy: .newlines) {
        let parts = line.split(separator: ":", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        if parts.count == 2 {
            headers[parts[0].lowercased()] = parts[1]
        }
    }
    guard let name = headers["name"], !name.isEmpty,
          let portText = headers["port"], let port = Int(portText),
          let identifier = headers["resource-identifier"],
          !identifier.isEmpty else { return nil }
    return DiscoveredServer(name: name, host: host, port: port,
                            identifier: identifier)
}

/// Broadcasts a GDM discovery probe and collects replies.
public final class GDMScanner: Sendable {
    public init() {}

    /// Discovers servers for up to `timeout` seconds.
    public func scan(timeout: TimeInterval = 5) async -> [DiscoveredServer] {
        await Task.detached(priority: .utility) {
            Self.syncScan(timeout: timeout)
        }.value
    }

    private static func syncScan(timeout: TimeInterval)
        -> [DiscoveredServer] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { close(fd) }
        var wait = timeval(tv_sec: Int(timeout), tv_usec: 0)
        withUnsafePointer(to: &wait) {
            _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, $0,
                           socklen_t(MemoryLayout<timeval>.size))
        }
        var dest = sockaddr_in()
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = in_port_t(32400 + 14).bigEndian
        dest.sin_addr = in_addr(s_addr: inet_addr("239.0.0.250"))
        let message = Array("M-SEARCH * HTTP/1.0".utf8)
        message.withUnsafeBufferPointer { buffer in
            withUnsafePointer(to: &dest) { destPtr in
                destPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    _ = sendto(fd, buffer.baseAddress, buffer.count, 0, $0,
                               socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        var found: [String: DiscoveredServer] = [:]
        var buffer = [UInt8](repeating: 0, count: 4096)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            var from = sockaddr_in()
            var fromLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let received = buffer.withUnsafeMutableBufferPointer { pointer in
                withUnsafeMutablePointer(to: &from) { fromPtr in
                    fromPtr.withMemoryRebound(to: sockaddr.self,
                                              capacity: 1) {
                        recvfrom(fd, pointer.baseAddress, pointer.count, 0,
                                 $0, &fromLength)
                    }
                }
            }
            guard received > 0 else { break }
            let text = String(bytes: buffer.prefix(received), encoding: .utf8)
                ?? ""
            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            withUnsafePointer(to: &from) { fromPtr in
                fromPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    _ = getnameinfo($0, fromLength, &hostBuffer,
                                    socklen_t(hostBuffer.count), nil, 0,
                                    NI_NUMERICHOST)
                }
            }
            if let server = parseGDMResponse(text,
                                             host: String(cString: hostBuffer)) {
                found[server.identifier] = server
            }
        }
        return Array(found.values)
    }
}

/// Auth tokens live in the keychain, never in UserDefaults.
public struct KeychainStore: Sendable {
    private let service: String

    public init(service: String = "tv.freetv") {
        self.service = service
    }

    public func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "KeychainStore", code: Int(status))
        }
    }

    public func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result)
            == errSecSuccess,
            let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: "KeychainStore", code: Int(status))
        }
    }
}
