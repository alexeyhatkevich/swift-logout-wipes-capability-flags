import SwiftUI
import LogoutWipe

enum Mode: String, CaseIterable, Identifiable {
    case naive = "Naive"
    case fixed = "Fixed"
    var id: String { rawValue }

    @MainActor func makeModule() -> FeatureModule {
        switch self {
        case .naive: NaiveSearchModule()
        case .fixed: FixedSearchModule()
        }
    }

    var explanation: String {
        switch self {
        case .naive:
            "The module publishes the capability with .session scope. Tap Log out, then Log in: the screen falls back to Basic search and stays there until you tap Relaunch."
        case .fixed:
            "The module publishes the capability with .persisted scope. Log out / Log in as often as you like: Advanced search stays. Session data (the auth token) is still wiped."
        }
    }
}

/// Simulates one app: a Disk that outlives launches, the current store and the module.
@MainActor
@Observable
final class DemoModel {
    var mode: Mode = .naive { didSet { reset() } }
    private(set) var disk: Disk
    private(set) var store: KeyValueStore
    private(set) var launches = 0
    private(set) var log: [String] = []
    private var module: FeatureModule?

    init() {
        let disk = Disk()
        self.disk = disk
        store = KeyValueStore(disk: disk)
        // Launch argument for scripted runs: `-mode fixed` starts in the Fixed implementation.
        // (With @Observable the assignment runs didSet, which already does the first cold start.)
        if UserDefaults.standard.string(forKey: "mode")?.lowercased() == "fixed" { mode = .fixed }
        if launches == 0 { relaunch() }
    }

    /// Launch argument `-autorun 1`: Log in, Log out, Log in (no relaunch).
    func autorunIfRequested() async {
        guard UserDefaults.standard.bool(forKey: "autorun") else { return }
        for step in [logIn, logOut, logIn] {
            try? await Task.sleep(for: .milliseconds(600))
            step()
        }
    }

    var screen: SearchScreen { SearchScreen.variant(in: store) }
    var capability: String { store.value(for: advancedSearchCapabilityKey) ?? "nil" }
    var token: String { store.value(for: "authToken") ?? "nil" }
    var signedIn: Bool { store.value(for: "authToken") != nil }

    func reset() {
        disk = Disk()
        launches = 0
        log = []
        relaunch()
    }

    /// Cold start: new store on the same disk, then the module's one-time initialize().
    func relaunch() {
        store = KeyValueStore(disk: disk)
        let module = mode.makeModule()
        module.initialize(store: store)
        self.module = module
        launches += 1
        append("Cold start #\(launches): module.initialize()")
    }

    func logIn() {
        store.set("token-\(Int.random(in: 100...999))", for: "authToken", scope: .session)
        append("Log in")
    }

    func logOut() {
        store.logOut()
        append("Log out")
    }

    private func append(_ action: String) {
        log.insert("\(action) -> \(screen == .advanced ? "Advanced" : "Basic fallback")", at: 0)
    }
}

struct ContentView: View {
    @State private var model = DemoModel()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Implementation", selection: $model.mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("modePicker")
                    Text(model.mode.explanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("What to watch")
                }

                Section("Search screen the UI would show") {
                    ScreenCard(screen: model.screen)
                    LabeledContent("Capability key", value: model.capability)
                    LabeledContent("Auth token (session)", value: model.token)
                    LabeledContent("Cold starts", value: "\(model.launches)")
                }

                Section {
                    HStack {
                        Button("Log in") { model.logIn() }
                            .disabled(model.signedIn)
                        Spacer()
                        Button("Log out", role: .destructive) { model.logOut() }
                        Spacer()
                        Button("Relaunch") { model.relaunch() }
                    }
                    .buttonStyle(.bordered)
                } header: {
                    Text("Actions")
                } footer: {
                    Text("Try: Log in, Log out, Log in. Then switch modes and repeat. Relaunch simulates killing and reopening the app (same disk, new store).")
                }

                Section("History (newest first)") {
                    ForEach(Array(model.log.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption.monospaced())
                    }
                }
            }
            .navigationTitle("Logout wipes flags")
            .task { await model.autorunIfRequested() }
        }
    }
}

struct ScreenCard: View {
    let screen: SearchScreen

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: screen == .advanced ? "sparkle.magnifyingglass" : "exclamationmark.triangle.fill")
                .font(.title)
            VStack(alignment: .leading) {
                Text(screen == .advanced ? "Advanced search" : "Basic fallback")
                    .font(.headline)
                Text(screen == .advanced ? "Capability present: correct" : "Capability missing: this is the bug")
                    .font(.caption)
            }
            Spacer()
        }
        .padding()
        .foregroundStyle(.white)
        .background(screen == .advanced ? Color.green : Color.red, in: RoundedRectangle(cornerRadius: 12))
        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        .accessibilityIdentifier("screenCard")
    }
}
