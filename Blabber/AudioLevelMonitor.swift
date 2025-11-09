import AVFoundation
import Foundation
import os.log

/// Monitors audio levels from AVAudioRecorder and provides callbacks for level changes
class AudioLevelMonitor {

    private static let logger = OSLog(subsystem: "com.blabber.app", category: "audio")

    private var timer: Timer?
    private weak var audioRecorder: AVAudioRecorder?
    private var isMonitoring = false

    // Audio level thresholds
    private let silenceThreshold: Float = -40.0  // dB - below this is considered silence
    private let updateInterval: TimeInterval = 0.1  // 10 Hz updates

    // Silence tracking
    private var silenceStartTime: Date?
    private let soundWarningInterval: TimeInterval = 7.0  // Play sound every 7 seconds
    private var hasShownNotification = false  // Track if we've shown notification (only at 20s)
    private var lastSoundWarningTime: Date?  // Track last time we played warning sound
    private var silenceSoundCount = 0  // Count how many times submarine sound has played
    private var lastSoundPlayTime: Date?  // Track when we last played submarine sound
    private var audioDetectionStartTime: Date?  // Track when sustained audio started

    // Callback for when audio level changes
    var onLevelChanged: ((AudioLevel) -> Void)?

    // Callback for notification at 10 seconds (only once)
    var onProlongedSilence: (() -> Void)?

    // Callback for sound warnings (every 5 seconds)
    var onSilenceSoundWarning: (() -> Void)?

    enum AudioLevel {
        case silence        // No audio detected (below threshold)
        case active         // Audio detected (above threshold)
    }

    init() {
        // Empty init
    }

    /// Start monitoring audio levels from the given recorder
    func startMonitoring(audioRecorder: AVAudioRecorder?) {
        guard let recorder = audioRecorder else {
            os_log(.error, log: Self.logger, "No recorder provided")
            return
        }

        self.audioRecorder = recorder
        isMonitoring = true

        // Reset silence tracking
        silenceStartTime = Date()  // Start tracking silence from beginning
        hasShownNotification = false
        lastSoundWarningTime = Date()  // Initialize to now so first warning is at 5 seconds
        silenceSoundCount = 0
        lastSoundPlayTime = nil
        audioDetectionStartTime = nil

        // Enable metering on the recorder
        recorder.isMeteringEnabled = true

        // Start timer to poll audio levels
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.checkAudioLevel()
        }

        #if DEBUG
        print("AudioLevelMonitor: Started monitoring")
        #endif
    }

    /// Stop monitoring audio levels
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        isMonitoring = false
        audioRecorder = nil

        // Reset silence tracking
        silenceStartTime = nil
        hasShownNotification = false
        lastSoundWarningTime = nil
        silenceSoundCount = 0
        lastSoundPlayTime = nil
        audioDetectionStartTime = nil

        #if DEBUG
        print("AudioLevelMonitor: Stopped monitoring")
        #endif
    }

    /// Check current audio level and trigger callback if needed
    private func checkAudioLevel() {
        guard let recorder = audioRecorder, isMonitoring else { return }

        // Update metering values
        recorder.updateMeters()

        // Get average power for channel 0 (mono recording)
        let averagePower = recorder.averagePower(forChannel: 0)

        // Determine audio level state
        let level: AudioLevel = averagePower > silenceThreshold ? .active : .silence

        // Track silence duration
        if level == .silence {
            // Silence detected - reset audio detection timer
            audioDetectionStartTime = nil

            // Check if we've been silent
            if let startTime = silenceStartTime, let lastWarning = lastSoundWarningTime {
                let silenceDuration = Date().timeIntervalSince(startTime)
                let timeSinceLastWarning = Date().timeIntervalSince(lastWarning)

                // Play submarine sound every 5 seconds
                if timeSinceLastWarning >= soundWarningInterval {
                    lastSoundWarningTime = Date()
                    lastSoundPlayTime = Date()  // Track when we played the sound
                    silenceSoundCount += 1

                    #if DEBUG
                    print("AudioLevelMonitor: Silence sound warning #\(silenceSoundCount) (\(Int(silenceDuration))s total)")
                    #endif
                    onSilenceSoundWarning?()

                    // Show notification after 4th submarine sound (= 20 seconds)
                    if silenceSoundCount >= 4 && !hasShownNotification {
                        hasShownNotification = true
                        os_log(.default, log: Self.logger, "WARNING - 4 silence warnings played - showing notification")
                        onProlongedSilence?()
                    }
                }
            }
        } else {
            // Audio detected
            // Check if this might be our own submarine sound (within 2 seconds of playing it)
            let isOurSound = lastSoundPlayTime.map { Date().timeIntervalSince($0) < 2.0 } ?? false

            if isOurSound {
                // Ignore this audio - it's likely our submarine sound being picked up
                // Don't log to reduce noise
            } else {
                // Real audio detected - reset silence tracking immediately
                // This ensures we only trigger after CONTINUOUS silence, not cumulative
                if silenceSoundCount > 0 {
                    #if DEBUG
                    print("AudioLevelMonitor: Audio detected - resetting silence tracking")
                    #endif
                }
                silenceStartTime = Date()
                hasShownNotification = false
                lastSoundWarningTime = Date()
                silenceSoundCount = 0
                lastSoundPlayTime = nil
                audioDetectionStartTime = nil
            }
        }

        // Trigger callback with current level
        onLevelChanged?(level)
    }

    /// Get current audio level as a normalized value (0.0 to 1.0)
    func getCurrentLevel() -> Float {
        guard let recorder = audioRecorder else { return 0.0 }

        recorder.updateMeters()
        let averagePower = recorder.averagePower(forChannel: 0)

        // Normalize from dB range (-160 to 0) to 0.0-1.0
        // -160 dB is effectively silence, 0 dB is max
        let normalizedLevel = max(0.0, min(1.0, (averagePower + 160.0) / 160.0))

        return normalizedLevel
    }
}
