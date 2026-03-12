import Foundation

struct Conversation: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [Message]
    let createdAt: Date
    var lastUpdatedAt: Date
    
    init(title: String = "Neuer Chat", messages: [Message] = []) {
        self.id = UUID()
        self.title = title
        self.messages = messages
        self.createdAt = Date()
        self.lastUpdatedAt = Date()
    }
}
