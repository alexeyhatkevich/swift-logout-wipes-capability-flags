import Foundation
import Testing
@testable import LogoutWipe

/// Cold start: a fresh store on the given disk, then the module's one-time initialize().
@MainActor
private func launch(_ module: FeatureModule, disk: Disk = Disk()) -> KeyValueStore {
    let store = KeyValueStore(disk: disk)
    module.initialize(store: store)
    return store
}

@MainActor
@Suite("Naive: capability in session scope")
struct NaiveTests {
    @Test func test_naive_capability_visible_right_after_cold_start() {
        // Proves the bug is invisible on the happy path: fresh launch shows the right screen.
        let store = launch(NaiveSearchModule())
        #expect(SearchScreen.variant(in: store) == .advanced)
    }

    @Test func test_naive_sign_out_then_sign_in_shows_fallback_screen() {
        // Proves the reported bug: log out, log back in without relaunch -> wrong screen.
        let store = launch(NaiveSearchModule())
        store.logOut()
        store.set("token-123", for: "authToken", scope: .session) // the next login
        #expect(SearchScreen.variant(in: store) == .basicFallback)
    }

    @Test func test_naive_guest_launch_reset_loses_capability_immediately() {
        // Proves a startup reset (guest launch) breaks it even before any sign-out.
        let store = launch(NaiveSearchModule())
        store.logOut() // reset performed during launch
        #expect(store.value(for: advancedSearchCapabilityKey) == nil)
    }

    @Test func test_naive_only_a_cold_start_brings_it_back() {
        // Proves why "kill and relaunch" was the workaround: initialize() runs again.
        let disk = Disk()
        let store = launch(NaiveSearchModule(), disk: disk)
        store.logOut()
        #expect(SearchScreen.variant(in: store) == .basicFallback)
        let relaunched = launch(NaiveSearchModule(), disk: disk)
        #expect(SearchScreen.variant(in: relaunched) == .advanced)
    }
}

@MainActor
@Suite("Naive + observer: re-publish on userWillLogOut")
struct NaiveObservingTests {
    @Test func test_naive_observer_does_run_during_logout() {
        // Proves the handler is not the problem: it fires, synchronously, inside logOut().
        let store = launch(NaiveObservingSearchModule())
        var valueSeenInsideNotification: String?
        let token = store.notificationCenter.addObserver(
            forName: .userWillLogOut, object: store, queue: nil
        ) { _ in
            MainActor.assumeIsolated {
                valueSeenInsideNotification = store.value(for: advancedSearchCapabilityKey)
            }
        }
        defer { store.notificationCenter.removeObserver(token) }
        store.logOut()
        #expect(valueSeenInsideNotification == "true")
    }

    @Test func test_naive_observer_value_is_wiped_after_the_notification() {
        // Proves the trap: will-notification fires BEFORE the wipe, so the re-published value dies.
        let module = NaiveObservingSearchModule()
        let store = launch(module)
        store.logOut()
        #expect(store.value(for: advancedSearchCapabilityKey) == nil)
        #expect(SearchScreen.variant(in: store) == .basicFallback)
    }
}

@MainActor
@Suite("Fixed: capability in persisted scope")
struct FixedTests {
    @Test func test_fixed_capability_survives_logout() {
        // Proves the fix: logOut() only wipes session keys.
        let store = launch(FixedSearchModule())
        store.logOut()
        #expect(SearchScreen.variant(in: store) == .advanced)
    }

    @Test func test_fixed_capability_survives_repeated_logout_login_cycles() {
        // Proves there is no "first logout only" luck involved.
        let store = launch(FixedSearchModule())
        for i in 0..<3 {
            store.set("token-\(i)", for: "authToken", scope: .session)
            store.logOut()
        }
        #expect(SearchScreen.variant(in: store) == .advanced)
    }

    @Test func test_fixed_logout_still_wipes_real_session_data() {
        // Proves the fix did not weaken logout: user data is still erased.
        let store = launch(FixedSearchModule())
        store.set("token-123", for: "authToken", scope: .session)
        store.logOut()
        #expect(store.value(for: "authToken") == nil)
    }

    @Test func test_fixed_relaunch_restores_capability_from_disk() {
        // Proves cold starts stay consistent: the persisted value is restored before initialize().
        let disk = Disk()
        _ = launch(FixedSearchModule(), disk: disk)
        let relaunched = KeyValueStore(disk: disk) // no module initialize() yet
        #expect(SearchScreen.variant(in: relaunched) == .advanced)
    }
}

@MainActor
@Suite("Edge: listening to the right notification")
struct NotificationOrderTests {
    @Test func test_did_log_out_handler_runs_after_the_wipe() {
        // Proves the alternative: a handler on userDidLogOut sees the store already cleaned,
        // so anything it writes there survives (useful for data that really is per-session).
        let store = launch(NaiveSearchModule())
        let token = store.notificationCenter.addObserver(
            forName: .userDidLogOut, object: store, queue: nil
        ) { _ in
            MainActor.assumeIsolated {
                store.set("true", for: advancedSearchCapabilityKey, scope: .session)
            }
        }
        defer { store.notificationCenter.removeObserver(token) }
        store.logOut()
        #expect(SearchScreen.variant(in: store) == .advanced)
    }
}
