import Foundation
import Darwin

public struct LibraryProfile: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public struct ProfileSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var activeID: String
    public var profiles: [LibraryProfile]
    public var active: LibraryProfile { profiles.first { $0.id == activeID }! }
}

/// The original library stays in place. Every additional profile has a separate database.
/// A file lock makes profile selection atomic with native, Outlook and MCP operations.
public struct ProfileManager: Sendable {
    public let root: URL
    public init(root: URL = Store.defaultDirectory) throws {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        _ = try locked {
            if !FileManager.default.fileExists(atPath: registryURL.path) {
                try save(ProfileSnapshot(activeID: "default", profiles: [
                    LibraryProfile(id: "default", name: "Work"),
                    LibraryProfile(id: UUID().uuidString, name: "University")
                ]))
            }
            return try read()
        }
    }
    public func snapshot() throws -> ProfileSnapshot { try locked { try read() } }
    public func directory(for profile: LibraryProfile) throws -> URL {
        guard validID(profile.id) else { throw AgoraError.invalid("Invalid profile identifier.") }
        if profile.id == "default" { return root }
        let parent = root.appendingPathComponent("Profiles", isDirectory: true)
        let directory = parent.appendingPathComponent(profile.id, isDirectory: true)
        for candidate in [parent, directory] {
            let type = (try? FileManager.default.attributesOfItem(atPath: candidate.path))?[.type] as? FileAttributeType
            guard type != .typeSymbolicLink else { throw AgoraError.invalid("Profile directories cannot be symbolic links.") }
        }
        guard directory.resolvingSymlinksInPath().path.hasPrefix(root.path + "/") else {
            throw AgoraError.invalid("The profile directory must stay inside this Agora library.")
        }
        return directory
    }
    @discardableResult public func create(name: String) throws -> LibraryProfile {
        try locked {
            var value = try read()
            guard value.profiles.count < 50 else { throw AgoraError.invalid("You can create up to 50 profiles.") }
            let profile = LibraryProfile(id: UUID().uuidString, name: try validatedName(name, in: value))
            value.profiles.append(profile)
            try save(value)
            return profile
        }
    }
    public func rename(id: String, name: String) throws {
        try locked {
            var value = try read()
            guard let index = value.profiles.firstIndex(where: { $0.id == id }) else { throw AgoraError.notFound }
            value.profiles[index].name = try validatedName(name, in: value, excluding: id)
            try save(value)
        }
    }
    @discardableResult public func select(id: String) throws -> ProfileSnapshot {
        try locked {
            var value = try read()
            guard value.profiles.contains(where: { $0.id == id }) else { throw AgoraError.notFound }
            value.activeID = id
            try save(value)
            return value
        }
    }
    public func withActiveProfile<T>(expectedID: String, _ operation: (LibraryProfile) throws -> T) throws -> T {
        try locked {
            let value = try read()
            guard value.activeID == expectedID else { throw AgoraError.profileChanged }
            return try operation(value.active)
        }
    }
    private var registryURL: URL { root.appendingPathComponent("profiles.json") }
    private func validID(_ id: String) -> Bool { id == "default" || UUID(uuidString: id) != nil }
    private func key(_ name: String) -> String { name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
    private func validatedName(_ name: String, in value: ProfileSnapshot, excluding id: String? = nil) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60, !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw AgoraError.invalid("Use a profile name of 1–60 characters.")
        }
        guard !value.profiles.contains(where: { $0.id != id && key($0.name) == key(name) }) else {
            throw AgoraError.invalid("A profile with this name already exists.")
        }
        return name
    }
    private func read() throws -> ProfileSnapshot {
        let attributes = try FileManager.default.attributesOfItem(atPath: registryURL.path)
        guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 65_536 else { throw AgoraError.invalid("The profile settings file is too large.") }
        let value = try JSONDecoder().decode(ProfileSnapshot.self, from: Data(contentsOf: registryURL))
        guard value.schemaVersion == 1, (1...50).contains(value.profiles.count),
              value.profiles.contains(where: { $0.id == "default" }),
              value.profiles.contains(where: { $0.id == value.activeID }),
              Set(value.profiles.map { $0.id.lowercased() }).count == value.profiles.count,
              value.profiles.allSatisfy({ validID($0.id) }) else { throw AgoraError.invalid("The profile settings are invalid. Restore profiles.json from a backup.") }
        for profile in value.profiles { _ = try validatedName(profile.name, in: value, excluding: profile.id) }
        return value
    }
    private func save(_ value: ProfileSnapshot) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        guard data.count <= 65_536 else { throw AgoraError.invalid("The profile names are too long to save. Use a shorter name.") }
        try data.write(to: registryURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: registryURL.path)
    }
    private func locked<T>(_ operation: () throws -> T) throws -> T {
        let descriptor = open(root.appendingPathComponent(".profiles.lock").path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw AgoraError.storage("Could not open the profile lock.") }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw AgoraError.storage("Could not lock the profile settings.") }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try operation()
    }
}

/// MCP conversations stay bound to their initial profile. Switching in Agora requires
/// reconnecting the AI client, so an old conversation cannot write into a new world.
public final class ProfileSession: @unchecked Sendable {
    public let manager: ProfileManager?
    public let profile: LibraryProfile?
    public let store: Store
    public init(environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        if let path = environment["AGORA_PROFILE_ROOT"], !path.isEmpty {
            guard (environment["AGORA_DATA_DIR"] ?? "").isEmpty else { throw AgoraError.invalid("Configure either AGORA_PROFILE_ROOT or AGORA_DATA_DIR, not both.") }
            let manager = try ProfileManager(root: URL(fileURLWithPath: path))
            let profile = try manager.snapshot().active
            self.manager = manager; self.profile = profile
            store = try Store(directory: manager.directory(for: profile))
        } else if let path = environment["AGORA_DATA_DIR"], !path.isEmpty {
            manager = nil; profile = nil; store = try Store(directory: URL(fileURLWithPath: path))
        } else {
            let manager = try ProfileManager(root: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Agora"))
            let profile = try manager.snapshot().active
            self.manager = manager; self.profile = profile
            store = try Store(directory: manager.directory(for: profile))
        }
    }
    public func call(_ name: String, args: [String: Any]) throws -> Any {
        if let manager, let profile {
            return try manager.withActiveProfile(expectedID: profile.id) { _ in try Commands.call(name, args: args, store: store) }
        }
        return try Commands.call(name, args: args, store: store)
    }
}
