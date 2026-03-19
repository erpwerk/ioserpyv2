import SwiftUI
import Combine

class ChatViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var currentConversationId: UUID?
    @Published var inputText: String = ""
    @Published var isStreaming: Bool = false
    @Published var selectedModel: String = "gpt-4.1-mini"
    @Published var isRecording: Bool = false
    
    // API Keys (Persisted via AppStorage)
    @AppStorage("openAIKey") var openAIKey: String = ""
    @AppStorage("geminiKey") var geminiKey: String = ""
    
    private var openAIService = OpenAIService()
    private var geminiService = GeminiService()
    private var speechManager = SpeechManager()
    private var cancellables = Set<AnyCancellable>()
    
    let models = ["gpt-4.1-mini", "gemini-2.5-flash", "gemini-1.5-flash"]
    
    var isOpenAIKeyValid: Bool { !openAIKey.isEmpty }
    var isGeminiKeyValid: Bool { !geminiKey.isEmpty }
    
    var messages: [Message] {
        conversations.first(where: { $0.id == currentConversationId })?.messages ?? []
    }
    
    init() {
        loadConversations()
        
        // Sync isRecording with SpeechManager
        speechManager.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recording in
                self?.isRecording = recording
            }
            .store(in: &cancellables)
    }
    
    func createNewChat() {
        let newChat = Conversation()
        conversations.insert(newChat, at: 0)
        currentConversationId = newChat.id
        saveConversations()
    }
    
    func selectConversation(_ id: UUID) {
        currentConversationId = id
    }
    
    func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        if currentConversationId == nil {
            createNewChat()
        }
        
        let userMessage = Message(role: "user", content: inputText)
        addMessage(userMessage)
        
        // Update title if it's the first message
        if messages.count == 1 {
            updateTitle(inputText)
        }
        
        let prompt = inputText
        inputText = ""
        
        saveConversations()
        startStreaming(prompt: prompt)
    }
    
    private func addMessage(_ message: Message) {
        if let index = conversations.firstIndex(where: { $0.id == currentConversationId }) {
            conversations[index].messages.append(message)
            conversations[index].lastUpdatedAt = Date()
        }
    }
    
    private func updateTitle(_ text: String) {
        if let index = conversations.firstIndex(where: { $0.id == currentConversationId }) {
            let title = String(text.prefix(25)) + (text.count > 25 ? "..." : "")
            conversations[index].title = title
        }
    }
    
    private func startStreaming(prompt: String) {
        guard currentConversationId != nil else { return }
        isStreaming = true
        
        let assistantMessage = Message(role: "assistant", content: "")
        addMessage(assistantMessage)
        
        let provider: LLMProvider
        let apiKey: String
        let model: String
        
        if selectedModel.contains("gpt") {
            provider = openAIService
            apiKey = openAIKey
            model = selectedModel
        } else {
            provider = geminiService
            apiKey = geminiKey
            model = selectedModel
        }
        
        if apiKey.isEmpty {
            updateAssistantMessage(id: assistantMessage.id, content: "⚠️ Bitte gib zuerst einen API-Key in den Einstellungen ein.")
            isStreaming = false
            return
        }
        
        provider.generateStream(prompt: prompt, model: model, apiKey: apiKey, onMessage: { [weak self] chunk in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if chunk.hasPrefix("[IMAGE]") {
                    let url = chunk.replacingOccurrences(of: "[IMAGE]", with: "")
                    self.updateAssistantImage(id: assistantMessage.id, url: url)
                } else {
                    self.appendAssistantContent(id: assistantMessage.id, chunk: chunk)
                }
            }
        }, onComplete: { [weak self] in
            DispatchQueue.main.async {
                self?.isStreaming = false
                self?.saveConversations()
            }
        })
    }
    
    private func updateAssistantMessage(id: UUID, content: String) {
        if let convIndex = conversations.firstIndex(where: { $0.id == currentConversationId }),
           let msgIndex = conversations[convIndex].messages.firstIndex(where: { $0.id == id }) {
            conversations[convIndex].messages[msgIndex].content = content
        }
    }
    
    private func appendAssistantContent(id: UUID, chunk: String) {
        if let convIndex = conversations.firstIndex(where: { $0.id == currentConversationId }),
           let msgIndex = conversations[convIndex].messages.firstIndex(where: { $0.id == id }) {
            conversations[convIndex].messages[msgIndex].content += chunk
            self.objectWillChange.send()
        }
    }
    
    private func updateAssistantImage(id: UUID, url: String) {
        if let convIndex = conversations.firstIndex(where: { $0.id == currentConversationId }),
           let msgIndex = conversations[convIndex].messages.firstIndex(where: { $0.id == id }) {
            conversations[convIndex].messages[msgIndex].imageUrl = url
        }
    }
    
    // PERSISTENCE
    private var historyURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("conversations.json")
    }
    
    func saveConversations() {
        do {
            let data = try JSONEncoder().encode(conversations)
            try data.write(to: historyURL)
        } catch {
            print("Failed to save conversations: \(error)")
        }
    }
    
    func loadConversations() {
        if FileManager.default.fileExists(atPath: historyURL.path) {
            do {
                let data = try Data(contentsOf: historyURL)
                let decoded = try JSONDecoder().decode([Conversation].self, from: data)
                self.conversations = decoded
                self.currentConversationId = conversations.first?.id
            } catch {
                print("Failed to load conversations: \(error)")
                createNewChat()
            }
        } else {
            createNewChat()
        }
    }
    
    func clearHistory() {
        conversations = []
        createNewChat()
        saveConversations()
    }
    
    func toggleRecording() {
        if isRecording {
            speechManager.stopRecording()
            if !inputText.isEmpty {
                sendMessage()
            }
        } else {
            speechManager.startRecording { [weak self] transcript in
                DispatchQueue.main.async {
                    self?.inputText = transcript
                }
            }
        }
    }
}
