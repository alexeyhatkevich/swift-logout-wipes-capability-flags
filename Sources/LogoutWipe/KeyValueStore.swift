import Foundation

/// Where a value lives and how long it survives.
public enum Scope: Sendable {
    /// In memory only. Wiped by `logOut()`.
    case session
    /// Written through to `Disk` and restored when a new store is created (next launch).
    case persisted
}

/// Stand-in for the file system / UserDefaults. Outlives any single `KeyValueStore`,
/// so creating a second store on the same `Disk` simulates an app relaunch.
@MainActor
public final class Disk {
    public private(set) var contents: [String: String] = [:]
    public init() {}
    func write(_ value: String?, for key: String) { contents[key] = value }
}

extension Notification.Name {
    /// Posted by `KeyValueStore.logOut()` BEFORE session data is wiped.
    public static let userWillLogOut = Notification.Name("userWillLogOut")
    /// Posted by `KeyValueStore.logOut()` AFTER session data is wiped.
    public static let userDidLogOut = Notification.Name("userDidLogOut")
}

/// A scoped key-value store, the shape many apps use as their shared state.
@MainActor
public final class KeyValueStore {
    public let notificationCenter: NotificationCenter
    private let disk: Disk
    private var values: [String: String] = [:]
    private var sessionKeys: Set<String> = []

    /// Creating a store == launching the app: persisted data is restored from disk.
    public init(disk: Disk, notificationCenter: NotificationCenter = NotificationCenter()) {
        self.disk = disk
        self.notificationCenter = notificationCenter
        values = disk.contents
    }

    public func set(_ value: String, for key: String, scope: Scope) {
        values[key] = value
        switch scope {
        case .session:
            sessionKeys.insert(key)
            disk.write(nil, for: key)
        case .persisted:
            sessionKeys.remove(key)
            disk.write(value, for: key)
        }
    }

    public func value(for key: String) -> String? { values[key] }

    /// Called on explicit sign-out AND on a guest launch (a reset at startup).
    /// Note the order: observers hear about the logout before the wipe happens.
    public func logOut() {
        notificationCenter.post(name: .userWillLogOut, object: self)
        for key in sessionKeys { values[key] = nil }
        sessionKeys.removeAll()
        notificationCenter.post(name: .userDidLogOut, object: self)
    }
}
