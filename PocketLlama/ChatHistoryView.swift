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
    
    // Selection mode state
    @State private var isSelectionMode = false
    @State private var selectedSessionIds: Set<UUID> = []
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        Group {
            if historyManager.sessions.isEmpty {
                emptyStateView
            } else {
                sessionListView
            }
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !historyManager.sessions.isEmpty {
                    Button(isSelectionMode ? "Done" : "Select") {
                        withAnimation {
                            isSelectionMode.toggle()
                            if !isSelectionMode {
                                selectedSessionIds.removeAll()
                            }
                        }
                    }
                }
            }
            
            ToolbarItem(placement: .navigationBarLeading) {
                if isSelectionMode {
                    Button(selectedSessionIds.count == historyManager.sessions.count ? "Deselect All" : "Select All") {
                        if selectedSessionIds.count == historyManager.sessions.count {
                            selectedSessionIds.removeAll()
                        } else {
                            selectedSessionIds = Set(historyManager.sessions.map { $0.id })
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelectionMode && !selectedSessionIds.isEmpty {
                deleteButtonBar
            }
        }
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
        .alert("Delete \(selectedSessionIds.count) Chat\(selectedSessionIds.count == 1 ? "" : "s")?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteSelectedSessions()
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }
    
    // MARK: - Delete Button Bar
    
    private var deleteButtonBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Text("Delete \(selectedSessionIds.count) Chat\(selectedSessionIds.count == 1 ? "" : "s")")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .background(Color(UIColor.systemBackground))
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
                HStack {
                    // Selection indicator
                    if isSelectionMode {
                        Image(systemName: selectedSessionIds.contains(session.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selectedSessionIds.contains(session.id) ? .blue : .secondary)
                            .font(.title2)
                    }
                    
                    SessionRowView(session: session, historyManager: historyManager)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if isSelectionMode {
                        toggleSelection(for: session)
                    } else {
                        selectedSession = session
                        showingLoadConfirmation = true
                    }
                }
            }
            .onDelete(perform: deleteSessions)
            .deleteDisabled(isSelectionMode)
        }
        .listStyle(.insetGrouped)
    }
    
    // MARK: - Actions
    
    private func toggleSelection(for session: ChatSession) {
        if selectedSessionIds.contains(session.id) {
            selectedSessionIds.remove(session.id)
        } else {
            selectedSessionIds.insert(session.id)
        }
    }
    
    private func deleteSelectedSessions() {
        for id in selectedSessionIds {
            historyManager.deleteSession(id: id)
        }
        selectedSessionIds.removeAll()
        isSelectionMode = false
    }
    
    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            let session = historyManager.sessions[index]
            historyManager.deleteSession(id: session.id)
        }
    }
    
    private func loadChat(_ session: ChatSession) {
        // Load the session directly on the shared ViewModel
        ChatViewModel.shared.loadSession(session)
        
        // Post notification to switch tabs (ContentView listens for this)
        NotificationCenter.default.post(
            name: .loadChatSession,
            object: nil,
            userInfo: nil
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
    
    /// Look up the friendly model name from historyManager, fallback to filename
    private var modelDisplayName: String {
        historyManager.getModelDisplayName(for: session.modelFilename)
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
                Text(modelDisplayName)
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
