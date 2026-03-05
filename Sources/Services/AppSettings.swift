import Foundation

/// アプリケーション設定の一元管理
/// 全設定値をUserDefaultsで永続化し、デフォルト値とリセット機能を提供する
@MainActor
final class AppSettings: ObservableObject {
    // MARK: - Default Values

    static let defaultOutputMode: OutputMode = .autoInput
    static let defaultSilenceTimeout: TimeInterval = 30
    static let defaultModel: WhisperModel = .base
    static let defaultUpdateInterval: Double = 0.5
    static let defaultBufferSize: Int = 1024
    static let defaultNoiseSuppressionEnabled: Bool = true
    static let defaultVadEnabled: Bool = true
    static let defaultVadThreshold: Float = 0.01
    static let defaultTextPostprocessingEnabled: Bool = true
    static let defaultMonitoringEnabled: Bool = true

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let outputMode = "setting.outputMode"
        static let silenceTimeout = "setting.silenceTimeout"
        static let modelName = "setting.modelName"
        static let updateInterval = "setting.updateInterval"
        static let bufferSize = "setting.bufferSize"
        static let noiseSuppressionEnabled = "setting.noiseSuppressionEnabled"
        static let vadEnabled = "setting.vadEnabled"
        static let vadThreshold = "setting.vadThreshold"
        static let textPostprocessingEnabled = "setting.textPostprocessingEnabled"
        static let monitoringEnabled = "setting.monitoringEnabled"
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

    @Published var model: WhisperModel {
        didSet {
            guard !isResetting else { return }
            defaults.set(model.rawValue, forKey: Keys.modelName)
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

    @Published var noiseSuppressionEnabled: Bool {
        didSet {
            guard !isResetting else { return }
            defaults.set(noiseSuppressionEnabled, forKey: Keys.noiseSuppressionEnabled)
        }
    }

    @Published var vadEnabled: Bool {
        didSet {
            guard !isResetting else { return }
            defaults.set(vadEnabled, forKey: Keys.vadEnabled)
        }
    }

    @Published var vadThreshold: Float {
        didSet {
            guard !isResetting else { return }
            guard vadThreshold >= 0.0, vadThreshold <= 1.0 else {
                vadThreshold = Self.defaultVadThreshold
                return
            }
            defaults.set(vadThreshold, forKey: Keys.vadThreshold)
        }
    }

    @Published var textPostprocessingEnabled: Bool {
        didSet {
            guard !isResetting else { return }
            defaults.set(textPostprocessingEnabled, forKey: Keys.textPostprocessingEnabled)
        }
    }

    @Published var monitoringEnabled: Bool {
        didSet {
            guard !isResetting else { return }
            defaults.set(monitoringEnabled, forKey: Keys.monitoringEnabled)
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

        if let saved = defaults.string(forKey: Keys.modelName),
           let model = WhisperModel(rawValue: saved) {
            self.model = model
        } else {
            self.model = Self.defaultModel
        }

        let savedInterval = defaults.double(forKey: Keys.updateInterval)
        self.updateInterval = savedInterval > 0 ? savedInterval : Self.defaultUpdateInterval

        let savedBuffer = defaults.integer(forKey: Keys.bufferSize)
        self.bufferSize = savedBuffer > 0 ? savedBuffer : Self.defaultBufferSize

        // Bool の復元: UserDefaults にキーが存在しない場合はデフォルト値を使用
        if defaults.object(forKey: Keys.noiseSuppressionEnabled) != nil {
            self.noiseSuppressionEnabled = defaults.bool(forKey: Keys.noiseSuppressionEnabled)
        } else {
            self.noiseSuppressionEnabled = Self.defaultNoiseSuppressionEnabled
        }

        if defaults.object(forKey: Keys.vadEnabled) != nil {
            self.vadEnabled = defaults.bool(forKey: Keys.vadEnabled)
        } else {
            self.vadEnabled = Self.defaultVadEnabled
        }

        let savedThreshold = defaults.float(forKey: Keys.vadThreshold)
        if defaults.object(forKey: Keys.vadThreshold) != nil, savedThreshold >= 0.0, savedThreshold <= 1.0 {
            self.vadThreshold = savedThreshold
        } else {
            self.vadThreshold = Self.defaultVadThreshold
        }

        if defaults.object(forKey: Keys.textPostprocessingEnabled) != nil {
            self.textPostprocessingEnabled = defaults.bool(forKey: Keys.textPostprocessingEnabled)
        } else {
            self.textPostprocessingEnabled = Self.defaultTextPostprocessingEnabled
        }

        if defaults.object(forKey: Keys.monitoringEnabled) != nil {
            self.monitoringEnabled = defaults.bool(forKey: Keys.monitoringEnabled)
        } else {
            self.monitoringEnabled = Self.defaultMonitoringEnabled
        }
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
        defaults.removeObject(forKey: Keys.noiseSuppressionEnabled)
        defaults.removeObject(forKey: Keys.vadEnabled)
        defaults.removeObject(forKey: Keys.vadThreshold)
        defaults.removeObject(forKey: Keys.textPostprocessingEnabled)
        defaults.removeObject(forKey: Keys.monitoringEnabled)

        outputMode = Self.defaultOutputMode
        silenceTimeout = Self.defaultSilenceTimeout
        model = Self.defaultModel
        updateInterval = Self.defaultUpdateInterval
        bufferSize = Self.defaultBufferSize
        noiseSuppressionEnabled = Self.defaultNoiseSuppressionEnabled
        vadEnabled = Self.defaultVadEnabled
        vadThreshold = Self.defaultVadThreshold
        textPostprocessingEnabled = Self.defaultTextPostprocessingEnabled
        monitoringEnabled = Self.defaultMonitoringEnabled
    }
}
