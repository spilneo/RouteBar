import Darwin
import Foundation

/// Where an OmniRoute server lives and how its URLs are built.
public enum ServerAddress {
    /// Turns what a user types (`192.168.1.5`, `box.local:3000`, `https://ai.example.com`)
    /// into a server root URL. A bare host gets `http://` and `defaultPort`, a full URL
    /// keeps its own scheme and port. Paths, queries and credentials are dropped.
    public static func normalize(_ input: String, defaultPort: Int = OmniRoute.port) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        let hasScheme = trimmed.range(of: "^[a-zA-Z][a-zA-Z0-9+.-]*://", options: .regularExpression) != nil
        guard var components = URLComponents(string: hasScheme ? trimmed : "http://\(trimmed)"),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty
        else { return nil }
        components.scheme = scheme
        components.host = host.lowercased()
        if !hasScheme, components.port == nil { components.port = defaultPort }
        components.user = nil
        components.password = nil
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// True for `localhost` and loopback literals. Only these may receive the machine-bound CLI token.
    public static func isLoopback(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]")) else { return false }
        if host == "localhost" || host == "::1" { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.first == "127" && parts.allSatisfy { UInt8($0) != nil }
    }

    /// True for hosts that never leave a private network: loopback, RFC 1918,
    /// link-local, CGNAT/Tailscale (100.64/10), `.local` and unqualified names.
    public static func isPrivate(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if isLoopback(url) || host.hasSuffix(".local") || host.hasSuffix(".ts.net") || !host.contains(".") { return true }
        let octets = host.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4 else { return false }
        switch (octets[0], octets[1]) {
        case (10, _), (192, 168), (169, 254): return true
        case (172, 16...31): return true
        case (100, 64...127): return true
        default: return false
        }
    }

    /// The OpenAI-compatible base URL apps paste in: `<root>/v1`.
    public static func endpoint(for root: URL) -> String {
        root.appendingPathComponent("v1").absoluteString
    }

    /// `host:port` without the scheme, for compact labels.
    public static func label(for root: URL) -> String {
        guard let host = root.host else { return root.absoluteString }
        let shown = host.contains(":") ? "[\(host)]" : host
        return root.port.map { "\(shown):\($0)" } ?? shown
    }
}

/// This Mac's address on the local network, so the endpoint works from other devices.
public enum NetworkAddress {
    public struct Interface: Equatable, Sendable {
        public let name: String
        public let address: String

        public init(name: String, address: String) {
            self.name = name
            self.address = address
        }
    }

    /// The best IPv4 address other devices on the LAN can reach, if any.
    public static func lanIPv4() -> String? {
        best(among: interfaces())
    }

    /// Prefers Ethernet and Wi-Fi (`en*`) with a private address. VPN tunnels
    /// (`utun`, `ipsec`, `ppp`), AirDrop (`awdl`, `llw`), bridges and loopback are
    /// skipped because other devices on the LAN cannot reach them.
    public static func best(among interfaces: [Interface]) -> String? {
        let skipped = ["lo", "utun", "ipsec", "ppp", "awdl", "llw", "bridge", "gif", "stf", "anpi", "ap"]
        let candidates = interfaces.filter { interface in
            !skipped.contains { interface.name.hasPrefix($0) }
                && !interface.address.hasPrefix("127.")
                && !interface.address.hasPrefix("169.254.")
        }
        /// Lower is better: Ethernet or Wi-Fi first, then a private address, then the lowest unit (en0 before en1).
        func rank(_ interface: Interface) -> Int {
            let isPrivate = URL(string: "http://\(interface.address)").map(ServerAddress.isPrivate) ?? false
            let unit = min(Int(interface.name.drop { !$0.isNumber }) ?? 999, 999)
            return (interface.name.hasPrefix("en") ? 0 : 4_000) + (isPrivate ? 0 : 2_000) + unit
        }
        return candidates.min { (rank($0), $0.name) < (rank($1), $1.name) }?.address
    }

    /// Up, running, non-loopback IPv4 interfaces.
    static func interfaces() -> [Interface] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var found: [Interface] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let flags = Int32(entry.ifa_flags)
            guard let address = entry.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
            else { continue }
            guard let numeric = String(bytes: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8) else { continue }
            found.append(Interface(name: String(cString: entry.ifa_name), address: numeric))
        }
        return found
    }
}
