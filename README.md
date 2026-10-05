# Logout wipes capability flags

A feature module publishes "this build supports advanced search" into a scoped
key-value store at cold start. It used `.session` scope, so the first logout erased it.
After signing back in the UI showed the fallback screen until the app was killed and
relaunched. Re-publishing from the logout notification does not help either: the
notification is posted **before** the store wipes session data.

## How to run

1. Open `Demo/Demo.xcodeproj` in Xcode 16 or newer (the local `LogoutWipe` package resolves automatically).
2. Pick the `Demo` scheme and any iPhone simulator (iOS 17+).
3. Press ⌘R. Use the **Naive / Fixed** switch at the top, then tap **Log in**, **Log out**, **Log in**:
   - **Naive**: the card turns red ("Basic fallback") after the first logout and stays red after
     logging back in. Only **Relaunch** (a simulated cold start) brings Advanced search back.
   - **Fixed**: the card stays green through any number of logout/login cycles, while the
     auth token is still wiped on every logout.
4. Press ⌘U to run the package tests (`LogoutWipeTests`) from the same scheme.

The library is plain Foundation, so `swift test` from the repo root also works on macOS
(see [Run the tests](#run-the-tests)).

## The pieces

- `KeyValueStore` with two scopes: `.session` (wiped by `logOut()`) and `.persisted`
  (written to `Disk` and restored when a new store is created, i.e. at launch).
- `logOut()` posts `.userWillLogOut`, wipes session keys, then posts `.userDidLogOut`.
- `NaiveSearchModule`: publishes the capability with `.session` scope (the bug).
- `NaiveObservingSearchModule`: also re-publishes in a `.userWillLogOut` handler (still lost).
- `FixedSearchModule`: publishes with `.persisted` scope (the fix).

## The fix

A capability describes the build, not the user session:

```swift
store.set("true", for: advancedSearchCapabilityKey, scope: .persisted)
```

## Run the tests

```bash
swift test
```

`test_naive_*` tests assert the broken behaviour (they pass, and document the bug);
`test_fixed_*` tests assert the fix. Requires Swift 6 / Xcode 16 or newer on macOS.

## Takeaways

- Static facts (capabilities, feature presence, configuration) are not session data.
- Know whether a lifecycle notification fires before or after the cleanup. Name them
  `will`/`did` and document it.
- Test "log out, then log in again without relaunching".

License: MIT

Write-up: https://alexeyhatkevich.blogspot.com
