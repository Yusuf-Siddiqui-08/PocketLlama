import SwiftUI

enum TabItem: Hashable {
    case library, chat, history, settings
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
        .onReceive(NotificationCenter.default.publisher(for: .loadChatSession)) { _ in
            // Switch to chat tab when a session is loaded
            selectedTab = .chat
        }
    }
}

// MARK: - iPad Two-Column Layout
struct IPadSidebarLayout: View {
    @State private var selectedView: String? = "chat"
    
    var body: some View {
        NavigationSplitView {
            // Sidebar with navigation options
            List(selection: $selectedView) {
                NavigationLink(value: "library") {
                    Label("Library", systemImage: "books.vertical")
                }
                NavigationLink(value: "chat") {
                    Label("Chat", systemImage: "message.fill")
                }
                NavigationLink(value: "history") {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                NavigationLink(value: "settings") {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            .navigationTitle("PocketLlama")
        } detail: {
            NavigationStack {
                switch selectedView {
                case "library":
                    ModelListView()
                case "chat":
                    ChatView()
                case "history":
                    ChatHistoryView()
                case "settings":
                    SettingsView()
                default:
                    ChatView()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .loadChatSession)) { _ in
            // Switch to chat view when a session is loaded
            selectedView = "chat"
        }
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
            
            NavigationStack { ChatHistoryView() }
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(TabItem.history as TabItem?)
            
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(TabItem.settings as TabItem?)
        }
    }
}

#Preview {
    ContentView()
}
