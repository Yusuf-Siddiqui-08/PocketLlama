//
//  ChatSession.swift
//  PocketLlama
//
//  Created by Yusuf Siddiqui on 2026-02-04.
//

import Foundation

/// Represents a saved chat session that can be persisted to disk
struct ChatSession: Codable, Identifiable {
    let id: UUID
    let title: String           // Truncated first prompt (30 chars max)
    let messages: [String]      // Chat messages array
    let modelFilename: String   // Model used for this chat
    let createdAt: Date
    var lastChatAt: Date
    
    /// Creates a title from the first user message
    static func generateTitle(from messages: [String]) -> String {
        // Find the first user message
        guard let firstUserMessage = messages.first(where: { $0.hasPrefix("User:") }) else {
            return "New Chat"
        }
        
        // Remove "User: " prefix and truncate
        var title = firstUserMessage.replacingOccurrences(of: "User: ", with: "")
        
        // Truncate to 30 characters with ellipsis
        if title.count > 30 {
            title = String(title.prefix(30)) + "..."
        }
        
        return title.isEmpty ? "New Chat" : title
    }
}
