//
//  SettingsView.swift
//  PocketLlama
//
//  Created by Yusuf Siddiqui on 2026-01-12.
//

import SwiftUI
import Combine

struct SettingsView: View {
    let onBack: (() -> Void)?
    @AppStorage("currentModelFilename") private var currentModelFilename: String = ""
    @AppStorage("answerStyle") private var answerStyle: String = "simple"
    @AppStorage("appAppearance") private var appAppearance: String = "system"
    
    @EnvironmentObject var downloadManager: DownloadManager
    
    // Store the models in State so we don't hit the disk constantly
    @State private var cachedModels: [ModelOption] = []
    
    init(onBack: (() -> Void)? = nil) {
        self.onBack = onBack
    }
    
    var body: some View {
        Form {
            if !cachedModels.isEmpty {
                Section(header: Text("Current model"), footer: Text("This model will be used for new chats.")) {
                    Picker("Current model", selection: $currentModelFilename) {
                        ForEach(cachedModels) { model in
                            Text(model.name).tag(model.filename)
                        }
                    }
                }
            } else {
                Section(footer: Text("Download a model in the Library tab to select it here.")) {
                    EmptyView()
                }
            }
            
            Section(header: Text("Appearance"), footer: Text("Choose Light or Dark, or follow System setting.")) {
                Picker("Appearance", selection: $appAppearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }
            
            Section(header: Text("Answer Style")) {
                Picker("Answer Style", selection: $answerStyle) {
                    Text("Simple answers").tag("simple")
                    Text("Detailed answers").tag("detailed")
                }
                .pickerStyle(.segmented)
                Text(answerStyle == "simple" ? "Responses will be concise and easy to understand." : "Responses will be comprehensive and in-depth.")
                    .font(.footnote).foregroundColor(.secondary)
            }
            
            Section(footer: Text("Changes apply to new chats. Use the trash icon in Chat to clear and restart with the selected style.")) {
                EmptyView()
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            if let onBack = onBack {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        onBack()
                    } label: {
                        Label("Back to Chat", systemImage: "chevron.backward")
                    }
                }
            }
        }
        .onAppear {
            refreshModelList()
            validateSelection()
        }
        .onReceive(downloadManager.objectWillChange) { _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)
                refreshModelList()
                validateSelection()
            }
        }
    }
    
    // Helper to load models once
    @MainActor
    private func refreshModelList() {
        cachedModels = installedModels()
    }
    
    private func validateSelection() {
        if cachedModels.isEmpty {
            currentModelFilename = ""
        } else {
            if !cachedModels.contains(where: { $0.filename == currentModelFilename }) {
                currentModelFilename = cachedModels[0].filename
            }
        }
    }
}
