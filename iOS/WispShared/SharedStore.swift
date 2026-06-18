import Foundation

enum WispMode: String, CaseIterable {
    case dictate
    case compose

    var title: String {
        switch self {
        case .dictate: "Dictate"
        case .compose: "Compose"
        }
    }
}

enum SharedStore {
    static let appGroupID = "group.local.wisp.mobile"

    private enum Key {
        static let latestText = "latestText"
        static let latestDate = "latestDate"
        static let pendingMode = "pendingMode"
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func saveLatestText(_ text: String) {
        defaults.set(text, forKey: Key.latestText)
        defaults.set(Date(), forKey: Key.latestDate)
    }

    static func latestText() -> String {
        defaults.string(forKey: Key.latestText) ?? ""
    }

    static func savePendingMode(_ mode: WispMode) {
        defaults.set(mode.rawValue, forKey: Key.pendingMode)
    }

    static func consumePendingMode() -> WispMode? {
        guard let raw = defaults.string(forKey: Key.pendingMode),
              let mode = WispMode(rawValue: raw) else {
            return nil
        }

        defaults.removeObject(forKey: Key.pendingMode)
        return mode
    }
}
