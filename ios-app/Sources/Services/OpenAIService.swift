import Foundation

class OpenAIService: NSObject, LLMProvider, URLSessionDataDelegate {
    private var session: URLSession!
    private var onMessage: ((String) -> Void)?
    private var onComplete: (() -> Void)?
    private var apiKey: String = ""
    private var buffer = ""
    
    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    func generateStream(prompt: String, model: String, apiKey: String, onMessage: @escaping (String) -> Void, onComplete: @escaping () -> Void) {
        self.onMessage = onMessage
        self.onComplete = onComplete
        self.apiKey = apiKey
        self.buffer = ""
        
        // Handle image generation branching (Abzweigung)
        let lowerPrompt = prompt.lowercased()
        if lowerPrompt.contains("bild") && (lowerPrompt.contains("generier") || lowerPrompt.contains("erstell") || lowerPrompt.contains("mach")) {
            generateImage(prompt: prompt, apiKey: apiKey)
            return
        }
        
        // 2026 Responses API
        guard let url = URL(string: "https://api.openai.com/v1/responses") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Use exact 2026 model IDs
        let apiModel = (model == "gpt-5.4" || model == "gpt-5-main") ? "gpt-5.4" : (model == "gpt-5-mini" ? "gpt-5-mini" : "gpt-4o")
        
        let body: [String: Any] = [
            "model": apiModel,
            "input": prompt,
            "tools": [
                ["type": "web_search"]
            ],
            "stream": true
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        let task = session.dataTask(with: request)
        task.resume()
    }
    
    private func generateImage(prompt: String, apiKey: String) {
        guard let url = URL(string: "https://api.openai.com/v1/images/generations") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": "gpt-image-1",
            "prompt": prompt,
            "n": 1,
            "size": "1024x1024"
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataArray = json["data"] as? [[String: Any]],
                  let imageUrl = dataArray.first?["url"] as? String else {
                DispatchQueue.main.async {
                    self?.onMessage?("⚠️ Bildgenerierung (GPT-Image-1) fehlgeschlagen.")
                    self?.onComplete?()
                }
                return
            }
            
            DispatchQueue.main.async {
                self.onMessage?("[IMAGE]\(imageUrl)")
                self.onComplete?()
            }
        }.resume()
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let responseString = String(data: data, encoding: .utf8) else { return }
        buffer += responseString
        parseBuffer()
    }
    
    private func parseBuffer() {
        var searchIndex = buffer.startIndex
        
        while let openBrace = buffer[searchIndex...].firstIndex(where: { $0 == "{" || $0 == "[" }) {
            let startChar = buffer[openBrace]
            let endChar: Character = (startChar == "{") ? "}" : "]"
            
            var balance = 0
            var found = false
            var endIdx = openBrace
            
            for (i, char) in buffer[openBrace...].enumerated() {
                if char == startChar { balance += 1 }
                else if char == endChar { balance -= 1 }
                
                if balance == 0 {
                    endIdx = buffer.index(openBrace, offsetBy: i)
                    found = true
                    break
                }
            }
            
            if found {
                let jsonString = String(buffer[openBrace...endIdx])
                if let data = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) {
                    process(json: json)
                }
                
                // Clear buffer up to the end of this object
                buffer.removeSubrange(buffer.startIndex...endIdx)
                searchIndex = buffer.startIndex
            } else {
                // Incomplete JSON, wait for more data
                break
            }
        }
    }
    
    private func process(json: Any) {
        if let array = json as? [[String: Any]] {
            for item in array { processMessage(item) }
        } else if let dict = json as? [String: Any] {
            processMessage(dict)
        }
    }
    
    private func processMessage(_ item: [String: Any]) {
        // Handle output_text (Modern Responses API)
        if let outputText = item["output_text"] as? String {
            DispatchQueue.main.async { self.onMessage?(outputText) }
        } 
        // Handle content array (Alternative Modern format)
        else if let contentArray = item["content"] as? [[String: Any]] {
            for content in contentArray {
                if let text = content["text"] as? String {
                    DispatchQueue.main.async { self.onMessage?(text) }
                } else if let text = content["output_text"] as? String {
                     DispatchQueue.main.async { self.onMessage?(text) }
                }
            }
        }
        // Handle legacy delta (Standard SSE)
        else if let choices = item["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let delta = first["delta"] as? [String: Any],
                  let content = delta["content"] as? String {
            DispatchQueue.main.async { self.onMessage?(content) }
        }
        // Handle error
        else if let error = item["error"] as? [String: Any], let message = error["message"] as? String {
            DispatchQueue.main.async { self.onMessage?("⚠️ OpenAI Error: \(message)") }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.onMessage?("⚠️ OpenAI Connection Error: \(error.localizedDescription)")
            }
        }
        DispatchQueue.main.async {
            self.onComplete?()
        }
    }
}
