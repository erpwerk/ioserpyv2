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
        
        let lowerPrompt = prompt.lowercased()
        if lowerPrompt.contains("bild") && (lowerPrompt.contains("generier") || lowerPrompt.contains("erstell") || lowerPrompt.contains("mach")) {
            generateImage(prompt: prompt, apiKey: apiKey)
            return
        }
        
        guard let url = URL(string: "https://api.openai.com/v1/responses") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Canonical 2026 IDs
        let apiModel = model.contains("mini") ? "gpt-5-mini" : "gpt-5"
        
        var body: [String: Any] = [
            "model": apiModel,
            "input": prompt,
            "stream": true
        ]
        
        // Only gpt-5 main supports web_search in early 2026 previews
        if apiModel == "gpt-5" {
            body["tools"] = [["type": "web_search"]]
        }
        
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
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                let errorBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
                DispatchQueue.main.async {
                    self?.onMessage?("⚠️ OpenAI Image Error (\(httpResponse.statusCode)): \(errorBody)")
                    self?.onComplete?()
                }
                return
            }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataArray = json["data"] as? [[String: Any]],
                  let imageUrl = dataArray.first?["url"] as? String else {
                DispatchQueue.main.async {
                    self?.onMessage?("⚠️ Bildgen fehlgeschlagen (Parser Error).")
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
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            // We'll capture the error body in didReceive data
            completionHandler(.allow)
        } else {
            completionHandler(.allow)
        }
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let responseString = String(data: data, encoding: .utf8) else { return }
        
        // If it looks like a JSON error object, report it immediately
        if responseString.contains("\"error\"") {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                DispatchQueue.main.async { self.onMessage?("⚠️ OpenAI API Error: \(message)") }
                return
            }
        }
        
        buffer += responseString
        parseBuffer()
    }
    
    private func parseBuffer() {
        var searchIndex = buffer.startIndex
        while let open = buffer[searchIndex...].firstIndex(where: { $0 == "{" || $0 == "[" }) {
            let startChar = buffer[open]
            let endChar: Character = (startChar == "{") ? "}" : "]"
            var balance = 0
            var found = false
            var endIdx = open
            
            for (i, char) in buffer[open...].enumerated() {
                if char == startChar { balance += 1 }
                else if char == endChar { balance -= 1 }
                if balance == 0 {
                    endIdx = buffer.index(open, offsetBy: i)
                    found = true
                    break
                }
            }
            
            if found {
                let jsonString = String(buffer[open...endIdx])
                if let data = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) {
                    process(json: json)
                }
                buffer.removeSubrange(buffer.startIndex...endIdx)
                searchIndex = buffer.startIndex
            } else { break }
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
        if let outputText = item["output_text"] as? String {
            DispatchQueue.main.async { self.onMessage?(outputText) }
        } else if let contentArray = item["content"] as? [[String: Any]] {
            for content in contentArray {
                if let text = (content["text"] as? String) ?? (content["output_text"] as? String) {
                    DispatchQueue.main.async { self.onMessage?(text) }
                }
            }
        } else if let choices = item["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let delta = first["delta"] as? [String: Any],
                  let content = delta["content"] as? String {
            DispatchQueue.main.async { self.onMessage?(content) }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            DispatchQueue.main.async { self.onMessage?("⚠️ Connection Error: \(error.localizedDescription)") }
        }
        DispatchQueue.main.async { self.onComplete?() }
    }
}
