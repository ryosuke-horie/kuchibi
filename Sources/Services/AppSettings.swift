import Foundation

/// アプリケーション設定の一元管理
/// 全設定値をUserDefaultsで永続化し、デフォルト値とリセット機能を提供する
@MainActor
final class AppSettings: ObservableObject {
    // MARK: - Default Values

    static let defaultOutputMode: OutputMode = .clipboard
    static let defaultSilenceTimeout: TimeInterval = 30
    static let defaultModelName: String = "moonshine-tiny-ja"
    static let defaultUpdateInterval: Double = 0.5
    static let defaultBufferSize: Int = 1024

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let outputMode = "setting.outputMode"
        static let silenceTimeout = "setting.silenceTimeout"
        static let modelName = "setting.modelName"
        static let updateInterval = "setting.updateInterval"
        static let bufferSize = "setting.bufferSize"
    }

    // MARK: - Published Properties

    @Published var outputMode: OutputMode {
        didSet {
            guard !isResetting else { return }
            defaults.set(outputMode.rawValue, forKey: Keys.outputMode)
        }
    }

    @Published var silenceTimeout: TimeInterval {
        didSet {
            guard !isResetting else { return }
            guard silenceTimeout > 0 else {
                silenceTimeout = Self.defaultSilenceTimeout
                return
            }
            defaults.set(silenceTimeout, forKey: Keys.silenceTimeout)
        }
    }

    @Published var modelName: String {
        didSet {
            guard !isResetting else { return }
            defaults.set(modelName, forKey: Keys.modelName)
        }
    }

    @Published var updateInterval: Double {
        didSet {
            guard !isResetting else { return }
            guard updateInterval > 0 else {
                updateInterval = Self.defaultUpdateInterval
                return
            }
            defaults.set(updateInterval, forKey: Keys.updateInterval)
        }
    }

    @Published var bufferSize: Int {
        didSet {
            guard !isResetting else { return }
            guard bufferSize > 0 else {
                bufferSize = Self.defaultBufferSize
                return
            }
            defaults.set(bufferSize, forKey: Keys.bufferSize)
        }
    }

    // MARK: - Private

    private let defaults: UserDefaults
    private var isResetting = false

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // UserDefaultsから復元、未設定時はデフォルト値
        if let saved = defaults.string(forKey: Keys.outputMode),
           let mode = OutputMode(rawValue: saved) {
            self.outputMode = mode
        } else {
            self.outputMode = Self.defaultOutputMode
        }

        let savedTimeout = defaults.double(forKey: Keys.silenceTimeout)
        self.silenceTimeout = savedTimeout > 0 ? savedTimeout : Self.defaultSilenceTimeout

        if let savedModel = defaults.string(forKey: Keys.modelName), !savedModel.isEmpty {
            self.modelName = savedModel
        } else {
            self.modelName = Self.defaultModelName
        }

        let savedInterval = defaults.double(forKey: Keys.updateInterval)
        self.updateInterval = savedInterval > 0 ? savedInterval : Self.defaultUpdateInterval

        let savedBuffer = defaults.integer(forKey: Keys.bufferSize)
        self.bufferSize = savedBuffer > 0 ? savedBuffer : Self.defaultBufferSize
    }

    // MARK: - Reset

    func resetToDefaults() {
        isResetting = true
        defer { isResetting = false }

        defaults.removeObject(forKey: Keys.outputMode)
        defaults.removeObject(forKey: Keys.silenceTimeout)
        defaults.removeObject(forKey: Keys.modelName)
        defaults.removeObject(forKey: Keys.updateInterval)
        defaults.removeObject(forKey: Keys.bufferSize)

        outputMode = Self.defaultOutputMode
        silenceTimeout = Self.defaultSilenceTimeout
        modelName = Self.defaultModelName
        updateInterval = Self.defaultUpdateInterval
        bufferSize = Self.defaultBufferSize
    }
}
