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
        if lowerPrompt.contains("bild") || lowerPrompt.contains("generier") || lowerPrompt.contains("erstell") || lowerPrompt.contains("photo") {
            generateGeminiImage(prompt: prompt, model: model, apiKey: apiKey)
            return
        }
        
        // Use user selected model or stable 2.5 Flash
        let correctedModel = model.contains("gemini") ? model : "gemini-2.5-flash"
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(correctedModel):streamGenerateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]]
            ],
            "tools": [
                ["googleSearch": [:]]
            ],
            "generationConfig": [
                "temperature": 1.0
            ]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        let task = session.dataTask(with: request)
        task.resume()
    }
    
    private func generateGeminiImage(prompt: some StringProtocol, model: String, apiKey: String) {
        // Try to use 1.5 Flash if selected, otherwise fallback to the specialized 2.5 image model
        let imageModel = model.contains("gemini-1.5") ? "gemini-1.5-flash" : "gemini-2.5-flash-image"
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(imageModel):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // In 2026, many models support multimodal output via prompt
        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": "Generate a high quality image: \(prompt)"]]]
            ]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                let errorBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
                
                var userFriendlyError = "⚠️ Gemini Image Error (\(httpResponse.statusCode))"
                if errorBody.contains("billing") || errorBody.contains("free tier") || httpResponse.statusCode == 403 {
                    userFriendlyError = "⚠️ Gemini Bildgen-Fehler: Für Bild-Generierung ist 2026 meist ein billing-fähiges Konto nötig. (Modell: \(imageModel))"
                } else if httpResponse.statusCode == 404 {
                    userFriendlyError = "⚠️ Modell \(imageModel) nicht gefunden oder unterstützt keine Bildgenerierung in dieser Region."
                } else {
                    userFriendlyError += ": \(errorBody)"
                }
                
                DispatchQueue.main.async {
                    self?.onMessage?(userFriendlyError)
                    self?.onComplete?()
                }
                return
            }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let first = candidates.first,
                  let content = first["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let inlineData = parts.first?["inlineData"] as? [String: Any],
                  let mimeType = inlineData["mimeType"] as? String,
                  let base64Data = inlineData["data"] as? String else {
                
                DispatchQueue.main.async {
                    self?.onMessage?("⚠️ Bildgen Parser Error. Das Modell \(imageModel) lieferte keine Bilddaten.")
                    self?.onComplete?()
                }
                return
            }
            
            DispatchQueue.main.async {
                self?.onMessage?("[IMAGE]data:\(mimeType);base64,\(base64Data)")
                self?.onComplete?()
            }
        }.resume()
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let responseString = String(data: data, encoding: .utf8) else { return }
        
        // Immediate error check
        if responseString.contains("\"error\"") {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                DispatchQueue.main.async { self.onMessage?("⚠️ Gemini API Error: \(message)") }
            } else {
                DispatchQueue.main.async { self.onMessage?("⚠️ Gemini Error Body: \(responseString)") }
            }
            return
        }
        
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
              let parts = content["parts"] as? [[String: Any]] else { return }
        
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
