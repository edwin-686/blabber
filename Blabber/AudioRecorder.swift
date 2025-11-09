import AVFoundation
import Foundation
import os.log

class AudioRecorder {

    private static let logger = OSLog(subsystem: "com.blabber.app", category: "audio")

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?

    // Expose the recorder for audio level monitoring
    var recorder: AVAudioRecorder? {
        return audioRecorder
    }

    func startRecording() {
        #if DEBUG
        print("AudioRecorder: Starting recording...")
        #endif

        do {
            // Create temporary file
            let tempDir = FileManager.default.temporaryDirectory
            recordingURL = tempDir.appendingPathComponent("recording_\(Date().timeIntervalSince1970).wav")

            #if DEBUG
            print("AudioRecorder: Recording to \(recordingURL?.path ?? "unknown")")
            #endif

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 16000.0,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]

            audioRecorder = try AVAudioRecorder(url: recordingURL!, settings: settings)
            audioRecorder?.record()

            #if DEBUG
            print("AudioRecorder: Recording started successfully")
            #endif

        } catch {
            os_log(.error, log: Self.logger, "Failed to start recording: %{public}s", error.localizedDescription)
        }
    }

    func stopRecording() -> URL? {
        #if DEBUG
        print("AudioRecorder: Stopping recording...")
        #endif
        audioRecorder?.stop()
        #if DEBUG
        print("AudioRecorder: Recording stopped, file at: \(recordingURL?.path ?? "unknown")")
        #endif
        return recordingURL
    }
}
