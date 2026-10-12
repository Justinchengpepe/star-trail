import SwiftUI

@main
struct NebulaPhotosApp: App {
    @StateObject private var library = PhotoLibraryModel()
    @State private var browsing = BrowsingState()
    @StateObject private var organization = PhotoOrganization()
    @StateObject private var playback = LivePhotoPlayback()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environment(browsing)
                .environmentObject(organization)
                .environmentObject(playback)
                .frame(minWidth: 920, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
