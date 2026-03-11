import Foundation
import Combine

class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var inputText: String = ""
    @Published var isStreaming: Bool = false
    @Published var selectedModel: String = "gpt-4o"
    @Published var isRecording: Bool = false
    
    // API Keys (In a real app, these should be in the Keychain)
    @Published var openAIKey: String = ""
    @Published var geminiKey: String = ""
    
    private var openAIService = OpenAIService()
    private var geminiService = GeminiService()
    private var speechManager = SpeechManager()
    
    let models = ["gpt-4o", "gemini-1.5-flash"]
    
    func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        let userMessage = Message(role: "user", content: inputText)
        messages.append(userMessage)
        let prompt = inputText
        inputText = ""
        
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
            if let index = self.messages.firstIndex(where: { $0.id == assistantMessage.id }) {
                self.messages[index].content += chunk
            }
        }, onComplete: { [weak self] in
            self?.isStreaming = false
        })
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
