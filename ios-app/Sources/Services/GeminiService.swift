import Foundation

class GeminiService: NSObject, LLMProvider, URLSessionDataDelegate {
    private var session: URLSession!
    private var onMessage: ((String) -> Void)?
    private var onComplete: (() -> Void)?
    
    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    func generateStream(prompt: String, model: String, apiKey: String, onMessage: @escaping (String) -> Void, onComplete: @escaping () -> Void) {
        self.onMessage = onMessage
        self.onComplete = onComplete
        
        // Handle image generation branching (Nano Banana)
        if prompt.lowercased().contains("generiere ein bild") || prompt.lowercased().contains("erstelle ein bild") {
            generateNanoImage(prompt: prompt, apiKey: apiKey)
            return
        }
        
        // Grounding setup for Gemini 3.1
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "contents": [[
                "parts": [["text": prompt]]
            ]],
            "tools": [[
                "google_search_retrieval": [:] // Grounding enabled
            ]]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        let task = session.dataTask(with: request)
        task.resume()
    }
    
    private func generateNanoImage(prompt: String, apiKey: String) {
        // Nano Banana 2 Pro (gemini-3.1-pro-image-preview) for high quality
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-pro-image-preview:generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "contents": [[
                "parts": [["text": "Generate a high quality image based on this description: \(prompt)"]]
            ]]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
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
                    self.onMessage?("⚠️ Bildgenerierung (Nano Banana) fehlgeschlagen.")
                    self.onComplete?()
                }
                return
            }
            
            // For on-device display, we return a local data URL or handle base64
            DispatchQueue.main.async {
                self.onMessage?("[IMAGE]data:\(mimeType);base64,\(base64Data)")
                self.onComplete?()
            }
        }.resume()
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let responseString = String(data: data, encoding: .utf8) else { return }
        
        // Split by JSON object boundaries "}{" or common delimiters in the stream
        let cleaned = responseString.replacingOccurrences(of: "][", with: "],[")
        let chunks = cleaned.components(separatedBy: "}\r\n")
        
        for chunk in chunks {
            var finalChunk = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            if finalChunk.isEmpty { continue }
            if finalChunk.hasPrefix(",") { finalChunk.removeFirst() }
            if finalChunk.hasPrefix("[") { finalChunk.removeFirst() }
            if !finalChunk.hasSuffix("}") { finalChunk += "}" }
            
            guard let chunkData = finalChunk.data(using: .utf8) else { continue }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: chunkData) as? [String: Any] {
                    if let candidates = json["candidates"] as? [[String: Any]],
                       let first = candidates.first,
                       let content = first["content"] as? [String: Any],
                       let parts = content["parts"] as? [[String: Any]] {
                        for part in parts {
                            if let text = part["text"] as? String {
                                DispatchQueue.main.async { self.onMessage?(text) }
                            }
                        }
                    } else if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
                        DispatchQueue.main.async { self.onMessage?("⚠️ Gemini API Error: \(message)") }
                    }
                }
            } catch {
                // Ignore fragments
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.onMessage?("⚠️ Connection Error: \(error.localizedDescription)")
            }
        }
        DispatchQueue.main.async {
            self.onComplete?()
        }
    }
}
