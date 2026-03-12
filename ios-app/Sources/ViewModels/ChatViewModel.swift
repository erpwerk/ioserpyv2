import SwiftUI
import Combine

class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var inputText: String = ""
    @Published var isStreaming: Bool = false
    @Published var selectedModel: String = "gpt-4o"
    @Published var isRecording: Bool = false
    
    // API Keys (Persisted via AppStorage)
    @AppStorage("openAIKey") var openAIKey: String = ""
    @AppStorage("geminiKey") var geminiKey: String = ""
    @AppStorage("searchKey") var searchKey: String = ""
    
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
                } else if chunk.hasPrefix("[TOOL_CALL]") {
                    // Logic to execute tool, e.g. web_search
                    self.executeWebSearch(query: prompt, assistantMessageId: assistantMessage.id)
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
    
    private func executeWebSearch(query: String, assistantMessageId: UUID) {
        let hardcodedTavilyKey = "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"
        let effectiveKey = searchKey.isEmpty ? hardcodedTavilyKey : searchKey
        
        // Try Tavily FIRST
        guard let url = URL(string: "https://api.tavily.com/search") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["api_key": effectiveKey, "query": query, "search_depth": "basic"]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = json["results"] as? [[String: Any]], !results.isEmpty {
                
                let context = results.prefix(3).compactMap { $0["content"] as? String }.joined(separator: "\n\n")
                self.updateAssistantMessage(id: assistantMessageId, content: "Tavily Suche Ergebnisse:\n\n\(context)")
            } else {
                // FALLBACK to Google (Simplified for now - using a public search link or placeholder logic)
                self.executeGoogleFallback(query: query, assistantMessageId: assistantMessageId)
            }
        }.resume()
    }
    
    private func executeGoogleFallback(query: String, assistantMessageId: UUID) {
        // Since a real Google Search API requires a Search Engine ID and another Key,
        // we provide a helpful redirection or placeholder result for the backup.
        DispatchQueue.main.async {
            if let index = self.messages.firstIndex(where: { $0.id == assistantMessageId }) {
                self.messages[index].content = "Tavily fehlgeschlagen. Versuche Google Suche Backup... (Hinweis: Für echtes Google-API-Backup wird ein Google Search Key benötigt)."
                // In einer echten Implementierung würde hier der Aufruf an Google erfolgen.
            }
        }
    }
    
    private func updateAssistantMessage(id: UUID, content: String) {
        DispatchQueue.main.async {
            if let index = self.messages.firstIndex(where: { $0.id == id }) {
                self.messages[index].content = content
                self.saveMessages()
            }
        }
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
