import CryptoKit
import Foundation
import IOKit

/// OmniRoute's local CLI credential (`x-omniroute-cli-token`).
///
/// OmniRoute accepts this machine-bound token on its loopback management API, so
/// RouteBar can read providers and analytics even when the dashboard has a
/// password. The derivation mirrors `bin/cli/utils/cliToken.mjs`:
/// `HMAC-SHA256(key: lowercase IOPlatformUUID, message: salt)` as hex, where the
/// salt comes from `OMNIROUTE_CLI_SALT` or `<data dir>/cli-token-salt.json`.
public enum CLIToken {
    public static let header = "x-omniroute-cli-token"
    static let fallbackSalt = "omniroute-cli-auth-v1"
    static let saltFileName = "cli-token-salt.json"

    public static func current(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        if let explicit = environment["OMNIROUTE_CLI_TOKEN"], !explicit.isEmpty {
            return explicit
        }
        guard let machineID = platformUUID() else { return nil }
        let salt = environment["OMNIROUTE_CLI_SALT"].flatMap { $0.isEmpty ? nil : $0 }
            ?? establishSalt(in: OmniRoute.dataDirectory(environment: environment))
            ?? fallbackSalt
        return derive(machineID: machineID, salt: salt)
    }

    public static func derive(machineID: String, salt: String) -> String {
        let key = SymmetricKey(data: Data(machineID.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(salt.utf8), using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    /// Reads the persisted salt, creating it exactly like OmniRoute does
    /// (exclusive create, owner-only) so the CLI, the server and RouteBar agree.
    static func establishSalt(in directory: URL) -> String? {
        let file = directory.appendingPathComponent(saltFileName)
        if let existing = readSalt(at: file) { return existing }

        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        let generated = bytes.map { String(format: "%02x", $0) }.joined()
        guard let payload = try? JSONSerialization.data(withJSONObject: ["salt": generated]) else { return nil }

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = open(file.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        if descriptor < 0 {
            return errno == EEXIST ? readSalt(at: file) : nil
        }
        defer { close(descriptor) }
        let written = payload.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
        return written == payload.count ? generated : nil
    }

    static func readSalt(at file: URL) -> String? {
        guard let data = try? Data(contentsOf: file),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let salt = object["salt"] as? String,
              salt.count == 64,
              salt.allSatisfy({ $0.isHexDigit && !$0.isUppercase })
        else { return nil }
        return salt
    }

    /// The raw hardware UUID, lowercased like `node-machine-id`'s `machineIdSync(true)`.
    static func platformUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        let property = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)
        return (property?.takeRetainedValue() as? String)?.lowercased()
    }
}
