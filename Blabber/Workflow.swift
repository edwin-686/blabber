import Foundation
import Cocoa

class Workflow: Codable {
    var id: UUID
    var name: String
    var description: String
    var prompt: String
    var serviceId: String? // References a CloudModel/LLM service ID
    var isEnabled: Bool
    var order: Int // Display order (lower numbers appear first)

    init(name: String, description: String, prompt: String, serviceId: String? = nil, isEnabled: Bool = true, order: Int = 0) {
        self.id = UUID()
        self.name = name
        self.description = description
        self.prompt = prompt
        self.serviceId = serviceId
        self.isEnabled = isEnabled
        self.order = order
    }

    /// Returns a display name for the workflow button (name + description)
    var buttonDisplayText: String {
        if description.isEmpty {
            return name
        }
        return "\(name)\n\(description)"
    }

    /// Returns truncated description for table view (max 50 characters)
    var truncatedDescription: String {
        if description.count <= 50 {
            return description
        }
        return String(description.prefix(50)) + "..."
    }

    /// Returns service display name or "Not configured" if no service
    func serviceDisplayName(manager: CloudModelManager) -> String {
        guard let serviceId = serviceId else {
            return "Not configured"
        }

        if let model = manager.availableModels.first(where: { $0.id == serviceId }) {
            return "\(model.provider) - \(model.name)"
        }

        return "Unknown service"
    }
}
