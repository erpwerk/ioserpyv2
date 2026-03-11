Message.swift
../erpy-v2/ios-app/Sources/Models



import Foundation
struct Message: Identifiable, Codable {
    let id: UUID
    let role: String
    var content: String
    let createdAt: Date
    
    init(role: String, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.createdAt = Date()
    }
}
