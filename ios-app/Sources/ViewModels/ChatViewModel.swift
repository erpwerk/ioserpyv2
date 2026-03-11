import Foundation
import Combine

class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var inputText: String = ""
    @Published var isStreaming: Bool = false
    @Published var selectedModel: String = "gpt-4o"
    
    let models = ["gpt-4o", "gemini-1.5-pro"]
    
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
        
        // In einer echten App würde hier URLSession SSE genutzt werden:
        // let url = URL(string: "https://your-backend.com/api/chat/stream?model=\(selectedModel)&prompt=\(prompt)")!
        
        // Simulation für Demo:
        let responsePrefix = selectedModel == "gpt-4o" ? "OpenAI GPT-4o: " : "Google Gemini 1.5 Pro: "
        let fullText = responsePrefix + "Ich habe deine Nachricht erhalten: '\(prompt)'. Als native App kann ich jetzt auch PDF-Analysen und Sprachsteuerung verarbeiten."
        
        let words = fullText.components(separatedBy: " ")
        var currentIndex = 0
        
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if currentIndex < words.count {
                assistantMessage.content += words[currentIndex] + " "
                if let index = self.messages.firstIndex(where: { $0.id == assistantMessage.id }) {
                    self.messages[index] = assistantMessage
                }
                currentIndex += 1
            } else {
                timer.invalidate()
                self.isStreaming = false
            }
        }
    }
    
    func startSpeechRecognition() {
        // Implementation für SFSpeechRecognizer
        print("Starte Spracherkennung...")
    }
}
