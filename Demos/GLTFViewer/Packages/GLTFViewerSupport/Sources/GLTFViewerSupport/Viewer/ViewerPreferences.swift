import Foundation
import Observation

/// App-wide viewing choices (``ViewerSettings``), restored at launch and saved on every change. SamplesView puts it in
/// the environment.
@MainActor
@Observable
final class ViewerPreferences {
    static let storageKey = "GLTFViewer.viewerSettings"

    var settings: ViewerSettings {
        didSet {
            if settings != oldValue {
                defaults.set(settings.storedData, forKey: Self.storageKey)
            }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = ViewerSettings(storedData: defaults.data(forKey: Self.storageKey) ?? Data())
    }
}
