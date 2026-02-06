//
//  ChatHistoryView.swift
//  PocketLlama
//
//  Created by Yusuf Siddiqui on 2026-02-04.
//

import SwiftUI

struct ChatHistoryView: View {
    @ObservedObject private var historyManager = ChatHistoryManager.shared
    @State private var selectedSession: ChatSession? = nil
    @State private var showingLoadConfirmation = false
    
    var body: some View {
        Group {
            if historyManager.sessions.isEmpty {
                emptyStateView
            } else {
                sessionListView
            }
        }
        .navigationTitle("History")
        .onAppear {
            historyManager.loadAllSessions()
        }
        .alert("Load Chat?", isPresented: $showingLoadConfirmation) {
            Button("Cancel", role: .cancel) {
                selectedSession = nil
            }
            Button("Load") {
                if let session = selectedSession {
                    loadChat(session)
                }
            }
        } message: {
            Text("This will replace your current chat. Continue?")
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No Saved Chats")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Save a chat from the Chat tab to see it here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
    
    // MARK: - Session List
    
    private var sessionListView: some View {
        List {
            ForEach(historyManager.sessions) { session in
                SessionRowView(session: session, historyManager: historyManager)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedSession = session
                        showingLoadConfirmation = true
                    }
            }
            .onDelete(perform: deleteSessions)
        }
        .listStyle(.insetGrouped)
    }
    
    // MARK: - Actions
    
    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            let session = historyManager.sessions[index]
            historyManager.deleteSession(id: session.id)
        }
    }
    
    private func loadChat(_ session: ChatSession) {
        // Post notification to load the chat in ChatViewModel
        NotificationCenter.default.post(
            name: .loadChatSession,
            object: nil,
            userInfo: ["session": session]
        )
        selectedSession = nil
    }
}

// MARK: - Session Row View

struct SessionRowView: View {
    let session: ChatSession
    let historyManager: ChatHistoryManager
    
    private var formattedCreatedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: session.createdAt)
    }
    
    private var formattedLastChatDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: session.lastChatAt, relativeTo: Date())
    }
    
    private var sessionSize: String {
        let bytes = historyManager.getSessionSize(id: session.id)
        return historyManager.formatSize(bytes)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.title)
                .font(.headline)
                .lineLimit(1)
            
            HStack {
                Label(formattedCreatedDate, systemImage: "calendar")
                Spacer()
                Label(sessionSize, systemImage: "doc")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            HStack {
                Label("Last chat: \(formattedLastChatDate)", systemImage: "clock")
                Spacer()
                Text(session.modelFilename)
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let loadChatSession = Notification.Name("loadChatSession")
}

#Preview {
    NavigationStack {
        ChatHistoryView()
    }
}
