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
    
    var body: some View {
        NavigationView {
            List {
                // Storage Header
                if let usage = diskUsage() {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Storage").font(.headline)
                            Spacer()
                            Text(modelsOnly ? "\(formatBytes(usedBytesForBar(usage: usage))) by models of \(formatBytes(usage.total))" : "\(formatBytes(usedBytesForBar(usage: usage))) of \(formatBytes(usage.total)) used")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        ProgressView(value: Double(usedBytesForBar(usage: usage)), total: Double(usage.total))
                        Toggle(isOn: $modelsOnly) { Text("Show models only") }.font(.caption)
                    }
                    .padding(.vertical, 8)
                }
                
                // Model List
                ForEach(availableModels) { model in
                    VStack(alignment: .leading, spacing: 12) {
                        // Top Row: Name and Status
                        HStack {
                            Text(model.name).font(.headline)
                            Spacer()
                            if model.isDownloaded {
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
                                    if model.isDownloaded {
                                        Button(role: .destructive) {
                                            downloader.uninstall(model: model)
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
            }
            .navigationTitle("Model Library")
            .onReceive(downloader.$errorMessage) { msg in
                if let msg = msg { self.errorMessage = msg }
            }
            .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
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
    private func modelsUsageBytes() -> Int64 {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let files = try? FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
        return files.filter { $0.pathExtension.lowercased() == "gguf" }
            .reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
    
    private func usedBytesForBar(usage: (used: Int64, total: Int64)) -> Int64 {
        let used = modelsOnly ? modelsUsageBytes() : usage.used
        return min(used, usage.total)
    }
    
    // Helper to guess the "Marketing" size (e.g. 128GB) from the "Logical" size (e.g. 108GB)
        private func nearestStandardSize(_ bytes: Int64) -> Int64 {
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

        private func diskUsage() -> (used: Int64, total: Int64)? {
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
