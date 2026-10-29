import Foundation

public enum QMPMessage: Equatable, Sendable {
    case greeting(version: String)
    case success(id: String?)
    case failure(errorClass: String, description: String, id: String?)
    case event(name: String)
}

public enum QMPError: Error, Equatable, Sendable {
    case malformed(String)
}

public enum QMP {
    /// Parses one JSON line sent by QEMU.
    public static func parse(_ line: Data) throws -> QMPMessage {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            throw QMPError.malformed(String(decoding: line.prefix(120), as: UTF8.self))
        }
        if let q = obj["QMP"] as? [String: Any] {
            let v = (q["version"] as? [String: Any])?["qemu"] as? [String: Any]
            let parts = ["major", "minor", "micro"].compactMap { (v?[$0] as? Int).map(String.init) }
            return .greeting(version: parts.joined(separator: "."))
        }
        if let name = obj["event"] as? String { return .event(name: name) }
        let id = obj["id"] as? String
        if obj["return"] != nil { return .success(id: id) }
        if let err = obj["error"] as? [String: Any] {
            return .failure(errorClass: err["class"] as? String ?? "", description: err["desc"] as? String ?? "", id: id)
        }
        throw QMPError.malformed("unrecognized QMP message")
    }

    /// Encodes `{"execute": ..., "id": ...}\n`. Command names come from a fixed set, not user text.
    public static func encode(_ command: Command, id: String) -> Data {
        var d = (try? JSONSerialization.data(withJSONObject: ["execute": command.rawValue, "id": id],
                                             options: [.sortedKeys])) ?? Data()
        d.append(0x0A)
        return d
    }

    public enum Command: String, Sendable {
        case capabilities = "qmp_capabilities"
        case systemPowerdown = "system_powerdown"   // ACPI power button: safe shutdown
        case systemReset = "system_reset"
        case stop
        case cont
        case queryStatus = "query-status"
        case quit
    }
}
