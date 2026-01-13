import SwiftUI

struct ContentView: View {
    // Initialize the Source of Truth here
    @StateObject private var downloadManager = DownloadManager()
    
    @AppStorage("appAppearance") private var appAppearance: String = "system"
    private var preferredScheme: ColorScheme? {
        switch appAppearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil // system
        }
    }
    
    var body: some View {
        TabView {
            // Tab 1: Library
            ModelListView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }
            
            // Tab 2: Chat
            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "message.fill")
                }
            
            // Tab 3: Settings
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .preferredColorScheme(preferredScheme)
        // Inject the manager into the environment for all child views
        .environmentObject(downloadManager)
    }
}

#Preview {
    ContentView()
}
