import Foundation
import AVFoundation
import os.log

class CloudTranscriber {

    private static let logger = OSLog(subsystem: "com.blabber.app", category: "cloud-transcription")
    private let cloudManager = CloudModelManager.shared

    /// Transcribe audio file using a cloud provider
    func transcribe(audioFile: URL, modelId: String, completion: @escaping (String?) -> Void) {
        // Get the cloud model
        guard let cloudModel = cloudManager.availableModels.first(where: { $0.id == modelId }) else {
            os_log(.error, log: Self.logger, "Unknown model ID: %{public}s", modelId)
            completion(nil)
            return
        }

        // Get API key
        guard let apiKey = cloudManager.getAPIKey(for: cloudModel.id) else {
            os_log(.error, log: Self.logger, "No API key found for %{public}s", cloudModel.name)
            completion(nil)
            return
        }

        #if DEBUG
        print("CloudTranscriber: Starting transcription with \(cloudModel.name)")
        #endif

        // Route to appropriate provider
        switch cloudModel.provider {
        case "OpenAI":
            transcribeWithOpenAI(audioFile: audioFile, apiKey: apiKey, modelIdentifier: cloudModel.modelIdentifier, completion: completion)
        default:
            os_log(.error, log: Self.logger, "Unsupported provider: %{public}s", cloudModel.provider)
            completion(nil)
        }
    }

    // MARK: - OpenAI Whisper API

    private func transcribeWithOpenAI(audioFile: URL, apiKey: String, modelIdentifier: String, completion: @escaping (String?) -> Void) {
        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        // Create multipart form data
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Add model parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(modelIdentifier)\r\n".data(using: .utf8)!)

        // Add language parameter (if not auto-detect)
        let language = SettingsManager.shared.transcriptionLanguage
        if language != "auto" {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(language)\r\n".data(using: .utf8)!)
            #if DEBUG
            print("CloudTranscriber: Using language: \(language)")
            #endif
        } else {
            #if DEBUG
            print("CloudTranscriber: Using auto language detection")
            #endif
        }

        // Add file parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioFile.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)

        if let fileData = try? Data(contentsOf: audioFile) {
            body.append(fileData)
            body.append("\r\n".data(using: .utf8)!)
        } else {
            os_log(.error, log: Self.logger, "Failed to read audio file")
            completion(nil)
            return
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                os_log(.error, log: Self.logger, "OpenAI: Request failed: %{public}s", error.localizedDescription)
                completion(nil)
                return
            }

            guard let data = data else {
                os_log(.error, log: Self.logger, "OpenAI: No data received")
                completion(nil)
                return
            }

            // Parse JSON response
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let text = json["text"] as? String {
                    os_log(.info, log: Self.logger, "OpenAI: Transcription successful")
                    completion(text)
                } else {
                    os_log(.error, log: Self.logger, "OpenAI: Unexpected response format")
                    #if DEBUG
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("Response: \(responseString)")
                    }
                    #endif
                    completion(nil)
                }
            } catch {
                os_log(.error, log: Self.logger, "OpenAI: JSON parsing error: %{public}s", error.localizedDescription)
                completion(nil)
            }
        }

        task.resume()
    }
}
