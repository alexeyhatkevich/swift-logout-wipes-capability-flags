import Foundation

/// The key a feature module publishes so the UI knows the feature exists in this build.
public let advancedSearchCapabilityKey = "AdvancedSearchCapability"

/// Something a feature module does once, at cold start.
@MainActor
public protocol FeatureModule: AnyObject {
    func initialize(store: KeyValueStore)
}

/// BUG: publishes a static fact about the build into session-scoped storage.
/// The first `logOut()` erases it and nothing writes it again until the next cold start.
@MainActor
public final class NaiveSearchModule: FeatureModule {
    public init() {}
    public func initialize(store: KeyValueStore) {
        store.set("true", for: advancedSearchCapabilityKey, scope: .session)
    }
}

/// STILL BROKEN: re-publishes from the logout notification. The notification is posted
/// before the store wipes session keys, so the value is erased right after it is written.
@MainActor
public final class NaiveObservingSearchModule: FeatureModule {
    private var token: NSObjectProtocol?
    public init() {}

    public func initialize(store: KeyValueStore) {
        publish(into: store)
        token = store.notificationCenter.addObserver(
            forName: .userWillLogOut, object: store, queue: nil
        ) { [weak self, weak store] _ in
            // post(name:) delivers synchronously on the posting thread (main here).
            MainActor.assumeIsolated {
                guard let self, let store else { return }
                self.publish(into: store)
            }
        }
    }

    private func publish(into store: KeyValueStore) {
        store.set("true", for: advancedSearchCapabilityKey, scope: .session)
    }
}

/// FIX: a capability describes the build, not the user, so it is persisted.
/// `logOut()` leaves it alone and a relaunch restores it from disk.
@MainActor
public final class FixedSearchModule: FeatureModule {
    public init() {}
    public func initialize(store: KeyValueStore) {
        store.set("true", for: advancedSearchCapabilityKey, scope: .persisted)
    }
}

/// Which screen the UI shows, decided purely from the capability key.
public enum SearchScreen: Equatable, Sendable {
    case advanced
    case basicFallback

    @MainActor
    public static func variant(in store: KeyValueStore) -> SearchScreen {
        store.value(for: advancedSearchCapabilityKey) == "true" ? .advanced : .basicFallback
    }
}
