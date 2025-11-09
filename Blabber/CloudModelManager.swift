import Foundation
import Security
import os.log

// Represents the type of cloud service
enum CloudServiceType {
    case transcription  // Speech-to-text
    case llm           // Large Language Model for text generation
}

// Represents a cloud-based AI provider
struct CloudModel {
    let id: String
    let name: String
    let provider: String
    let modelIdentifier: String // e.g., "whisper-1" for OpenAI, "gpt-4" for LLMs
    let description: String
    let comingSoon: Bool // True if not yet implemented
    let serviceType: CloudServiceType // Type of service this model provides

    var displayName: String {
        name
    }

    var dropdownDisplayName: String {
        "\(name) (Cloud)"
    }
}

class CloudModelManager {

    static let shared = CloudModelManager()

    private static let logger = OSLog(subsystem: "com.blabber.app", category: "cloud")

    // MARK: - Cache

    /// Cache to store which model IDs have configured API keys
    /// This prevents repeated keychain reads for UI operations
    private var configuredModelsCache: Set<String>?

    /// Lock for thread-safe cache access
    private let cacheLock = NSLock()

    // Available cloud models catalog
    let availableModels: [CloudModel] = [
        // TRANSCRIPTION MODELS
        CloudModel(
            id: "openai-whisper",
            name: "OpenAI Whisper",
            provider: "OpenAI",
            modelIdentifier: "whisper-1",
            description: "OpenAI's cloud-based Whisper API for speech recognition",
            comingSoon: false,
            serviceType: .transcription
        ),
        CloudModel(
            id: "elevenlabs",
            name: "ElevenLabs",
            provider: "ElevenLabs",
            modelIdentifier: "eleven-turbo-v2",
            description: "ElevenLabs speech-to-text API",
            comingSoon: true,
            serviceType: .transcription
        ),
        CloudModel(
            id: "custom",
            name: "Custom",
            provider: "Custom",
            modelIdentifier: "custom",
            description: "Point to your own cloud-hosted transcription endpoint",
            comingSoon: true,
            serviceType: .transcription
        ),

        // LLM MODELS FOR TEXT GENERATION
        CloudModel(
            id: "openai-gpt4",
            name: "GPT-4",
            provider: "OpenAI",
            modelIdentifier: "gpt-4",
            description: "OpenAI's most capable model for complex tasks",
            comingSoon: false,
            serviceType: .llm
        ),
        CloudModel(
            id: "openai-gpt4-turbo",
            name: "GPT-4 Turbo",
            provider: "OpenAI",
            modelIdentifier: "gpt-4-turbo",
            description: "Faster and more cost-effective GPT-4",
            comingSoon: false,
            serviceType: .llm
        ),
        CloudModel(
            id: "openai-gpt35-turbo",
            name: "GPT-3.5 Turbo",
            provider: "OpenAI",
            modelIdentifier: "gpt-3.5-turbo",
            description: "Fast and efficient model for everyday tasks",
            comingSoon: false,
            serviceType: .llm
        ),
        CloudModel(
            id: "anthropic-claude-opus",
            name: "Claude 3 Opus",
            provider: "Anthropic",
            modelIdentifier: "claude-3-opus-20240229",
            description: "Most capable Claude model for complex tasks",
            comingSoon: false,
            serviceType: .llm
        ),
        CloudModel(
            id: "anthropic-claude-sonnet",
            name: "Claude 3.5 Sonnet",
            provider: "Anthropic",
            modelIdentifier: "claude-3-5-sonnet-20241022",
            description: "Balanced intelligence and speed",
            comingSoon: false,
            serviceType: .llm
        ),
        CloudModel(
            id: "anthropic-claude-haiku",
            name: "Claude 3 Haiku",
            provider: "Anthropic",
            modelIdentifier: "claude-3-haiku-20240307",
            description: "Fastest Claude model for quick tasks",
            comingSoon: false,
            serviceType: .llm
        ),
        CloudModel(
            id: "google-gemini-pro",
            name: "Gemini Pro",
            provider: "Google",
            modelIdentifier: "gemini-pro",
            description: "Google's advanced AI model",
            comingSoon: false,
            serviceType: .llm
        ),
        CloudModel(
            id: "xai-grok",
            name: "Grok",
            provider: "xAI",
            modelIdentifier: "grok-beta",
            description: "xAI's conversational AI model",
            comingSoon: false,
            serviceType: .llm
        ),
        CloudModel(
            id: "ollama-llama2",
            name: "Llama 2 (Ollama)",
            provider: "Ollama",
            modelIdentifier: "llama2",
            description: "Meta's open source LLM via Ollama",
            comingSoon: false,
            serviceType: .llm
        ),
        CloudModel(
            id: "ollama-mistral",
            name: "Mistral (Ollama)",
            provider: "Ollama",
            modelIdentifier: "mistral",
            description: "Mistral AI's efficient model via Ollama",
            comingSoon: false,
            serviceType: .llm
        ),
        CloudModel(
            id: "ollama-codellama",
            name: "Code Llama (Ollama)",
            provider: "Ollama",
            modelIdentifier: "codellama",
            description: "Code-specialized LLM via Ollama",
            comingSoon: false,
            serviceType: .llm
        )
    ]

    // MARK: - Initialization

    private init() {
        os_log(.info, log: Self.logger, "CloudModelManager initialized")
    }

    // MARK: - Cache Management

    /// Load the cache by checking which models have API keys in keychain
    /// This performs one keychain read per model, but only once
    private func loadCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        // If cache is already loaded, don't reload
        if configuredModelsCache != nil {
            return
        }

        #if DEBUG
        print("CloudModelManager: Loading configuration cache...")
        #endif
        var configured = Set<String>()

        // Check each model's API key in keychain
        for model in availableModels {
            if getAPIKeyFromKeychain(for: model.id) != nil {
                configured.insert(model.id)
            }
        }

        configuredModelsCache = configured
        os_log(.info, log: Self.logger, "Cache loaded with %{public}d configured models", configured.count)
    }

    /// Invalidate the cache, forcing it to reload on next access
    private func invalidateCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        #if DEBUG
        print("CloudModelManager: Invalidating cache")
        #endif
        configuredModelsCache = nil
    }

    /// Get the cached set of configured model IDs
    private func getConfiguredModelIds() -> Set<String> {
        // Load cache if not already loaded
        if configuredModelsCache == nil {
            loadCache()
        }

        cacheLock.lock()
        defer { cacheLock.unlock() }

        return configuredModelsCache ?? Set()
    }

    // MARK: - API Key Management (Keychain)

    /// Save API key to Keychain
    func saveAPIKey(_ apiKey: String, for modelId: String) -> Bool {
        let service = "com.blabber.cloudmodels"
        let account = modelId

        guard let data = apiKey.data(using: .utf8) else { return false }

        // Delete existing key first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new key
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)

        // Invalidate cache so it will reload on next access
        if status == errSecSuccess {
            invalidateCache()
        }

        return status == errSecSuccess
    }

    /// Retrieve API key from Keychain directly (bypasses cache)
    private func getAPIKeyFromKeychain(for modelId: String) -> String? {
        let service = "com.blabber.cloudmodels"
        let account = modelId

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let apiKey = String(data: data, encoding: .utf8) else {
            return nil
        }

        return apiKey
    }

    /// Retrieve API key from Keychain (public API)
    /// This method always reads from keychain to get the actual key value
    func getAPIKey(for modelId: String) -> String? {
        return getAPIKeyFromKeychain(for: modelId)
    }

    /// Delete API key from Keychain
    func deleteAPIKey(for modelId: String) -> Bool {
        let service = "com.blabber.cloudmodels"
        let account = modelId

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        let success = status == errSecSuccess || status == errSecItemNotFound

        // Invalidate cache so it will reload on next access
        if success {
            invalidateCache()
        }

        return success
    }

    // MARK: - Model Status

    /// Check if a cloud model is configured (has API key)
    /// This uses the cache to avoid repeated keychain reads
    func isModelConfigured(_ model: CloudModel) -> Bool {
        let configuredIds = getConfiguredModelIds()
        return configuredIds.contains(model.id)
    }

    /// Get list of configured models
    func getConfiguredModels() -> [CloudModel] {
        return availableModels.filter { isModelConfigured($0) }
    }

    /// Check if any cloud model is configured
    func hasAnyModelConfigured() -> Bool {
        return !getConfiguredModels().isEmpty
    }

    // MARK: - Service Type Filtering

    /// Get models by service type
    func getModels(ofType type: CloudServiceType) -> [CloudModel] {
        return availableModels.filter { $0.serviceType == type && !$0.comingSoon }
    }

    /// Get transcription models
    func getTranscriptionModels() -> [CloudModel] {
        return getModels(ofType: .transcription)
    }

    /// Get LLM models for text generation
    func getLLMModels() -> [CloudModel] {
        return getModels(ofType: .llm)
    }

    /// Get configured LLM models
    func getConfiguredLLMModels() -> [CloudModel] {
        return getLLMModels().filter { isModelConfigured($0) }
    }

    /// Check if any LLM is configured
    func hasAnyLLMConfigured() -> Bool {
        return !getConfiguredLLMModels().isEmpty
    }

    /// Get configured transcription models only
    func getConfiguredTranscriptionModels() -> [CloudModel] {
        return getTranscriptionModels().filter { isModelConfigured($0) }
    }
}
