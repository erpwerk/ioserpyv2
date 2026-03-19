import Foundation

class NetworkManager: NSObject, URLSessionDataDelegate {
    private var session: URLSession!
    private var onMessage: ((String) -> Void)?
    private var onComplete: (() -> Void)?
    
    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    func streamChat(url: URL, onMessage: @escaping (String) -> Void, onComplete: @escaping () -> Void) {
        self.onMessage = onMessage
        self.onComplete = onComplete
        
        let task = session.dataTask(with: url)
        task.resume()
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let responseString = String(data: data, encoding: .utf8) else { return }
        
        // Basic SSE parsing: data: message\n\n
        let lines = responseString.components(separatedBy: .newlines)
        for line in lines {
            if line.hasPrefix("data: ") {
                let message = line.replacingOccurrences(of: "data: ", with: "")
                DispatchQueue.main.async {
                    self.onMessage?(message)
                }
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("Stream error: \(error)")
        }
        DispatchQueue.main.async {
            self.onComplete?()
        }
    }
}
