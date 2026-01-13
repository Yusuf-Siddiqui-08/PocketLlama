//
//  DownloadManager.swift
//  PocketLlama
//
//  Created by Yusuf Siddiqui on 2026-01-12.
//

import Foundation
import Combine

class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var progressByFile: [String: Float] = [:]
    @Published var activeDownloads: Set<String> = []
    @Published var errorMessage: String? = nil
    
    // Track tasks for cancellation
    private var activeTasks: [String: URLSessionDownloadTask] = [:]

    private func availableDiskSpace() -> Int64? {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityKey]
        guard let values = try? documentsURL.resourceValues(forKeys: keys),
              let available = values.volumeAvailableCapacity else {
            return nil
        }
        return Int64(available)
    }

    private func bytesRequired(for model: ModelOption) -> Int64? {
        let trimmed = model.size.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let components = trimmed.split(separator: " ")
        guard components.count == 2, let number = Double(components[0]) else { return nil }
        let unit = components[1]
        let bytes: Double
        if unit.hasPrefix("GB") {
            bytes = number * 1024.0 * 1024.0 * 1024.0
        } else if unit.hasPrefix("MB") {
            bytes = number * 1024.0 * 1024.0
        } else if unit.hasPrefix("KB") {
            bytes = number * 1024.0
        } else {
            bytes = number
        }
        return Int64(bytes)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    func download(model: ModelOption) {
        guard !activeDownloads.contains(model.filename), !model.isDownloaded else { return }

        if let required = bytesRequired(for: model), let available = availableDiskSpace() {
            if available < required {
                let need = formatBytes(required)
                let have = formatBytes(available)
                self.errorMessage = "Not enough storage. You need \(need) but only have \(have) available."
                return
            }
        }

        activeDownloads.insert(model.filename)
        progressByFile[model.filename] = 0.0

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue.main)
        let task = session.downloadTask(with: model.url)
        task.taskDescription = model.filename
        
        // Save task reference
        activeTasks[model.filename] = task
        
        task.resume()
    }
    
    func cancelDownload(model: ModelOption) {
        if let task = activeTasks[model.filename] {
            task.cancel()
        }
        activeTasks.removeValue(forKey: model.filename)
        activeDownloads.remove(model.filename)
        progressByFile.removeValue(forKey: model.filename)
        objectWillChange.send()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let filename = downloadTask.taskDescription, totalBytesExpectedToWrite > 0 else { return }
        progressByFile[filename] = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
        objectWillChange.send()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let filename = downloadTask.taskDescription else { return }
        let destinationURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(filename)
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: location, to: destinationURL)
            DispatchQueue.main.async {
                self.activeDownloads.remove(filename)
                self.activeTasks.removeValue(forKey: filename)
                self.progressByFile[filename] = 1.0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.progressByFile.removeValue(forKey: filename)
                }
                // Notify observers that file system changed
                self.objectWillChange.send()
            }
        } catch {
            DispatchQueue.main.async {
                self.activeDownloads.remove(filename)
                self.activeTasks.removeValue(forKey: filename)
                self.progressByFile.removeValue(forKey: filename)
                self.errorMessage = "Download finished but couldn't be saved: \(error.localizedDescription)"
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error else { return }
        
        // Ignore "cancelled" errors
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return
        }
        
        let filename = task.taskDescription
        if let filename = filename {
            activeTasks.removeValue(forKey: filename)
            activeDownloads.remove(filename)
            progressByFile.removeValue(forKey: filename)
        }
        self.errorMessage = "Download failed. Please check your internet. (\(error.localizedDescription))"
    }

    func uninstall(model: ModelOption) {
        let fileURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(model.filename)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        activeDownloads.remove(model.filename)
        progressByFile.removeValue(forKey: model.filename)
        
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
}
