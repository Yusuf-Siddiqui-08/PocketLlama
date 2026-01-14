//
//  ModelListView.swift
//  PocketLlama
//
//  Created by Yusuf Siddiqui on 2026-01-12.
//

import SwiftUI

struct ModelListView: View {
    @EnvironmentObject var downloader: DownloadManager
    
    @State private var modelsOnly = false
    @State private var errorMessage: String? = nil
    @State private var storageStats: (used: Int64, total: Int64, modelsUsed: Int64)? = nil
    @State private var downloadedFilenames: Set<String> = []
    
    var body: some View {
        List {
            // Storage Header
            if let usage = storageStats {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Storage").font(.headline)
                        Spacer()
                        Text(modelsOnly ? "\(formatBytes(usage.modelsUsed)) by models of \(formatBytes(usage.total))" : "\(formatBytes(usage.used)) of \(formatBytes(usage.total)) used")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    ProgressView(value: Double(modelsOnly ? usage.modelsUsed : usage.used), total: Double(usage.total))
                    Toggle(isOn: $modelsOnly) { Text("Show models only") }.font(.caption)
                }
                .padding(.vertical, 8)
            } else {
                 ProgressView("Loading storage info...")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            
            // Model List
            ForEach(availableModels) { model in
                VStack(alignment: .leading, spacing: 12) {
                    // Top Row: Name and Status
                    HStack {
                        Text(model.name).font(.headline)
                        Spacer()
                        if downloadedFilenames.contains(model.filename) {
                            Text("Installed")
                                .font(.caption).bold()
                                .foregroundColor(.green)
                                .padding(4)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(6)
                        } else if downloader.activeDownloads.contains(model.filename) {
                            let p = downloader.progressByFile[model.filename] ?? 0
                            HStack(spacing: 6) {
                                ProgressView(value: p).frame(width: 80)
                                Text("\(Int(p * 100))%").font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // Main Content: Stats (Left) & Metrics/Actions (Right)
                    HStack(alignment: .top, spacing: 10) {
                        
                        // LEFT COLUMN: Hard Stats
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "internaldrive").frame(width: 16)
                                Text("~" + model.size)
                            }
                            HStack(spacing: 6) {
                                Image(systemName: "text.book.closed").frame(width: 16)
                                Text(model.context)
                            }
                            HStack(spacing: 6) {
                                Image(systemName: "cpu").frame(width: 16)
                                // Apply the dynamic color here
                                Text(model.computeLoad)
                                    .foregroundColor(computeColor(for: model.computeLoad))
                                    .bold()
                            }
                        }
                        .font(.caption).foregroundColor(.secondary)
                        
                        Spacer()
                        
                        // RIGHT COLUMN: Scores + Action Button
                        VStack(alignment: .trailing, spacing: 12) {
                            HStack(spacing: 16) {
                                ScoreView(title: "Speed", score: model.speed, color: .blue)
                                ScoreView(title: "IQ", score: model.accuracy, color: .purple)
                            }
                            Group {
                                if downloadedFilenames.contains(model.filename) {
                                    Button(role: .destructive) {
                                        downloader.uninstall(model: model)
                                        Task { await loadStorageData() }
                                    } label: {
                                        Text("Uninstall").font(.caption).frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered).controlSize(.small).frame(width: 120)
                                } else if downloader.activeDownloads.contains(model.filename) {
                                    Button("Cancel") {
                                        downloader.cancelDownload(model: model)
                                    }
                                    .buttonStyle(.borderedProminent).tint(.red).controlSize(.small).frame(width: 120)
                                } else {
                                    Button {
                                        downloader.download(model: model)
                                    } label: {
                                        Text("Download").font(.caption).bold().frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent).controlSize(.small).frame(width: 120)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            Section {
                NavigationLink(destination: SettingsView()) {
                    Label("Settings", systemImage: "gearshape")
                        .font(.body)
                        .foregroundColor(.primary)
                }
            }
        }
        .navigationTitle("Model Library")
        .onReceive(downloader.$errorMessage) { msg in
            if let msg = msg { self.errorMessage = msg }
        }
        .onChange(of: downloader.activeDownloads) { _, _ in
            Task { await loadStorageData() }
        }
        .task {
            await loadStorageData()
        }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
    
    // --- DATA LOADING ---
    private func loadStorageData() async {
        // Run heavy IO on background thread
        let result = await Task.detached(priority: .userInitiated) { () -> (stats: (used: Int64, total: Int64, modelsUsed: Int64)?, installed: Set<String>) in
            let stats = self.calculateDiskUsage()
            let modelsUsed = self.modelsUsageBytes()
            
            // Check installed models
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let files = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            let installed = Set(files.filter { $0.pathExtension.lowercased() == "gguf" }.map { $0.lastPathComponent })
            
            if let s = stats {
                return ((used: s.used, total: s.total, modelsUsed: modelsUsed), installed)
            }
            return (nil, installed)
        }.value
        
        // Update State on MainActor
        self.storageStats = result.stats
        self.downloadedFilenames = result.installed
    }

    // --- COLOR SCALE LOGIC ---
    private func computeColor(for load: String) -> Color {
        switch load {
        case "Light": return .green       // Ideal
        case "Low": return .yellow          // Good
        case "Medium": return .orange     // Warning
        case "High": return .red          // Hot
        case "Heavy": return .purple      // Extreme
        default: return .secondary
        }
    }
    
    // Disk Usage Helpers
    nonisolated private func modelsUsageBytes() -> Int64 {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let files = try? FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
        return files.filter { $0.pathExtension.lowercased() == "gguf" }
            .reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
    
    // Helper to guess the "Marketing" size (e.g. 128GB) from the "Logical" size (e.g. 108GB)
    nonisolated private func nearestStandardSize(_ bytes: Int64) -> Int64 {
        // Standard iPhone storage sizes in bytes (Decimal 1000^3, matching iOS Settings)
        let tiers: [Int64] = [
            64_000_000_000,  // 64 GB
            128_000_000_000, // 128 GB
            256_000_000_000, // 256 GB
            512_000_000_000, // 512 GB
            1_000_000_000_000, // 1 TB
            2_000_000_000_000  // 2 TB
        ]
        
        // Find the smallest tier that is larger than the reported bytes
        for tier in tiers {
            if tier > bytes {
                return tier
            }
        }
        return bytes // Fallback if it doesn't match a known tier
    }
    
    nonisolated private func calculateDiskUsage() -> (used: Int64, total: Int64)? {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // 1. Use 'ImportantUsageKey' to include purgeable space (more accurate free space)
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        
        guard let values = try? documentsURL.resourceValues(forKeys: keys),
              let logicalTotal = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else { return nil }
        
        // 2. Adjust total to match the Physical Device size (Marketing size)
        let physicalTotal = nearestStandardSize(Int64(logicalTotal))
        
        // 3. Recalculate 'Used' based on the Physical Total
        // Used = Physical Total - Available
        let used = physicalTotal - Int64(available)
        
        return (used: used, total: physicalTotal)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    // Helper View
    struct ScoreView: View {
        let title: String
        let score: Int
        let color: Color
        var body: some View {
            VStack(alignment: .trailing, spacing: 4) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(title).font(.caption2).foregroundColor(.secondary)
                    Text("\(score)").font(.caption).bold()
                }
                ProgressView(value: Double(score), total: 10).tint(color).frame(width: 50)
            }
        }
    }
}
