import Foundation

class OpenAIService: NSObject, LLMProvider, URLSessionDataDelegate {
    private var session: URLSession!
    private var onMessage: ((String) -> Void)?
    private var onComplete: (() -> Void)?
    private var apiKey: String = ""
    
    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    func generateStream(prompt: String, model: String, apiKey: String, onMessage: @escaping (String) -> Void, onComplete: @escaping () -> Void) {
        self.onMessage = onMessage
        self.onComplete = onComplete
        self.apiKey = apiKey
        
        // Handle image generation
        if prompt.lowercased().contains("generiere ein bild") || prompt.lowercased().contains("erstelle ein bild") {
            generateImage(prompt: prompt, apiKey: apiKey)
            return
        }
        
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
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
            "model": "dall-e-3",
            "prompt": prompt,
            "n": 1,
            "size": "1024x1024"
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataArray = json["data"] as? [[String: Any]],
                  let imageUrl = dataArray.first?["url"] as? String else {
                DispatchQueue.main.async {
                    self.onMessage?("⚠️ Bildgenerierung fehlgeschlagen.")
                    self.onComplete?()
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
        
        // 1. Check for the "Modern 2026" Array format [ {...}, {...} ]
        if let jsonData = responseString.data(using: .utf8),
           let jsonArray = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
            for item in jsonArray {
                if let type = item["type"] as? String, type == "message",
                   let contentArray = item["content"] as? [[String: Any]] {
                    for content in contentArray {
                        if let textType = content["type"] as? String, textType == "output_text",
                           let text = content["text"] as? String {
                            DispatchQueue.main.async { self.onMessage?(text) }
                        } else if let text = content["text"] as? String {
                            // Fallback for simple "text" fields
                            DispatchQueue.main.async { self.onMessage?(text) }
                        }
                    }
                } else if let type = item["type"] as? String, type == "web_search_call" {
                    // Optionally show status
                    // DispatchQueue.main.async { self.onMessage?("🔍 Suche gestartet...") }
                }
            }
            return
        }

        // 2. Fallback to Legacy "data: " streaming format
        let lines = responseString.components(separatedBy: "\n")
        for line in lines {
            if line.hasPrefix("data: ") {
                let jsonString = line.replacingOccurrences(of: "data: ", with: "")
                let trimmed = jsonString.trimmingCharacters(in: .whitespaces)
                if trimmed == "[DONE]" || trimmed.isEmpty { continue }
                
                if let data = trimmed.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    
                    // Legacy OpenAI format (choices[0].delta.content)
                    if let choices = json["choices"] as? [[String: Any]],
                       let firstChoice = choices.first,
                       let delta = firstChoice["delta"] as? [String: Any],
                       let content = delta["content"] as? String {
                        DispatchQueue.main.async { self.onMessage?(content) }
                    }
                }
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
