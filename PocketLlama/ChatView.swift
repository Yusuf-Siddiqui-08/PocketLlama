//
//  ChatView.swift
//  PocketLlama
//
//  Created by Yusuf Siddiqui on 2026-01-12.
//

import SwiftUI

struct ChatView: View {
    @ObservedObject var vm = ChatViewModel.shared
    @AppStorage("currentModelFilename") private var currentModelFilename: String = ""
    
    private var currentModelDisplayName: String {
        if let match = availableModels.first(where: { $0.filename == currentModelFilename }) {
            return match.name
        }
        return currentModelFilename.isEmpty ? "PocketLlama" : currentModelFilename
    }
    
    @State private var errorMessage: String? = nil
    @State private var showingSaveConfirmation = false
    @State private var showingSavedAlert = false
    
    var body: some View {
            VStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            // Use enumerated() to create unique IDs for every message row.
                            ForEach(Array(vm.messages.enumerated()), id: \.offset) { index, msg in
                                MessageBubble(message: msg)
                                    .id(index) // Assign ID for auto-scrolling
                            }
                        }
                        .padding()
                    }
                    // Auto-scroll to bottom when a new message arrives
                    .onChange(of: vm.messages.count) {
                        withAnimation {
                            proxy.scrollTo(vm.messages.count - 1, anchor: .bottom)
                        }
                    }
                }
                
                HStack {
                    TextField("Type a message...", text: $vm.inputText)
                        .textFieldStyle(.roundedBorder)
                        .disabled(vm.isLoading)
                    if vm.isLoading {
                        ProgressView()
                    } else {
                        Button(action: { vm.sendMessage() }) {
                            Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
                        }
                    }
                }
                .padding()
                .background(Color(UIColor.systemBackground))
            }
            .navigationTitle(currentModelDisplayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { vm.isAutoSaveEnabled.toggle() }) {
                            Label("Auto-Save", systemImage: vm.isAutoSaveEnabled ? "checkmark.square.fill" : "square")
                        }
                        .menuActionDismissBehavior(.disabled)
                        
                        Divider()
                        
                        Button(action: { saveCurrentChat() }) {
                            Label("Save Chat", systemImage: "square.and.arrow.down")
                        }
                        .disabled(!hasUserMessages)
                        .menuActionDismissBehavior(.disabled)
                        
                        Button(role: .destructive, action: { vm.clearChat() }) {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .task {
                if currentModelFilename.isEmpty {
                    let models = installedModels()
                    if models.count == 1 { currentModelFilename = models[0].filename }
                }
                if vm.bot == nil { vm.autoLoadModel() }
            }
            .onChange(of: currentModelFilename) { _, _ in vm.switchModelIfNeeded() }
            .onReceive(vm.$errorMessage) { msg in if let msg = msg { self.errorMessage = msg } }
            .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Chat Saved", isPresented: $showingSavedAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your chat has been saved to History.")
            }
            .alert("Delete Chat?", isPresented: $vm.showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    vm.clearChat()
                }
            } message: {
                Text("This will clear all messages. This action cannot be undone.")
            }
    }
    
    // MARK: - Helpers
    
    private var hasUserMessages: Bool {
        vm.messages.contains { $0.hasPrefix("User:") }
    }
    
    private func saveCurrentChat() {
        let session = vm.createSavableSession(modelFilename: currentModelFilename)
        ChatHistoryManager.shared.saveSession(session)
        showingSavedAlert = true
    }
}

struct MessageBubble: View {
    let message: String
    var isUser: Bool { message.starts(with: "User") }
    
    var body: some View {
        HStack {
            if isUser { Spacer() }
            
            // Text(.init(...)) parses Markdown automatically!
            Text(.init(processMarkdown(message)))
                .padding(12)
                .background(isUser ? Color.blue : Color(UIColor.secondarySystemBackground))
                .foregroundColor(isUser ? .white : .primary)
                .cornerRadius(16)
            
            if !isUser { Spacer() }
        }
    }
    
    // Helper to clean up specific patterns before rendering
    private func processMarkdown(_ text: String) -> String {
        var cleaned = text
        
        // 1. Remove prefixes
        cleaned = cleaned.replacingOccurrences(of: "User: ", with: "")
        cleaned = cleaned.replacingOccurrences(of: "AI: ", with: "")
        cleaned = cleaned.replacingOccurrences(of: "System: ", with: "")
        
        // 2. Convert Bullet Points (* Item -> • Item)
        if let regex = try? NSRegularExpression(pattern: "(^|\\n)\\* ", options: []) {
            let range = NSRange(location: 0, length: cleaned.utf16.count)
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "$1• ")
        }
        
        // Note: We DO NOT remove "**" because Text(.init()) needs them to render Bold.
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
