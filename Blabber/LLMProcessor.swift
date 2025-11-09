import Foundation
import os.log

class LLMProcessor {

    private static let logger = OSLog(subsystem: "com.blabber.app", category: "workflows")

    private let cloudManager = CloudModelManager.shared

    /// Process text using an LLM provider
    /// - Parameters:
    ///   - text: The input text to process
    ///   - prompt: The system/instruction prompt
    ///   - modelId: The ID of the LLM model to use
    ///   - completion: Callback with result (success: generated text, failure: nil)
    func processText(text: String, prompt: String, modelId: String, completion: @escaping (String?, Error?) -> Void) {
        // Get the cloud model
        guard let cloudModel = cloudManager.availableModels.first(where: { $0.id == modelId }) else {
            os_log(.error, log: Self.logger, "Unknown model ID: %{public}s", modelId)
            let error = NSError(domain: "LLMProcessor", code: 404, userInfo: [NSLocalizedDescriptionKey: "Unknown model"])
            completion(nil, error)
            return
        }

        // Verify it's an LLM model
        guard cloudModel.serviceType == .llm else {
            os_log(.error, log: Self.logger, "Model %{public}s is not an LLM", modelId)
            let error = NSError(domain: "LLMProcessor", code: 400, userInfo: [NSLocalizedDescriptionKey: "Model is not an LLM"])
            completion(nil, error)
            return
        }

        // Get API key (not required for Ollama)
        let apiKey = cloudManager.getAPIKey(for: cloudModel.id)
        if cloudModel.provider != "Ollama" && apiKey == nil {
            os_log(.error, log: Self.logger, "No API key found for %{public}s", cloudModel.name)
            let error = NSError(domain: "LLMProcessor", code: 401, userInfo: [NSLocalizedDescriptionKey: "No API key configured"])
            completion(nil, error)
            return
        }

        os_log(.info, log: Self.logger, "Processing text with %{public}s", cloudModel.name)

        // Combine prompt and user text
        let userMessage = "\(prompt)\n\n\(text)"

        // Route to appropriate provider
        switch cloudModel.provider {
        case "OpenAI":
            processWithOpenAI(userMessage: userMessage, apiKey: apiKey!, modelIdentifier: cloudModel.modelIdentifier, completion: completion)
        case "Anthropic":
            processWithAnthropic(systemPrompt: prompt, userMessage: text, apiKey: apiKey!, modelIdentifier: cloudModel.modelIdentifier, completion: completion)
        case "Google":
            processWithGemini(userMessage: userMessage, apiKey: apiKey!, modelIdentifier: cloudModel.modelIdentifier, completion: completion)
        case "xAI":
            processWithGrok(userMessage: userMessage, apiKey: apiKey!, modelIdentifier: cloudModel.modelIdentifier, completion: completion)
        case "Ollama":
            processWithOllama(userMessage: userMessage, modelIdentifier: cloudModel.modelIdentifier, completion: completion)
        default:
            os_log(.error, log: Self.logger, "Unsupported provider: %{public}s", cloudModel.provider)
            let error = NSError(domain: "LLMProcessor", code: 501, userInfo: [NSLocalizedDescriptionKey: "Provider not supported"])
            completion(nil, error)
        }
    }

    // MARK: - OpenAI Chat Completions API

    private func processWithOpenAI(userMessage: String, apiKey: String, modelIdentifier: String, completion: @escaping (String?, Error?) -> Void) {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": modelIdentifier,
            "messages": [
                ["role": "user", "content": userMessage]
            ],
            "temperature": 0.7
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        executeRequest(request, provider: "OpenAI") { data, error in
            guard let data = data, error == nil else {
                completion(nil, error)
                return
            }

            // Parse OpenAI response
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    completion(content, nil)
                } else {
                    let error = NSError(domain: "LLMProcessor", code: 500, userInfo: [NSLocalizedDescriptionKey: "Unexpected response format"])
                    completion(nil, error)
                }
            } catch {
                completion(nil, error)
            }
        }
    }

    // MARK: - Anthropic Messages API

    private func processWithAnthropic(systemPrompt: String, userMessage: String, apiKey: String, modelIdentifier: String, completion: @escaping (String?, Error?) -> Void) {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": modelIdentifier,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userMessage]
            ]
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        executeRequest(request, provider: "Anthropic") { data, error in
            guard let data = data, error == nil else {
                completion(nil, error)
                return
            }

            // Parse Anthropic response
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let content = json["content"] as? [[String: Any]],
                   let firstContent = content.first,
                   let text = firstContent["text"] as? String {
                    completion(text, nil)
                } else {
                    let error = NSError(domain: "LLMProcessor", code: 500, userInfo: [NSLocalizedDescriptionKey: "Unexpected response format"])
                    completion(nil, error)
                }
            } catch {
                completion(nil, error)
            }
        }
    }

    // MARK: - Google Gemini API

    private func processWithGemini(userMessage: String, apiKey: String, modelIdentifier: String, completion: @escaping (String?, Error?) -> Void) {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(modelIdentifier):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            let error = NSError(domain: "LLMProcessor", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            completion(nil, error)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": userMessage]
                    ]
                ]
            ]
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        executeRequest(request, provider: "Gemini") { data, error in
            guard let data = data, error == nil else {
                completion(nil, error)
                return
            }

            // Parse Gemini response
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let candidates = json["candidates"] as? [[String: Any]],
                   let firstCandidate = candidates.first,
                   let content = firstCandidate["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let firstPart = parts.first,
                   let text = firstPart["text"] as? String {
                    completion(text, nil)
                } else {
                    let error = NSError(domain: "LLMProcessor", code: 500, userInfo: [NSLocalizedDescriptionKey: "Unexpected response format"])
                    completion(nil, error)
                }
            } catch {
                completion(nil, error)
            }
        }
    }

    // MARK: - xAI Grok API (OpenAI-compatible)

    private func processWithGrok(userMessage: String, apiKey: String, modelIdentifier: String, completion: @escaping (String?, Error?) -> Void) {
        let url = URL(string: "https://api.x.ai/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": modelIdentifier,
            "messages": [
                ["role": "user", "content": userMessage]
            ],
            "temperature": 0.7
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        executeRequest(request, provider: "Grok") { data, error in
            guard let data = data, error == nil else {
                completion(nil, error)
                return
            }

            // Parse response (same format as OpenAI)
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    completion(content, nil)
                } else {
                    let error = NSError(domain: "LLMProcessor", code: 500, userInfo: [NSLocalizedDescriptionKey: "Unexpected response format"])
                    completion(nil, error)
                }
            } catch {
                completion(nil, error)
            }
        }
    }

    // MARK: - Ollama API (OpenAI-compatible, local)

    private func processWithOllama(userMessage: String, modelIdentifier: String, completion: @escaping (String?, Error?) -> Void) {
        let url = URL(string: "http://localhost:11434/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": modelIdentifier,
            "messages": [
                ["role": "user", "content": userMessage]
            ],
            "temperature": 0.7
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        executeRequest(request, provider: "Ollama") { data, error in
            guard let data = data, error == nil else {
                completion(nil, error)
                return
            }

            // Parse response (same format as OpenAI)
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    completion(content, nil)
                } else {
                    let error = NSError(domain: "LLMProcessor", code: 500, userInfo: [NSLocalizedDescriptionKey: "Unexpected response format"])
                    completion(nil, error)
                }
            } catch {
                completion(nil, error)
            }
        }
    }

    // MARK: - Helper Methods

    private func executeRequest(_ request: URLRequest, provider: String, completion: @escaping (Data?, Error?) -> Void) {
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                os_log(.error, log: Self.logger, "%{public}s request failed: %{public}s", provider, error.localizedDescription)
                completion(nil, error)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                let error = NSError(domain: "LLMProcessor", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                completion(nil, error)
                return
            }

            guard let data = data else {
                let error = NSError(domain: "LLMProcessor", code: 500, userInfo: [NSLocalizedDescriptionKey: "No data received"])
                completion(nil, error)
                return
            }

            // Check for HTTP errors
            if httpResponse.statusCode != 200 {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                os_log(.error, log: Self.logger, "%{public}s HTTP %{public}d: %{public}s", provider, httpResponse.statusCode, errorMessage)
                let error = NSError(domain: "LLMProcessor", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
                completion(nil, error)
                return
            }

            os_log(.info, log: Self.logger, "%{public}s request successful", provider)
            completion(data, nil)
        }

        task.resume()
    }
}
