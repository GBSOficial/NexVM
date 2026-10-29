import Foundation

public enum DiskImageCreator {
    /// Creates a sparse raw image of `sizeGiB` at `relativePath` inside the bundle.
    /// Refuses to overwrite. Raw sparse is an open format and needs no external tool.
    @discardableResult
    public static func createSparseRaw(in bundle: VMBundle, relativePath: String, sizeGiB: Int) throws -> URL {
        guard sizeGiB > 0 else { throw StorageError.invalidRelativePath("size must be positive") }
        let url = try PathValidator.resolve(relativePath, under: bundle.url)
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path) else { throw StorageError.alreadyExists(relativePath) }
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw StorageError.io("cannot create \(relativePath)")
        }
        do {
            let h = try FileHandle(forWritingTo: url)
            defer { try? h.close() }
            try h.truncate(atOffset: UInt64(sizeGiB) * 1024 * 1024 * 1024)
        } catch {
            try? fm.removeItem(at: url)  // the file we just created
            throw StorageError.io(error.localizedDescription)
        }
        return url
    }
}

public enum ISOValidator {
    public enum Issue: Error, Equatable, Sendable {
        case notFound
        case notAFile
        case wrongExtension
        case tooSmall
        case missingISO9660Signature
    }

    /// Cheap structural check: regular file, `.iso`, ISO-9660 "CD001" signature at sector 16.
    /// It does NOT verify the guest CPU architecture; that remains unchecked.
    public static func validate(path: String) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else { throw Issue.notFound }
        guard !isDir.boolValue else { throw Issue.notAFile }
        guard URL(fileURLWithPath: path).pathExtension.lowercased() == "iso" else { throw Issue.wrongExtension }
        guard let h = FileHandle(forReadingAtPath: path) else { throw Issue.notFound }
        defer { try? h.close() }
        try h.seek(toOffset: 0x8000)
        guard let data = try h.read(upToCount: 6), data.count == 6 else { throw Issue.tooSmall }
        guard data.dropFirst().elementsEqual("CD001".utf8) else { throw Issue.missingISO9660Signature }
    }
}
