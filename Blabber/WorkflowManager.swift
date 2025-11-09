import Foundation
import os.log

class WorkflowManager {
    static let shared = WorkflowManager()

    private static let logger = OSLog(subsystem: "com.blabber.app", category: "workflows")

    private var workflows: [Workflow] = []
    private let workflowsFileURL: URL
    private let templatesInitializedKey = "WorkflowManager.templatesInitialized"

    private init() {
        // Get app support directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let blabberDir = appSupport.appendingPathComponent("Blabber", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: blabberDir, withIntermediateDirectories: true)

        workflowsFileURL = blabberDir.appendingPathComponent("workflows.json")

        // Load existing workflows
        loadWorkflows()

        // Initialize default templates on first run
        initializeDefaultTemplatesIfNeeded()
    }

    // MARK: - Public Methods

    /// Get all workflows, sorted by custom order
    func getWorkflows() -> [Workflow] {
        return workflows.sorted { $0.order < $1.order }
    }

    /// Get only enabled workflows, sorted by custom order
    func getEnabledWorkflows() -> [Workflow] {
        return workflows.filter { $0.isEnabled }.sorted { $0.order < $1.order }
    }

    /// Add a new workflow
    func addWorkflow(_ workflow: Workflow) {
        // Assign order as the highest current order + 1
        let maxOrder = workflows.map { $0.order }.max() ?? -1
        workflow.order = maxOrder + 1
        workflows.append(workflow)
        saveWorkflows()
    }

    /// Update an existing workflow
    func updateWorkflow(_ workflow: Workflow) {
        if let index = workflows.firstIndex(where: { $0.id == workflow.id }) {
            workflows[index] = workflow
            saveWorkflows()
        }
    }

    /// Delete a workflow
    func deleteWorkflow(id: UUID) {
        workflows.removeAll { $0.id == id }
        saveWorkflows()
    }

    /// Reorder workflows (used for drag-and-drop)
    func reorderWorkflows(from sourceIndex: Int, to destinationIndex: Int) {
        let sortedWorkflows = getWorkflows()
        guard sourceIndex >= 0 && sourceIndex < sortedWorkflows.count &&
              destinationIndex >= 0 && destinationIndex < sortedWorkflows.count else {
            return
        }

        // Get the workflow being moved
        let movedWorkflow = sortedWorkflows[sourceIndex]

        // Create new array with reordered items
        var reordered = sortedWorkflows
        reordered.remove(at: sourceIndex)
        reordered.insert(movedWorkflow, at: destinationIndex)

        // Update order values
        for (index, workflow) in reordered.enumerated() {
            workflow.order = index
        }

        saveWorkflows()
    }

    /// Toggle enabled status of a workflow
    func toggleEnabled(id: UUID) {
        if let index = workflows.firstIndex(where: { $0.id == id }) {
            workflows[index].isEnabled.toggle()
            saveWorkflows()
        }
    }

    /// Get workflow by ID
    func getWorkflow(id: UUID) -> Workflow? {
        return workflows.first { $0.id == id }
    }

    /// Check if any workflows exist
    func hasWorkflows() -> Bool {
        return !workflows.isEmpty
    }

    // MARK: - Private Methods

    private func saveWorkflows() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(workflows)
            try data.write(to: workflowsFileURL)
            os_log(.info, log: Self.logger, "Saved %{public}d workflows to disk", workflows.count)
        } catch {
            os_log(.error, log: Self.logger, "Failed to save workflows: %{public}s", error.localizedDescription)
        }
    }

    private func loadWorkflows() {
        do {
            let data = try Data(contentsOf: workflowsFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            workflows = try decoder.decode([Workflow].self, from: data)

            // Ensure all workflows have an order assigned (for backwards compatibility)
            var needsSave = false
            for (index, workflow) in workflows.enumerated() {
                if workflow.order == 0 && workflows.filter({ $0.order == 0 }).count > 1 {
                    // Multiple workflows with order 0 means they need to be assigned orders
                    workflow.order = index
                    needsSave = true
                }
            }

            if needsSave {
                saveWorkflows()
            }

            os_log(.info, log: Self.logger, "Loaded %{public}d workflows from disk", workflows.count)
        } catch {
            #if DEBUG
            print("WorkflowManager: No existing workflows or failed to load: \(error)")
            #endif
            workflows = []
        }
    }

    // MARK: - Default Templates

    private func initializeDefaultTemplatesIfNeeded() {
        // Check if templates have already been initialized
        let initialized = UserDefaults.standard.bool(forKey: templatesInitializedKey)
        if initialized {
            return
        }

        // Only initialize if no workflows exist yet
        guard workflows.isEmpty else {
            UserDefaults.standard.set(true, forKey: templatesInitializedKey)
            return
        }

        os_log(.info, log: Self.logger, "Initializing default workflow templates")

        // Create default templates
        let defaultTemplates = createDefaultTemplates()
        workflows.append(contentsOf: defaultTemplates)

        // Save and mark as initialized
        saveWorkflows()
        UserDefaults.standard.set(true, forKey: templatesInitializedKey)
    }

    private func createDefaultTemplates() -> [Workflow] {
        var templates: [Workflow] = []

        // 1. Formal Email Formatter
        templates.append(Workflow(
            name: "Formal Email",
            description: "Professional email format",
            prompt: """
Review and format the following text into a professional email.

Requirements:
- Use proper email structure (greeting, body, closing)
- Add bullet points where multiple items are listed
- Maintain a semi-formal, professional tone
- Never use emojis or overly casual language
- Fix grammar and spelling errors

Text to format:
""",
            serviceId: nil,
            isEnabled: true,
            order: 0
        ))

        // 2. Language Translator (Afrikaans)
        templates.append(Workflow(
            name: "Translate to Afrikaans",
            description: "Translate text to Afrikaans",
            prompt: """
Translate the following text into Afrikaans. Maintain the tone and intent of the original message. Provide only the translation without explanations.

Text to translate:
""",
            serviceId: nil,
            isEnabled: true,
            order: 1
        ))

        // 3. Text Message Formatter
        templates.append(Workflow(
            name: "Text Message",
            description: "Casual, friendly format",
            prompt: """
Rewrite the following text as a friendly, casual text message.

Requirements:
- Keep it concise and conversational
- Use natural, friendly language
- Remove overly formal phrasing
- Fix obvious errors but maintain casual tone

Text to format:
""",
            serviceId: nil,
            isEnabled: true,
            order: 2
        ))

        // 4. Meeting Notes Organizer
        templates.append(Workflow(
            name: "Meeting Notes",
            description: "Structured summary with actions",
            prompt: """
Organize the following meeting transcription into structured notes.

Format as:
- **Summary**: Brief overview (2-3 sentences)
- **Key Discussion Points**: Bullet list of main topics
- **Action Items**: List of tasks with responsible parties if mentioned
- **Decisions Made**: Important conclusions or agreements

Transcription:
""",
            serviceId: nil,
            isEnabled: true,
            order: 3
        ))

        // 5. Grammar & Spelling Corrector
        templates.append(Workflow(
            name: "Fix Grammar",
            description: "Correct errors, preserve tone",
            prompt: """
Correct all grammar, spelling, and punctuation errors in the following text. Preserve the original tone, style, and structure. Only fix errors, do not rephrase or add content.

Text to correct:
""",
            serviceId: nil,
            isEnabled: true,
            order: 4
        ))

        return templates
    }
}
