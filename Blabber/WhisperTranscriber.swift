import Foundation
import os.log

class WhisperTranscriber {

    private static let logger = OSLog(subsystem: "com.blabber.app", category: "transcription")

    private let whisperPath: String
    private let modelManager = ModelManager.shared
    private var currentProcess: Process?

    init() {
        // Find whisper-cli path (supports both Apple Silicon and Intel Macs)
        let possiblePaths = [
            "/opt/homebrew/bin/whisper-cli",  // Apple Silicon
            "/usr/local/bin/whisper-cli"       // Intel Mac
        ]

        var foundPath: String?
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                foundPath = path
                break
            }
        }

        // Fallback to which command if not found in standard locations
        if foundPath == nil {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            process.arguments = ["whisper-cli"]
            let pipe = Pipe()
            process.standardOutput = pipe

            try? process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    foundPath = path
                }
            }
        }

        if let path = foundPath {
            whisperPath = path
            os_log(.info, log: Self.logger, "Found whisper-cli at %{public}s", whisperPath)
        } else {
            // Fallback to Apple Silicon path for better error messages
            whisperPath = "/opt/homebrew/bin/whisper-cli"
            os_log(.default, log: Self.logger, "WARNING - whisper-cli not found")
            os_log(.default, log: Self.logger, "Install with: brew install whisper-cpp")
        }

        // Check if any model is installed
        if !modelManager.hasAnyModelInstalled() {
            os_log(.default, log: Self.logger, "WARNING - No Whisper models found")
            os_log(.default, log: Self.logger, "Please download a model from Settings > Download Models")
        } else {
            let modelPath = modelManager.getCurrentModelPath().path
            os_log(.info, log: Self.logger, "Using model at %{public}s", modelPath)
        }
    }

    func transcribe(audioFile: URL) -> String? {
        #if DEBUG
        print("WhisperTranscriber: Starting transcription of \(audioFile.path)")
        #endif

        // Get current model path from ModelManager
        let modelPath = modelManager.getCurrentModelPath().path

        // Validate model exists
        guard FileManager.default.fileExists(atPath: modelPath) else {
            os_log(.error, log: Self.logger, "ERROR - Model not found at %{public}s", modelPath)
            os_log(.error, log: Self.logger, "Please download a model from Settings")
            return nil
        }

        #if DEBUG
        print("WhisperTranscriber: Using model: \(modelPath)")
        #endif

        let process = Process()
        process.executableURL = URL(fileURLWithPath: whisperPath)

        // Get language setting
        let language = SettingsManager.shared.transcriptionLanguage

        var arguments = [
            "-m", modelPath,
            "-f", audioFile.path,
            "--output-txt",
            "--no-timestamps",
            "-l", language  // Pass language (or "auto" for auto-detect)
        ]

        #if DEBUG
        print("WhisperTranscriber: Using language: \(language)")
        #endif

        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            // Store process reference for potential abort
            currentProcess = process

            try process.run()
            process.waitUntilExit()

            // Clear process reference after completion
            currentProcess = nil

            #if DEBUG
            print("WhisperTranscriber: Process exited with code \(process.terminationStatus)")
            #endif

            // Check if process was terminated (aborted)
            if process.terminationReason == .uncaughtSignal || process.terminationStatus == 15 {
                os_log(.info, log: Self.logger, "Process was aborted")

                // Cleanup temporary files
                try? FileManager.default.removeItem(at: audioFile)
                let outputFile = audioFile.appendingPathExtension("txt")
                try? FileManager.default.removeItem(at: outputFile)

                return nil
            }

            // whisper-cli appends .txt to the full filename (e.g., audio.wav.txt)
            let outputFile = audioFile.appendingPathExtension("txt")

            if FileManager.default.fileExists(atPath: outputFile.path) {
                let transcription = try String(contentsOf: outputFile, encoding: .utf8)
                os_log(.info, log: Self.logger, "Transcription successful (%{public}d characters)", transcription.count)

                // Cleanup temporary files
                try? FileManager.default.removeItem(at: audioFile)
                try? FileManager.default.removeItem(at: outputFile)

                return transcription.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                os_log(.error, log: Self.logger, "Output file not found at %{public}s", outputFile.path)

                // Try to read error output
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    #if DEBUG
                    print("WhisperTranscriber: Process output: \(output)")
                    #endif
                }
            }

            return nil

        } catch {
            currentProcess = nil
            os_log(.error, log: Self.logger, "Transcription failed with error: %{public}s", error.localizedDescription)
            return nil
        }
    }

    /// Abort current transcription process
    func abort() {
        guard let process = currentProcess, process.isRunning else {
            #if DEBUG
            print("WhisperTranscriber: No active process to abort")
            #endif
            return
        }

        os_log(.info, log: Self.logger, "Aborting transcription process")
        process.terminate()
        currentProcess = nil
    }
}
