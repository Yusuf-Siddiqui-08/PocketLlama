//
//  ModelOption.swift
//  PocketLlama
//
//  Created by Yusuf Siddiqui on 2026-01-12.
//

import Foundation

struct ModelOption: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let filename: String
    let url: URL
    let size: String
    let context: String
    let speed: Int          // 1-10
    let accuracy: Int       // 1-10
    let computeLoad: String // "Light", "Medium", etc.
    
    var isDownloaded: Bool {
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: path.path)
    }
}

let availableModels = [
    // --- RECOMMENDED STARTING MODELS ---
    
    // 1. Gemma 3 270M (Fixed URL)
    ModelOption(
        name: "Gemma 3 270M",
        filename: "google_gemma-3-270m-it-Q4_K_M.gguf",
        url: URL(string: "https://huggingface.co/bartowski/google_gemma-3-270m-it-GGUF/resolve/main/google_gemma-3-270m-it-Q4_K_M.gguf?download=true")!,
        size: "180 MB",
        context: "32k",
        speed: 10,
        accuracy: 5,
        computeLoad: "Light"
    ),
    
    // 2. Gemma 3 1B (Fixed URL)
    ModelOption(
        name: "Gemma 3 1B",
        filename: "google_gemma-3-1b-it-Q4_K_M.gguf",
        url: URL(string: "https://huggingface.co/bartowski/google_gemma-3-1b-it-GGUF/resolve/main/google_gemma-3-1b-it-Q4_K_M.gguf?download=true")!,
        size: "800 MB",
        context: "128k",
        speed: 9,
        accuracy: 7,
        computeLoad: "Low"
    ),
    
    // 3. Qwen 2.5 0.5B
    ModelOption(
        name: "Qwen 2.5 0.5B",
        filename: "Qwen2.5-0.5B-Instruct-Q4_K_M.gguf",
        url: URL(string: "https://huggingface.co/bartowski/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf?download=true")!,
        size: "400 MB",
        context: "32k",
        speed: 10,
        accuracy: 6,
        computeLoad: "Light"
    ),
    
    // 4. Llama 3.2 3B
    ModelOption(
        name: "Llama 3.2 3B",
        filename: "Llama-3.2-3B-Instruct-Q4_K_M.gguf",
        url: URL(string: "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf?download=true")!,
        size: "2.0 GB",
        context: "128k",
        speed: 6,
        accuracy: 9,
        computeLoad: "Medium"
    ),

    // --- LEGACY MODELS ---
    
    // 5. TinyLlama 1.1B
    ModelOption(
        name: "TinyLlama 1.1B",
        filename: "tinyllama-1.1b-chat.Q4_K_M.gguf",
        url: URL(string: "https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf?download=true")!,
        size: "636 MB",
        context: "2k",
        speed: 9,
        accuracy: 4,
        computeLoad: "Low"
    ),
    
    // 6. Phi-3 Mini
    ModelOption(
        name: "Phi-3 Mini",
        filename: "Phi-3-mini-4k.gguf",
        url: URL(string: "https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/Phi-3-mini-4k-instruct-q4.gguf?download=true")!,
        size: "2.4 GB",
        context: "4k",
        speed: 5,
        accuracy: 8,
        computeLoad: "High"
    )
]

func installedModels() -> [ModelOption] {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let files = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
    let ggufs = Set(files.filter { $0.pathExtension.lowercased() == "gguf" }.map { $0.lastPathComponent })
    // Return available models that are actually present on disk
    return availableModels.filter { ggufs.contains($0.filename) }
}
