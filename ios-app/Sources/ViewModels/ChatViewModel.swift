import SwiftUI
import Combine

class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var inputText: String = ""
    @Published var isStreaming: Bool = false
    @Published var selectedModel: String = "gpt-4o-latest"
    @Published var isRecording: Bool = false
    
    // API Keys (Persisted via AppStorage)
    @AppStorage("openAIKey") var openAIKey: String = ""
    @AppStorage("geminiKey") var geminiKey: String = ""
    
    private var openAIService = OpenAIService()
    private var geminiService = GeminiService()
    private var speechManager = SpeechManager()
    
    let models = ["gpt-4o-latest", "gemini-1.5-flash-latest", "gemini-1.5-pro-latest"]
    
    init() {
        loadMessages()
    }
    
    func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        let userMessage = Message(role: "user", content: inputText)
        messages.append(userMessage)
        let prompt = inputText
        inputText = ""
        
        saveMessages()
        startStreaming(prompt: prompt)
    }
    
    private func startStreaming(prompt: String) {
        isStreaming = true
        var assistantMessage = Message(role: "assistant", content: "")
        messages.append(assistantMessage)
        
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
            assistantMessage.content = "⚠️ Bitte gib zuerst einen API-Key in den Einstellungen ein."
            if let index = self.messages.firstIndex(where: { $0.id == assistantMessage.id }) {
                self.messages[index] = assistantMessage
            }
            isStreaming = false
            return
        }
        
        provider.generateStream(prompt: prompt, model: model, apiKey: apiKey, onMessage: { [weak self] chunk in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if chunk.hasPrefix("[IMAGE]") {
                    let url = chunk.replacingOccurrences(of: "[IMAGE]", with: "")
                    if let index = self.messages.firstIndex(where: { $0.id == assistantMessage.id }) {
                        self.messages[index].imageUrl = url
                    }
                } else {
                    if let index = self.messages.firstIndex(where: { $0.id == assistantMessage.id }) {
                        self.messages[index].content += chunk
                        self.objectWillChange.send()
                    }
                }
            }
        }, onComplete: { [weak self] in
            DispatchQueue.main.async {
                self?.isStreaming = false
                self?.saveMessages()
            }
        })
    }
    
    // PERSISTENCE
    private var historyURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("history.json")
    }
    
    func saveMessages() {
        do {
            let data = try JSONEncoder().encode(messages)
            try data.write(to: historyURL)
        } catch {
            print("Failed to save messages: \(error)")
        }
    }
    
    func loadMessages() {
        if FileManager.default.fileExists(atPath: historyURL.path) {
            do {
                let data = try Data(contentsOf: historyURL)
                let decoded = try JSONDecoder().decode([Message].self, from: data)
                self.messages = decoded
            } catch {
                print("Failed to load history: \(error)")
            }
        }
    }
    
    func clearHistory() {
        messages = []
        saveMessages()
    }
    
    func toggleRecording() {
        if isRecording {
            speechManager.stopRecording()
            isRecording = false
            if !inputText.isEmpty {
                sendMessage()
            }
        } else {
            isRecording = true
            speechManager.startRecording { [weak self] transcript in
                DispatchQueue.main.async {
                    self?.inputText = transcript
                }
            }
        }
    }
}
