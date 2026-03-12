import Foundation

struct Message: Identifiable, Codable {
    let id: UUID
    let role: String
    var content: String
    var imageUrl: String?
    let createdAt: Date
    
    init(role: String, content: String, imageUrl: String? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.imageUrl = imageUrl
        self.createdAt = Date()
    }
}
