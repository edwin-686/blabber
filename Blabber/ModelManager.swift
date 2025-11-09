import Foundation
import os.log

// Represents a Whisper model available for download
struct WhisperModel {
    let name: String
    let fileName: String
    let sizeInMB: Int
    let description: String
    let isQuantized: Bool
    let recommended: Bool

    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
    }

    var displayName: String {
        "\(name) (\(sizeInMB) MB)" + (recommended ? " - Recommended" : "")
    }

    var dropdownDisplayName: String {
        name + (recommended ? " ⭐ Recommended" : "")
    }
}

class ModelManager {

    static let shared = ModelManager()

    private static let logger = OSLog(subsystem: "com.blabber.app", category: "models")

    // Storage location for models
    private let modelsDirectory: URL

    // Available models catalog
    let availableModels: [WhisperModel] = [
        // Large V3 Turbo (Recommended)
        WhisperModel(
            name: "Large V3 Turbo (Full)",
            fileName: "ggml-large-v3-turbo.bin",
            sizeInMB: 1620,
            description: "Full quality model without quantization. Best accuracy. Recommended.",
            isQuantized: false,
            recommended: true
        ),
        WhisperModel(
            name: "Large V3 Turbo (Q5 Quantized)",
            fileName: "ggml-large-v3-turbo-q5_0.bin",
            sizeInMB: 574,
            description: "Best balance of speed and quality. Smaller download.",
            isQuantized: true,
            recommended: false
        ),
        WhisperModel(
            name: "Large V3 Turbo (Q8 Quantized)",
            fileName: "ggml-large-v3-turbo-q8_0.bin",
            sizeInMB: 874,
            description: "Higher quality quantized model with better accuracy.",
            isQuantized: true,
            recommended: false
        ),

        // Other models
        WhisperModel(
            name: "Large V3 (Full)",
            fileName: "ggml-large-v3.bin",
            sizeInMB: 3100,
            description: "Highest quality, but slower and larger.",
            isQuantized: false,
            recommended: false
        ),
        WhisperModel(
            name: "Medium (Q5 Quantized)",
            fileName: "ggml-medium-q5_0.bin",
            sizeInMB: 539,
            description: "Good quality, smaller size.",
            isQuantized: true,
            recommended: false
        ),
        WhisperModel(
            name: "Small (Q5 Quantized)",
            fileName: "ggml-small-q5_1.bin",
            sizeInMB: 190,
            description: "Fast and lightweight, lower accuracy.",
            isQuantized: true,
            recommended: false
        ),
        WhisperModel(
            name: "Base",
            fileName: "ggml-base.bin",
            sizeInMB: 148,
            description: "Very fast, basic accuracy.",
            isQuantized: false,
            recommended: false
        ),
        WhisperModel(
            name: "Tiny",
            fileName: "ggml-tiny.bin",
            sizeInMB: 78,
            description: "Fastest, lowest accuracy. For testing only.",
            isQuantized: false,
            recommended: false
        )
    ]

    // MARK: - Initialization

    private init() {
        // Set up models directory: ~/Library/Application Support/Blabber/Models/
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let blabberDir = appSupport.appendingPathComponent("Blabber")
        modelsDirectory = blabberDir.appendingPathComponent("Models")

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        os_log(.info, log: Self.logger, "Models directory: %{public}s", modelsDirectory.path)
    }

    // MARK: - Model Path Management

    /// Get the full path for a model file
    func modelPath(for model: WhisperModel) -> URL {
        return modelsDirectory.appendingPathComponent(model.fileName)
    }

    /// Get the full path for a model by filename
    func modelPath(for fileName: String) -> URL {
        return modelsDirectory.appendingPathComponent(fileName)
    }

    /// Get the current model path from settings, or return recommended model path
    func getCurrentModelPath() -> URL {
        let settingsPath = SettingsManager.shared.whisperModelPath

        // If settings path is the old default location, migrate to new location
        if settingsPath.contains("~/Models/") {
            // Try to find recommended model in new location
            if let recommended = availableModels.first(where: { $0.recommended }) {
                let newPath = modelPath(for: recommended)
                if FileManager.default.fileExists(atPath: newPath.path) {
                    return newPath
                }
            }
        }

        // Return the configured path
        return URL(fileURLWithPath: (settingsPath as NSString).expandingTildeInPath)
    }

    // MARK: - Model Status

    /// Check if a model is downloaded
    func isModelDownloaded(_ model: WhisperModel) -> Bool {
        let path = modelPath(for: model)
        return FileManager.default.fileExists(atPath: path.path)
    }

    /// Get list of installed models
    func getInstalledModels() -> [WhisperModel] {
        return availableModels.filter { isModelDownloaded($0) }
    }

    /// Check if any model is installed
    func hasAnyModelInstalled() -> Bool {
        return !getInstalledModels().isEmpty
    }

    /// Get the recommended model
    func getRecommendedModel() -> WhisperModel {
        return availableModels.first(where: { $0.recommended })!
    }

    /// Validate that a model file is complete (check file size)
    func validateModel(_ model: WhisperModel) -> Bool {
        let path = modelPath(for: model)

        guard FileManager.default.fileExists(atPath: path.path) else {
            return false
        }

        // Check file size (allow 5% variance for download overhead)
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
            if let fileSize = attributes[.size] as? Int64 {
                let expectedSize = Int64(model.sizeInMB) * 1024 * 1024
                let minSize = Int64(Double(expectedSize) * 0.95)
                let maxSize = Int64(Double(expectedSize) * 1.05)

                return fileSize >= minSize && fileSize <= maxSize
            }
        } catch {
            os_log(.error, log: Self.logger, "Error validating model: %{public}s", error.localizedDescription)
        }

        return false
    }

    // MARK: - Model Download

    /// Download a model with progress tracking
    func downloadModel(
        _ model: WhisperModel,
        progressHandler: @escaping (Double, Int64, Int64) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let destination = modelPath(for: model)

        os_log(.info, log: Self.logger, "Starting download of %{public}s from %{public}s", model.name, model.downloadURL.absoluteString)
        #if DEBUG
        print("ModelManager: Destination: \(destination.path)")
        #endif

        let session = URLSession(configuration: .default)
        let downloadTask = session.downloadTask(with: model.downloadURL) { tempURL, response, error in
            if let error = error {
                os_log(.error, log: Self.logger, "Download failed: %{public}s", error.localizedDescription)
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            guard let tempURL = tempURL else {
                let error = NSError(domain: "ModelManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No temporary file URL"])
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            do {
                // Remove existing file if present
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }

                // Move downloaded file to destination
                try FileManager.default.moveItem(at: tempURL, to: destination)

                os_log(.info, log: Self.logger, "Download complete: %{public}s", destination.path)

                DispatchQueue.main.async {
                    completion(.success(destination))
                }
            } catch {
                os_log(.error, log: Self.logger, "Error moving downloaded file: %{public}s", error.localizedDescription)
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }

        // Track download progress
        let observation = downloadTask.progress.observe(\.fractionCompleted) { progress, _ in
            let bytesDownloaded = progress.completedUnitCount
            let totalBytes = progress.totalUnitCount
            let percentage = progress.fractionCompleted

            DispatchQueue.main.async {
                progressHandler(percentage, bytesDownloaded, totalBytes)
            }
        }

        // Store observation to keep it alive
        objc_setAssociatedObject(downloadTask, "progressObservation", observation, .OBJC_ASSOCIATION_RETAIN)

        downloadTask.resume()
    }

    // MARK: - Model Deletion

    /// Delete a downloaded model
    func deleteModel(_ model: WhisperModel) -> Bool {
        let path = modelPath(for: model)

        guard FileManager.default.fileExists(atPath: path.path) else {
            return false
        }

        do {
            try FileManager.default.removeItem(at: path)
            os_log(.info, log: Self.logger, "Deleted model: %{public}s", model.fileName)
            return true
        } catch {
            os_log(.error, log: Self.logger, "Error deleting model: %{public}s", error.localizedDescription)
            return false
        }
    }

    // MARK: - Model Updates

    /// Check if an update is available for a model by comparing local and remote modification dates
    func checkForUpdate(_ model: WhisperModel, completion: @escaping (Bool) -> Void) {
        guard isModelDownloaded(model) else {
            completion(false)
            return
        }

        let localPath = modelPath(for: model)

        // Get local file modification date
        guard let localAttributes = try? FileManager.default.attributesOfItem(atPath: localPath.path),
              let localModDate = localAttributes[.modificationDate] as? Date else {
            completion(false)
            return
        }

        // Fetch remote Last-Modified header
        var request = URLRequest(url: model.downloadURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10

        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            guard error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  let lastModifiedString = httpResponse.value(forHTTPHeaderField: "Last-Modified"),
                  let remoteModDate = self.parseHTTPDate(lastModifiedString) else {
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }

            // Compare dates - if remote is newer, update is available
            let updateAvailable = remoteModDate > localModDate
            DispatchQueue.main.async {
                completion(updateAvailable)
            }
        }

        task.resume()
    }

    /// Parse HTTP date format (RFC 2822)
    private func parseHTTPDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(abbreviation: "GMT")
        return formatter.date(from: dateString)
    }

    // MARK: - Utility

    /// Get human-readable file size
    func getModelFileSize(_ model: WhisperModel) -> String? {
        let path = modelPath(for: model)

        guard FileManager.default.fileExists(atPath: path.path) else {
            return nil
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
            if let fileSize = attributes[.size] as? Int64 {
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                return formatter.string(fromByteCount: fileSize)
            }
        } catch {
            os_log(.error, log: Self.logger, "Error getting file size: %{public}s", error.localizedDescription)
        }

        return nil
    }

    /// Get total size of all downloaded models
    func getTotalModelsSize() -> Int64 {
        var totalSize: Int64 = 0

        for model in availableModels where isModelDownloaded(model) {
            let path = modelPath(for: model)
            if let attributes = try? FileManager.default.attributesOfItem(atPath: path.path),
               let fileSize = attributes[.size] as? Int64 {
                totalSize += fileSize
            }
        }

        return totalSize
    }
}
