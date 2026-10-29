import Foundation

public enum StorageError: Error, Equatable, Sendable {
    case invalidRelativePath(String)
    case pathEscapesBase(String)
    case alreadyExists(String)
    case notFound(String)
    case corrupted(String)
    case unsupportedSchema(found: Int, supported: Int)
    case locked(String)
    case deletionNotConfirmed
    case io(String)
}

public enum PathValidator {
    /// Resolves `relative` under `base`, rejecting absolute paths, `..`, NUL and
    /// anything that (after symlink resolution) lands outside `base`.
    public static func resolve(_ relative: String, under base: URL) throws -> URL {
        guard !relative.isEmpty, !relative.hasPrefix("/"), !relative.contains("\0") else {
            throw StorageError.invalidRelativePath(relative)
        }
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.contains("..") else { throw StorageError.invalidRelativePath(relative) }

        let basePath = realPath(base.path)
        let candidate = realPath(URL(fileURLWithPath: basePath).appendingPathComponent(relative).path)
        let prefix = basePath.hasSuffix("/") ? basePath : basePath + "/"
        guard candidate.hasPrefix(prefix) else { throw StorageError.pathEscapesBase(relative) }
        return URL(fileURLWithPath: candidate)
    }

    /// realpath() of the deepest existing ancestor (follows symlinks), plus the not-yet-existing tail.
    /// Foundation's resolvingSymlinksInPath() does not follow symlinks when the leaf is missing.
    private static func realPath(_ path: String) -> String {
        var existing = (path as NSString).standardizingPath
        var tail: [String] = []
        while existing != "/", !FileManager.default.fileExists(atPath: existing) {
            tail.insert((existing as NSString).lastPathComponent, at: 0)
            existing = (existing as NSString).deletingLastPathComponent
        }
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let resolved = realpath(existing, &buffer).map { String(cString: $0) } ?? existing
        return tail.reduce(resolved) { ($0 as NSString).appendingPathComponent($1) }
    }
}
