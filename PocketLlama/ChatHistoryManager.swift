//
//  ChatHistoryManager.swift
//  PocketLlama
//
//  Created by Yusuf Siddiqui on 2026-02-04.
//

import Foundation

/// Manages persistence of chat sessions to local storage
class ChatHistoryManager: ObservableObject {
    static let shared = ChatHistoryManager()
    
    @Published var sessions: [ChatSession] = []
    
    private let fileManager = FileManager.default
    private var historyDirectoryURL: URL {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsURL.appendingPathComponent("ChatHistory", isDirectory: true)
    }
    
    private init() {
        createHistoryDirectoryIfNeeded()
        loadAllSessions()
    }
    
    // MARK: - Directory Management
    
    private func createHistoryDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: historyDirectoryURL.path) {
            try? fileManager.createDirectory(at: historyDirectoryURL, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Save
    
    func saveSession(_ session: ChatSession) {
        let fileURL = historyDirectoryURL.appendingPathComponent("\(session.id.uuidString).json")
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(session)
            try data.write(to: fileURL)
            
            // Reload sessions to update the list
            loadAllSessions()
        } catch {
            print("Failed to save chat session: \(error)")
        }
    }
    
    // MARK: - Load
    
    func loadAllSessions() {
        createHistoryDirectoryIfNeeded()
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: historyDirectoryURL, includingPropertiesForKeys: nil)
            let jsonFiles = fileURLs.filter { $0.pathExtension == "json" }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            var loadedSessions: [ChatSession] = []
            
            for fileURL in jsonFiles {
                if let data = try? Data(contentsOf: fileURL),
                   let session = try? decoder.decode(ChatSession.self, from: data) {
                    loadedSessions.append(session)
                }
            }
            
            // Sort by lastChatAt descending (newest first)
            sessions = loadedSessions.sorted { $0.lastChatAt > $1.lastChatAt }
        } catch {
            print("Failed to load chat sessions: \(error)")
            sessions = []
        }
    }
    
    // MARK: - Delete
    
    func deleteSession(id: UUID) {
        let fileURL = historyDirectoryURL.appendingPathComponent("\(id.uuidString).json")
        
        do {
            try fileManager.removeItem(at: fileURL)
            loadAllSessions()
        } catch {
            print("Failed to delete chat session: \(error)")
        }
    }
    
    // MARK: - Session Size
    
    func getSessionSize(id: UUID) -> Int64 {
        let fileURL = historyDirectoryURL.appendingPathComponent("\(id.uuidString).json")
        
        do {
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
    
    /// Formats bytes into a human-readable string (e.g., "2.3 KB")
    func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
