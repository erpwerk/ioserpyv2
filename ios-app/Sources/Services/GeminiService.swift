import Foundation

class GeminiService: NSObject, LLMProvider, URLSessionDataDelegate {
    private var session: URLSession!
    private var onMessage: ((String) -> Void)?
    private var onComplete: (() -> Void)?
    private var buffer = ""
    
    // Track the latest signature to return in onComplete if needed
    private var lastSignature: String?
    
    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    func generateStream(prompt: String, model: String, apiKey: String, onMessage: @escaping (String) -> Void, onComplete: @escaping () -> Void) {
        self.onMessage = onMessage
        self.onComplete = onComplete
        self.buffer = ""
        self.lastSignature = nil
        
        // Handle image generation branching (Abzweigung)
        let lowerPrompt = prompt.lowercased()
        if lowerPrompt.contains("bild") && (lowerPrompt.contains("generier") || lowerPrompt.contains("erstell") || lowerPrompt.contains("mach")) {
            generateNanoImage(prompt: prompt, apiKey: apiKey)
            return
        }
        
        // Use gemini-3.1-pro-preview if 3.0 is requested (since it was closed March 9, 2026)
        let correctedModel = model.contains("gemini-3-pro") ? "gemini-3.1-pro-preview" : model
        
        // v1alpha required for media_resolution and advanced 2026 features
        let urlString = "https://generativelanguage.googleapis.com/v1alpha/models/\(correctedModel):streamGenerateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]]
            ],
            "tools": [
                ["googleSearch": [:]] // 2026 Grounding key
            ],
            "generationConfig": [
                "thinkingConfig": ["thinkingLevel": "high"],
                "mediaResolution": "media_resolution_high"
            ]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        let task = session.dataTask(with: request)
        task.resume()
    }
    
    private func generateNanoImage(prompt: String, apiKey: String) {
        // Nano Banana Pro is the 2026 high-end image model
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-pro-image-preview:generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": "Generate a stunning high-quality image: \(prompt)"]]]
            ],
            "config": [
                "imageConfig": ["imageSize": "4K", "aspectRatio": "16:9"]
            ]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let first = candidates.first,
                  let content = first["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let inlineData = parts.first?["inlineData"] as? [String: Any],
                  let mimeType = inlineData["mimeType"] as? String,
                  let base64Data = inlineData["data"] as? String else {
                
                DispatchQueue.main.async {
                    self?.onMessage?("⚠️ Bildgen (Nano Banana Pro) fehlgeschlagen.")
                    self?.onComplete?()
                }
                return
            }
            
            DispatchQueue.main.async {
                self.onMessage?("[IMAGE]data:\(mimeType);base64,\(base64Data)")
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
                buffer.removeSubrange(buffer.startIndex...endIdx)
                searchIndex = buffer.startIndex
            } else {
                break
            }
        }
    }
    
    private func process(json: Any) {
        if let array = json as? [[String: Any]] {
            for item in array { processCandidate(item) }
        } else if let dict = json as? [String: Any] {
            processCandidate(dict)
        }
    }
    
    private func processCandidate(_ item: [String: Any]) {
        guard let candidates = item["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            
            if let error = item["error"] as? [String: Any], let message = error["message"] as? String {
                DispatchQueue.main.async { self.onMessage?("⚠️ Gemini API Error: \(message)") }
            }
            return
        }
        
        for part in parts {
            if let text = part["text"] as? String {
                DispatchQueue.main.async { self.onMessage?(text) }
            }
            // Capture thoughtSignature for reasoning continuity
            if let sig = part["thoughtSignature"] as? String {
                self.lastSignature = sig
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.onMessage?("⚠️ Gemini Connection Error: \(error.localizedDescription)")
            }
        }
        
        // Final signature reporting can be added here if needed for state persistence
        DispatchQueue.main.async {
            self.onComplete?()
        }
    }
}
