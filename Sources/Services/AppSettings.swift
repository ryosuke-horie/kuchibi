import Foundation

/// アプリケーション設定の一元管理
/// 全設定値をUserDefaultsで永続化し、デフォルト値とリセット機能を提供する
@MainActor
final class AppSettings: ObservableObject {
    // MARK: - Default Values

    static let defaultOutputMode: OutputMode = .autoInput
    /// 音声認識エンジンのデフォルト値。
    /// WhisperKit Large v3 Turbo を採用。
    static let defaultSpeechEngine: SpeechEngine = .whisperKit(.largeV3Turbo)
    static let defaultUpdateInterval: Double = 0.5
    static let defaultBufferSize: Int = 1024
    static let defaultNoiseSuppressionEnabled: Bool = true
    static let defaultVadEnabled: Bool = true
    static let defaultVadThreshold: Float = 0.01
    static let defaultTextPostprocessingEnabled: Bool = true
    static let defaultMonitoringEnabled: Bool = true
    static let defaultSessionSoundEnabled: Bool = true

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let outputMode = "setting.outputMode"
        /// 旧キー（Task 4.1 で `model` プロパティは削除済み）。
        /// `setting.speechEngine` への migration（init 内）と
        /// `resetToDefaults` での旧キー除去のためにキー名のみ残している。
        static let modelName = "setting.modelName"
        static let speechEngine = "setting.speechEngine"
        static let updateInterval = "setting.updateInterval"
        static let bufferSize = "setting.bufferSize"
        static let noiseSuppressionEnabled = "setting.noiseSuppressionEnabled"
        static let vadEnabled = "setting.vadEnabled"
        static let vadThreshold = "setting.vadThreshold"
        static let textPostprocessingEnabled = "setting.textPostprocessingEnabled"
        static let monitoringEnabled = "setting.monitoringEnabled"
        static let sessionSoundEnabled = "setting.sessionSoundEnabled"
    }

    // MARK: - Published Properties

    @Published var outputMode: OutputMode {
        didSet {
            guard !isResetting else { return }
            defaults.set(outputMode.rawValue, forKey: Keys.outputMode)
        }
    }

    /// 音声認識エンジン設定（エンジン種別 + モデル）。
    /// JSON 文字列として `setting.speechEngine` に永続化される。
    @Published var speechEngine: SpeechEngine {
        didSet {
            guard !isResetting else { return }
            persistSpeechEngine(speechEngine)
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

    @Published var sessionSoundEnabled: Bool {
        didSet {
            guard !isResetting else { return }
            defaults.set(sessionSoundEnabled, forKey: Keys.sessionSoundEnabled)
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

        // speechEngine の復元 / migration:
        // 1) 新キー `setting.speechEngine` があればそれを採用
        // 2) 無く、旧キー `setting.modelName` が存在すれば WhisperKit + 対応モデルへ migration し、旧キーを削除
        // 3) どちらも無ければデフォルト (`SpeechEngine.whisperKit(.largeV3Turbo)`)
        if let json = defaults.string(forKey: Keys.speechEngine),
           let data = json.data(using: .utf8),
           let engine = try? JSONDecoder().decode(SpeechEngine.self, from: data) {
            self.speechEngine = engine
        } else if let oldName = defaults.string(forKey: Keys.modelName),
                  let migratedModel = WhisperKitModel(fromLegacy: oldName) {
            let migrated: SpeechEngine = .whisperKit(migratedModel)
            self.speechEngine = migrated
            // didSet は init 中の最初の代入では発火しないため、明示的に書き込む
            Self.writeSpeechEngine(migrated, to: defaults)
            defaults.removeObject(forKey: Keys.modelName)
        } else {
            self.speechEngine = Self.defaultSpeechEngine
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

        if defaults.object(forKey: Keys.sessionSoundEnabled) != nil {
            self.sessionSoundEnabled = defaults.bool(forKey: Keys.sessionSoundEnabled)
        } else {
            self.sessionSoundEnabled = Self.defaultSessionSoundEnabled
        }
    }

    // MARK: - Reset

    func resetToDefaults() {
        isResetting = true
        defer { isResetting = false }

        defaults.removeObject(forKey: Keys.outputMode)
        defaults.removeObject(forKey: Keys.modelName)
        defaults.removeObject(forKey: Keys.speechEngine)
        defaults.removeObject(forKey: Keys.updateInterval)
        defaults.removeObject(forKey: Keys.bufferSize)
        defaults.removeObject(forKey: Keys.noiseSuppressionEnabled)
        defaults.removeObject(forKey: Keys.vadEnabled)
        defaults.removeObject(forKey: Keys.vadThreshold)
        defaults.removeObject(forKey: Keys.textPostprocessingEnabled)
        defaults.removeObject(forKey: Keys.monitoringEnabled)
        defaults.removeObject(forKey: Keys.sessionSoundEnabled)

        outputMode = Self.defaultOutputMode
        speechEngine = Self.defaultSpeechEngine
        updateInterval = Self.defaultUpdateInterval
        bufferSize = Self.defaultBufferSize
        noiseSuppressionEnabled = Self.defaultNoiseSuppressionEnabled
        vadEnabled = Self.defaultVadEnabled
        vadThreshold = Self.defaultVadThreshold
        textPostprocessingEnabled = Self.defaultTextPostprocessingEnabled
        monitoringEnabled = Self.defaultMonitoringEnabled
        sessionSoundEnabled = Self.defaultSessionSoundEnabled
    }

    // MARK: - Persistence Helpers

    private func persistSpeechEngine(_ engine: SpeechEngine) {
        Self.writeSpeechEngine(engine, to: defaults)
    }

    /// `SpeechEngine` を JSON 文字列にエンコードして UserDefaults に書き込む。
    /// init 中（`self` がまだ完全に初期化されていない時点）からも呼べるよう static にしている。
    private static func writeSpeechEngine(_ engine: SpeechEngine, to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(engine),
           let json = String(data: data, encoding: .utf8) {
            defaults.set(json, forKey: Keys.speechEngine)
        }
    }
}
