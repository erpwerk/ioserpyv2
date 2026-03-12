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
        
        // Use exact documentation specs from March 2026
        let apiModel = model.contains("mini") ? "gpt-4.1-mini" : "gpt-4.1"
        
        var body: [String: Any] = [
            "model": apiModel,
            "input": prompt,
            "stream": true,
            "tool_choice": "auto",
            "include": ["web_search_call.action.sources"]
        ]
        
        // Both gpt-4.1 and 4.1-mini support web_search in the Responses API
        body["tools"] = [
            ["type": "web_search", "external_web_access": true]
        ]
        
        if apiModel == "gpt-4.1" {
            body["reasoning"] = ["effort": "low"]
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
            
            // Download the image and convert to Base64 for consistent UI handling
            guard let imageDownloadURL = URL(string: imageUrl) else { return }
            URLSession.shared.dataTask(with: imageDownloadURL) { [weak self] imageData, imageResponse, imageError in
                if let imageData = imageData, imageError == nil {
                    let base64Data = imageData.base64EncodedString()
                    let mimeType = imageResponse?.mimeType ?? "image/png"
                    DispatchQueue.main.async {
                        self?.onMessage?("[IMAGE]data:\(mimeType);base64,\(base64Data)")
                        self?.onComplete?()
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.onMessage?("⚠️ Bild-Download fehlgeschlagen.")
                        self?.onComplete?()
                    }
                }
            }.resume()
        }.resume()
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let responseString = String(data: data, encoding: .utf8) else { return }
        
        buffer += responseString
        
        // 2026 Responses API uses SSE event blocks separated by \n\n
        let blocks = buffer.components(separatedBy: "\n\n")
        
        // Keep the last potentially incomplete block in the buffer
        if let last = blocks.last, !responseString.hasSuffix("\n\n") {
            buffer = last
        } else {
            buffer = ""
        }
        
        // Process complete blocks
        let completeBlocks = responseString.hasSuffix("\n\n") ? blocks : Array(blocks.dropLast())
        
        for block in completeBlocks {
            processSSEBlock(block, rawData: data)
        }
    }
    
    private func processSSEBlock(_ block: String, rawData: Data) {
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
        
        // Basic error check in non-standard stream starts
        if block.contains("\"error\"") && dataString.isEmpty {
            dataString = block.trimmingCharacters(in: .whitespaces)
        }
        
        guard !dataString.isEmpty else { return }
        
        if dataString == "[DONE]" { return }
        
        guard let jsonData = dataString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return
        }
        
        // Handle direct error objects
        if let error = json["error"] as? [String: Any], let msg = error["message"] as? String {
            DispatchQueue.main.async { self.onMessage?("⚠️ OpenAI Error: \(msg)") }
            return
        }
        
        switch eventType {
        case "response.output_text.delta":
            if let delta = json["delta"] as? String {
                DispatchQueue.main.async { self.onMessage?(delta) }
            }
        case "response.output_item.added":
            // Can be used to signal tool starts, e.g. web_search_call
            if let item = json["item"] as? [String: Any], item["type"] as? String == "web_search_call" {
                DispatchQueue.main.async { self.onMessage?("\n🔍 *Suche läuft...*\n") }
            }
        case "response.completed":
            // Final processing (citations etc) could be done here
            break
        default:
            // Fallback for standard chat completion deltas if accidentally hit
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
