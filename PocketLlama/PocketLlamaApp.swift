//
//  PocketLlamaApp.swift
//  PocketLlama
//
//  Created by Yusuf Siddiqui on 2026-01-11.
//

import SwiftUI

@main
struct PocketLlamaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(after: .newItem) {
                Divider()
                
                Button(action: { ChatViewModel.shared.isAutoSaveEnabled.toggle() }) {
                    if ChatViewModel.shared.isAutoSaveEnabled {
                        Label("Auto-Save", systemImage: "checkmark")
                    } else {
                        Text("Auto-Save")
                    }
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
                
                Button("Save Chat") {
                    let session = ChatViewModel.shared.createSavableSession(
                        modelFilename: UserDefaults.standard.string(forKey: "currentModelFilename") ?? ""
                    )
                    ChatHistoryManager.shared.saveSession(session)
                }
                .keyboardShortcut("s", modifiers: .command)
                
                Divider()
                
                Button("Delete Chat", role: .destructive) {
                    ChatViewModel.shared.showDeleteConfirmation = true
                }
                .keyboardShortcut(.delete, modifiers: .command)
            }
        }
    }
}
