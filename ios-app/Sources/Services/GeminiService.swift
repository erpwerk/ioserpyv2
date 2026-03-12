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
        
        // Handle image generation separately for demo
        if prompt.lowercased().contains("generiere ein bild") || prompt.lowercased().contains("erstelle ein bild") {
            generateImage(prompt: prompt, apiKey: apiKey)
            return
        }
        
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
                "google_search_retrieval": [:]
            ]]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        let task = session.dataTask(with: request)
        task.resume()
    }
    
    private func generateImage(prompt: String, apiKey: String) {
        // Mocking Imagen call for demo as Imagen API is often restricted or differently structured
        // In a real app, this would call the Vertex AI / Google AI Imagen API
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.onMessage?("[IMAGE]https://picsum.photos/1024/1024") // Placeholder image
            self.onComplete?()
        }
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let responseString = String(data: data, encoding: .utf8) else { return }
        
        // Gemini stream comes as a JSON array [{},{},...] or individual objects
        // We strip the leading [ and , to parse individual chunks
        let cleaned = responseString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^\\[", with: "", options: .regularExpression)
            .replacingOccurrences(of: "^,", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\]$", with: "", options: .regularExpression)
        
        // Split by "}\n," or similar if multiple objects are in one chunk
        let chunks = cleaned.components(separatedBy: "}\n,")
        
        for var chunk in chunks {
            if !chunk.hasSuffix("}") && !chunk.isEmpty { chunk += "}" }
            guard let chunkData = chunk.data(using: .utf8) else { continue }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: chunkData) as? [String: Any] {
                    // Check for error
                    if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
                        DispatchQueue.main.async { self.onMessage?("⚠️ Gemini Error: \(message)") }
                        continue
                    }
                    
                    if let candidates = json["candidates"] as? [[String: Any]],
                       let first = candidates.first {
                        
                        // Extract text
                        if let content = first["content"] as? [String: Any],
                           let parts = content["parts"] as? [[String: Any]] {
                            for part in parts {
                                if let text = part["text"] as? String {
                                    DispatchQueue.main.async { self.onMessage?(text) }
                                }
                            }
                        }
                    }
                }
            } catch {
                // Ignore partial JSON
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
