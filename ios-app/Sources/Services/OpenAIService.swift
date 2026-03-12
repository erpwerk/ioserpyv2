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
        
        // Handle image generation separately if prompt implies it
        if prompt.lowercased().contains("generiere ein bild") || prompt.lowercased().contains("erstelle ein bild") {
            generateImage(prompt: prompt, apiKey: apiKey)
            return
        }
        
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let tools: [[String: Any]] = [
            [
                "type": "function",
                "function": [
                    "name": "web_search",
                    "description": "Sucht im Web nach aktuellen Informationen.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "query": [
                                "type": "string",
                                "description": "Der Suchbegriff"
                            ]
                        ],
                        "required": ["query"]
                    ]
                ]
            ]
        ]
        
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "stream": true,
            "tools": tools
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
                // Pass image URL back via a special format or another channel
                // For now, we'll use a prefix to identify it in the view model
                self.onMessage?("[IMAGE]\(imageUrl)")
                self.onComplete?()
            }
        }.resume()
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let responseString = String(data: data, encoding: .utf8) else { return }
        
        let lines = responseString.components(separatedBy: "\n")
        for line in lines {
            if line.hasPrefix("data: ") {
                let jsonString = line.replacingOccurrences(of: "data: ", with: "")
                if jsonString == "[DONE]" { continue }
                
                if let data = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let delta = choices.first?["delta"] as? [String: Any] {
                    
                    if let content = delta["content"] as? String {
                        DispatchQueue.main.async {
                            self.onMessage?(content)
                        }
                    }
                    
                    // Handle tool calls in stream (simplified for this exercise)
                    if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                        // In a real app, we would accumulate tool calls and execute search
                        // For this demo, we notify the view model
                        DispatchQueue.main.async {
                            self.onMessage?("[TOOL_CALL]web_search")
                        }
                    }
                }
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DispatchQueue.main.async {
            self.onComplete?()
        }
    }
}
