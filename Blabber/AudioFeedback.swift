import Cocoa
import AVFoundation

class AudioFeedback {

    // System sound names
    private let startSoundName = "Blow"
    private let stopSoundName = "Pop"
    private let transcribingSoundName = "Morse" // Subtle sound for transcription process

    // Keep strong references to sounds to prevent premature deallocation
    private var startSound: NSSound?
    private var stopSound: NSSound?
    private var transcribingSound: NSSound?

    init() {
        // Preload sounds during initialization to prevent first-play delay
        startSound = NSSound(named: startSoundName)
        stopSound = NSSound(named: stopSoundName)
        transcribingSound = NSSound(named: transcribingSoundName)

        // Set transcribing sound to loop continuously
        transcribingSound?.loops = true
    }

    func playStartSound() {
        guard SettingsManager.shared.audioFeedbackEnabled else { return }

        // Recreate sound if it doesn't exist
        if startSound == nil {
            startSound = NSSound(named: startSoundName)
        }

        if let sound = startSound {
            sound.stop() // Stop any previous playback
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    func playStopSound() {
        guard SettingsManager.shared.audioFeedbackEnabled else { return }

        // Recreate sound if it doesn't exist
        if stopSound == nil {
            stopSound = NSSound(named: stopSoundName)
        }

        if let sound = stopSound {
            sound.stop() // Stop any previous playback
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    func startTranscribingSound() {
        guard SettingsManager.shared.audioFeedbackEnabled else { return }

        // Recreate sound if it doesn't exist
        if transcribingSound == nil {
            transcribingSound = NSSound(named: transcribingSoundName)
            transcribingSound?.loops = true
        }

        if let sound = transcribingSound {
            sound.stop() // Stop any previous playback
            sound.volume = 0.15 // Make it very subtle (15% volume)
            sound.play()
        }
    }

    func stopTranscribingSound() {
        transcribingSound?.stop()
    }
}
