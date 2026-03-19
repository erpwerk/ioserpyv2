import Foundation

class OpenAIService: NSObject, LLMProvider, URLSessionDataDelegate {
    private var session: URLSession!
    private var onMessage: ((String) -> Void)?
    private var onComplete: (() -> Void)?
    private var buffer = ""
    
    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    func generateStream(prompt: String, model: String, apiKey: String, onMessage: @escaping (String) -> Void, onComplete: @escaping () -> Void) {
        self.onMessage = onMessage
        self.onComplete = onComplete
        self.buffer = ""
        
        guard let url = URL(string: "https://api.openai.com/v1/responses") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Canonical model is 4.1-mini for 2026 ERPY
        let apiModel = "gpt-4.1-mini"
        
        var tools: [[String: Any]] = [
            ["type": "web_search", "external_web_access": true]
        ]
        
        // Detect image request to add image_generation tool
        let lowerPrompt = prompt.lowercased()
        if lowerPrompt.contains("bild") || lowerPrompt.contains("photo") || lowerPrompt.contains("image") {
            tools.append([
                "type": "image_generation",
                "partial_images": 2,
                "action": "auto"
            ])
        }
        
        let body: [String: Any] = [
            "model": apiModel,
            "input": prompt,
            "stream": true,
            "tool_choice": "auto",
            "include": ["web_search_call.action.sources"],
            "tools": tools
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        let task = session.dataTask(with: request)
        task.resume()
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let responseString = String(data: data, encoding: .utf8) else { return }
        
        buffer += responseString
        
        let blocks = buffer.components(separatedBy: "\n\n")
        
        if let last = blocks.last, !responseString.hasSuffix("\n\n") {
            buffer = last
        } else {
            buffer = ""
        }
        
        let completeBlocks = responseString.hasSuffix("\n\n") ? blocks : Array(blocks.dropLast())
        
        for block in completeBlocks {
            processSSEBlock(block)
        }
    }
    
    private func processSSEBlock(_ block: String) {
        let lines = block.components(separatedBy: "\n")
        var eventType = ""
        var dataString = ""
        
        for line in lines {
            if line.hasPrefix("event: ") {
                eventType = line.replacingOccurrences(of: "event: ", with: "").trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data: ") {
                dataString = line.replacingOccurrences(of: "data: ", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        
        if block.contains("\"error\"") && dataString.isEmpty {
            dataString = block.trimmingCharacters(in: .whitespaces)
        }
        
        guard !dataString.isEmpty else { return }
        if dataString == "[DONE]" { return }
        
        guard let jsonData = dataString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return
        }
        
        if let error = json["error"] as? [String: Any], let msg = error["message"] as? String {
            DispatchQueue.main.async { self.onMessage?("⚠️ OpenAI Error: \(msg)") }
            return
        }
        
        switch eventType {
        case "response.output_text.delta":
            if let delta = json["delta"] as? String {
                DispatchQueue.main.async { self.onMessage?(delta) }
            }
        case "response.image_generation_call.partial_image":
            // Streaming partial images (2026 feature)
            if let b64 = json["partial_image_b64"] as? String {
                DispatchQueue.main.async { self.onMessage?("[IMAGE]data:image/png;base64,\(b64)") }
            }
        case "response.output_item.added":
            if let item = json["item"] as? [String: Any] {
                let type = item["type"] as? String
                if type == "web_search_call" {
                    DispatchQueue.main.async { self.onMessage?("\n🔍 *Suche läuft...*\n") }
                } else if type == "image_generation_call" {
                    DispatchQueue.main.async { self.onMessage?("\n🎨 *Bild wird erstellt...*\n") }
                }
            }
        case "response.output_item.done":
            // Final tool outputs
            if let item = json["item"] as? [String: Any],
               item["type"] as? String == "image_generation_call",
               let result = item["result"] as? String {
                DispatchQueue.main.async { self.onMessage?("[IMAGE]data:image/png;base64,\(result)") }
            }
        case "response.completed":
            break
        default:
            // Minimal fallback for standard deltas
            if let choices = json["choices"] as? [[String: Any]],
               let first = choices.first,
               let delta = first["delta"] as? [String: Any],
               let content = delta["content"] as? String {
                DispatchQueue.main.async { self.onMessage?(content) }
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            DispatchQueue.main.async { self.onMessage?("⚠️ Connection Error: \(error.localizedDescription)") }
        }
        DispatchQueue.main.async { self.onComplete?() }
    }
}
