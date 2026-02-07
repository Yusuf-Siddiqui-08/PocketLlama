//
//  ChatViewModel.swift
//  PocketLlama
//
//  Created by Yusuf Siddiqui on 2026-01-12.
//

import Foundation
import SwiftUI
import Combine
import LLM

class ChatViewModel: ObservableObject {
    static let shared = ChatViewModel()
    
    @AppStorage("currentModelFilename") private var currentModelFilename: String = ""
    private var selectedModelURL: URL? {
        guard !currentModelFilename.isEmpty else { return nil }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(currentModelFilename)
    }

    @Published var messages: [String] = ["System: Select a model from Library first."]
    @Published var inputText = ""
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    
    // Auto-save properties
    @Published var isAutoSaveEnabled = false
    @Published var showDeleteConfirmation = false  // For menu bar delete command
    var currentSessionId: UUID? = nil  // Tracks the current session for auto-save updates

    private enum ChatError: Error {
        case timeout
        case contextLimit
    }
    
    var bot: LLM?
    var modelURL: URL?
    var chatHistory = ""
    private var isBotContextActive = false

    // --- TEMPLATE HELPERS ---
    private var isGemma: Bool { modelURL?.lastPathComponent.lowercased().contains("gemma") ?? false }
    private var isQwen: Bool { modelURL?.lastPathComponent.lowercased().contains("qwen") ?? false }
    private var isLlama3: Bool { modelURL?.lastPathComponent.lowercased().contains("llama-3") ?? false }
    private var isPhi3: Bool { modelURL?.lastPathComponent.lowercased().contains("phi-3") ?? false }
    
    // Check if model is likely small context (like TinyLlama)
    private var isSmallContextModel: Bool {
            return true
        }

    // 1. SYSTEM PROMPT
    private func systemPrompt(for style: String) -> String {
        let instruction = style == "detailed" ? "Provide comprehensive, structured answers." : "Provide simple, concise answers."
        let constraint = " Use plain text only. Avoid markdown code blocks."
        
        if isLlama3 {
            return "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\nYou are a helpful AI assistant. \(instruction) \(constraint)<|eot_id|>"
        } else if isQwen {
            return "<|im_start|>system\nYou are a helpful AI assistant. \(instruction) \(constraint)<|im_end|>\n"
        } else if isGemma {
            return "<start_of_turn>user\n\(instruction) \(constraint)<end_of_turn>\n<start_of_turn>model\nOkay.<end_of_turn>\n"
        } else if isPhi3 {
            return "<|system|>\nYou are a helpful AI assistant. \(instruction) \(constraint)<|end|>\n"
        } else {
            return "<|system|>\nYou are a helpful AI assistant. \(instruction) \(constraint)</s>"
        }
    }

    // 2. RESPONSE SANITIZER
    private func cleanResponse(_ rawText: String) -> String {
        var text = rawText
        if let range = text.range(of: "<end_of_turn>") { text = String(text[..<range.lowerBound]) }
        if let range = text.range(of: "mathematical expression:") { text = String(text[..<range.lowerBound]) }
        if let range = text.range(of: "[\\u0900-\\u097F\\u0980-\\u09FF]", options: .regularExpression) { text = String(text[..<range.lowerBound]) }
        if let range = text.range(of: "\n\n\n") { text = String(text[..<range.lowerBound]) }
        
        if let regex = try? NSRegularExpression(pattern: "(?s)(.{10,})\\1+$", options: []) {
            let nsRange = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, options: [], range: nsRange), match.numberOfRanges > 1 {
                let repeatingUnitRange = match.range(at: 1)
                if let swiftRange = Range(repeatingUnitRange, in: text) {
                    let unit = String(text[swiftRange])
                    let fullLoopRange = Range(match.range, in: text)!
                    text.replaceSubrange(fullLoopRange, with: unit)
                }
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func autoLoadModel() {
        // 1. Indicate loading immediately
        self.isLoading = true
        self.messages.append("System: Scanning for models...")

        Task.detached {
            let fileManager = FileManager.default
            let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            
            // Access current filename on MainActor safely
            let filename = await MainActor.run { return self.currentModelFilename }
            
            let modelToLoadURL: URL?
            
            if !filename.isEmpty {
                 let specificURL = documentsURL.appendingPathComponent(filename)
                 if fileManager.fileExists(atPath: specificURL.path) {
                     modelToLoadURL = specificURL
                 } else {
                     modelToLoadURL = nil
                 }
            } else {
                if let files = try? fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil),
                   let firstModel = files.first(where: { $0.pathExtension == "gguf" }) {
                    modelToLoadURL = firstModel
                } else {
                    modelToLoadURL = nil
                }
            }

            guard let url = modelToLoadURL else {
                await MainActor.run {
                    self.messages.removeLast() // Remove "Scanning..."
                    self.messages.append("System: No models found. Please download one in the Library tab.")
                    self.isLoading = false
                }
                return
            }
            
            await MainActor.run {
                self.modelURL = url
                if let last = self.messages.last, last == "System: Scanning for models..." {
                    self.messages.removeLast()
                }
                self.messages.append("System: Loading \(url.lastPathComponent)...")
            }
            
            // 2. Run heavy work in the background
            let newBot = LLM(from: url)
            
            // 3. Update UI back on the Main Thread
            await MainActor.run {
                self.bot = newBot
                self.isBotContextActive = false
                self.isLoading = false
                
                if self.bot == nil {
                    self.messages.append("System: Failed to load model. File might be corrupt.")
                } else {
                    let style = self.currentAnswerStyle()
                    self.chatHistory = self.systemPrompt(for: style)
                    self.messages.append("System: Ready! Chat with me.")
                }
            }
        }
    }
    
    // --- CONTEXT MANAGEMENT HELPERS ---
    
    // Heuristic: 1 token ~= 4 characters.
    // TinyLlama limit is 2048 tokens (~8192 chars).
    // We set a safety threshold of ~6000 chars to be safe.
    private var isContextFull: Bool {
        let threshold = isSmallContextModel ? 6000 : 24000 // 24k chars for bigger models
        return chatHistory.count > threshold
    }
    
    private func resetContext(withLastMessage userMessage: String) {
        // 1. Kill the old bot
        bot = nil
        isBotContextActive = false
        
        // 2. Re-init
        if let url = self.modelURL {
            bot = LLM(from: url)
        }
        
        // 3. Reset History to just System + Newest User Message
        let recoveryPrompt = self.systemPrompt(for: self.currentAnswerStyle())
        
        // Note: We don't add userMessage here yet, the sendMessage flow handles the prompt construction
        chatHistory = recoveryPrompt
        
        DispatchQueue.main.async {
            self.messages.append("System: Context limit reached. Older messages forgotten to free up memory.")
        }
    }
    
    func sendMessage() {
        guard !inputText.isEmpty else { return }

        let userMessage = inputText
        inputText = ""
        isLoading = true
        messages.append("User: \(userMessage)")

        // --- PRE-FLIGHT CHECK ---
        // If history is too long, hard reset NOW before sending to LLM
        if isContextFull {
            resetContext(withLastMessage: userMessage)
        }

        // --- 1. PREPARE THE NEW TEXT BLOCK ---
        var userSegment = ""
        if isLlama3 {
            userSegment = "<|start_header_id|>user<|end_header_id|>\n\n\(userMessage)<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n"
        } else if isQwen {
            userSegment = "<|im_start|>user\n\(userMessage)<|im_end|>\n<|im_start|>assistant\n"
        } else if isGemma {
            userSegment = "<start_of_turn>user\n\(userMessage)<end_of_turn>\n<start_of_turn>model\n"
        } else if isPhi3 {
            userSegment = "\n<|user|>\n\(userMessage)<|end|>\n<|assistant|>\n"
        } else {
            userSegment = "\n<|user|>\n\(userMessage)</s>\n<|assistant|>\n"
        }
        
        // --- 2. DETERMINE PROMPT ---
        var promptToSend = ""
        if !isBotContextActive {
            promptToSend = chatHistory + userSegment
            isBotContextActive = true
        } else {
            promptToSend = userSegment
        }
        
        // Update history *speculatively* (will correct on failure)
        chatHistory += userSegment

        Task {
            // Ensure bot is alive
            if bot == nil, let url = self.modelURL {
                bot = LLM(from: url)
                promptToSend = self.systemPrompt(for: self.currentAnswerStyle()) + userSegment
                isBotContextActive = true
            }
            
            guard let currentBot = bot else { return }

            do {
                let response: String = try await withThrowingTaskGroup(of: String.self) { group in
                    group.addTask { await currentBot.getCompletion(from: promptToSend) }
                    
                    group.addTask {
                        try await Task.sleep(nanoseconds: 60_000_000_000)
                        throw ChatError.timeout
                    }
                    let result = try await group.next()!
                    group.cancelAll()
                    return result
                }
                // --- FIX STARTS HERE ---
                // If the model fails silently (context overflow), it often returns an empty string.
                // We must treat this as an error to trigger the recovery logic.
                if response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    throw ChatError.contextLimit
                }
                // --- FIX ENDS HERE ---
                
                self.handleResponse(response)

            } catch {
                print("⚠️ LLM Error: \(error). Performing Emergency Reset.")
                
                // --- 3. CRASH RECOVERY ---
                // If we land here, the model likely rejected the tokens.
                
                // 1. Force Re-init
                self.bot = nil
                self.isBotContextActive = false
                if let url = self.modelURL {
                    self.bot = LLM(from: url)
                }
                
                if let newBot = self.bot {
                    // 2. Construct "Goldfish" Prompt (System + This Message ONLY)
                    let recoveryPrompt = self.systemPrompt(for: self.currentAnswerStyle()) + userSegment
                    
                    // 3. Reset internal history state
                    self.chatHistory = recoveryPrompt
                    self.isBotContextActive = true
                    
                    // 4. Retry
                    let retryResponse = await newBot.getCompletion(from: recoveryPrompt)
                    self.handleResponse(retryResponse)
                } else {
                    DispatchQueue.main.async {
                        self.messages.append("System: Critical Error. Please restart app.")
                        self.isLoading = false
                    }
                }
            }
        }
    }
    
    @MainActor
    private func handleResponse(_ rawResponse: String) {
        let cleanText = self.cleanResponse(rawResponse)
        self.messages.append("AI: \(cleanText)")
        
        if self.isLlama3 {
            self.chatHistory += "\(cleanText)<|eot_id|>"
        } else if self.isQwen {
            self.chatHistory += "\(cleanText)<|im_end|>\n"
        } else if self.isGemma {
            self.chatHistory += "\(cleanText)<end_of_turn>\n"
        } else if self.isPhi3 {
            self.chatHistory += "\(cleanText)<|end|>"
        } else {
            self.chatHistory += "\(cleanText)</s>"
        }
        
        self.isLoading = false
        
        // Auto-save if enabled
        if isAutoSaveEnabled {
            performAutoSave()
        }
    }
    
    func clearChat() {
        messages = ["System: Memory cleared."]
        let style = self.currentAnswerStyle()
        chatHistory = self.systemPrompt(for: style)
        isBotContextActive = false
        
        // Reset auto-save state
        isAutoSaveEnabled = false
        currentSessionId = nil
        
        if let url = modelURL {
            bot = LLM(from: url)
        }
    }

    func switchModelIfNeeded() {
        guard let selected = selectedModelURL else { return }
        if modelURL?.lastPathComponent != selected.lastPathComponent {
            modelURL = selected
            let style = self.currentAnswerStyle()
            chatHistory = self.systemPrompt(for: style)
            messages = ["System: Loading \(selected.lastPathComponent)..."]
            
            bot = LLM(from: selected)
            isBotContextActive = false
            
            if bot != nil { messages.append("System: Ready! Chat with me.") }
        }
    }
    
    private func currentAnswerStyle() -> String {
        UserDefaults.standard.string(forKey: "answerStyle") ?? "simple"
    }
    
    // MARK: - Chat History
    
    /// Creates a ChatSession from the current state for saving
    func createSavableSession(modelFilename: String) -> ChatSession {
        return ChatSession(
            id: UUID(),
            title: ChatSession.generateTitle(from: messages),
            messages: messages,
            modelFilename: modelFilename,
            createdAt: Date(),
            lastChatAt: Date()
        )
    }
    
    /// Loads a saved session, replacing current chat
    @MainActor
    func loadSession(_ session: ChatSession) {
        // Clear and replace messages with saved session
        self.messages = session.messages
        
        // Track this session for auto-save updates
        self.currentSessionId = session.id
        
        // Reset the bot context for the loaded session
        let style = currentAnswerStyle()
        self.chatHistory = systemPrompt(for: style)
        self.isBotContextActive = false
        
        // Re-initialize the bot if needed
        if let url = self.modelURL {
            self.bot = LLM(from: url)
        }
        
        // Force UI refresh by triggering objectWillChange
        self.objectWillChange.send()
    }
    
    /// Performs auto-save of current chat
    private func performAutoSave() {
        // Create or update session
        let sessionId = currentSessionId ?? UUID()
        
        // If this is a new session (first auto-save), store the ID
        if currentSessionId == nil {
            currentSessionId = sessionId
        }
        
        let session = ChatSession(
            id: sessionId,
            title: ChatSession.generateTitle(from: messages),
            messages: messages,
            modelFilename: currentModelFilename,
            createdAt: Date(),  // Will be ignored on update if session exists
            lastChatAt: Date()
        )
        
        ChatHistoryManager.shared.saveSession(session)
    }
}
