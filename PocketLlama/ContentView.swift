import SwiftUI

enum TabItem: Hashable {
    case library, chat, settings
}

struct ContentView: View {
    @StateObject private var downloadManager = DownloadManager()
    @State private var selectedTab: TabItem? = .library
    @AppStorage("appAppearance") private var appAppearance: String = "system"

    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                IPadSidebarLayout()
            } else {
                IPhoneTabLayout(selectedTab: $selectedTab)
            }
        }
        .preferredColorScheme(appAppearance == "light" ? .light : (appAppearance == "dark" ? .dark : nil))
        .environmentObject(downloadManager)
    }
}

// MARK: - iPad Two-Column Layout
struct IPadSidebarLayout: View {
    var body: some View {
        NavigationSplitView {
            // Sidebar: Wrap in a stack so title and toolbars work
            NavigationStack {
                ModelListView()
            }
        } detail: {
            // Main Content: This NavigationStack forces the chat to fill the space
            NavigationStack {
                ChatView()
                    .frame(maxWidth: .infinity) // Ensures it stretches to fill the right side
            }
        }
        // Use default split view style for compatibility across iOS versions
    }
}

// MARK: - iPhone Layout (Modified for missing NavigationViews)
struct IPhoneTabLayout: View {
    @Binding var selectedTab: TabItem?
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // On iPhone, we must add NavigationStacks back since we removed them from the sub-views
            NavigationStack { ModelListView() }
                .tabItem { Label("Library", systemImage: "books.vertical") }
                .tag(TabItem.library as TabItem?)
            
            NavigationStack { ChatView() }
                .tabItem { Label("Chat", systemImage: "message.fill") }
                .tag(TabItem.chat as TabItem?)
            
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(TabItem.settings as TabItem?)
        }
    }
}

#Preview {
    ContentView()
}
