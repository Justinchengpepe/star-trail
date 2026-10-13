import SwiftUI
import AppKit

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
            CommandGroup(after: .appSettings) {
                Button("删除全部分析数据…") {
                    let alert = NSAlert()
                    alert.messageText = "删除全部本机分析数据？"
                    alert.informativeText = "将清除主题、识别文字、手动分类、事件命名和内存图片缓存。不会修改苹果相册原图。此操作无法撤销；备份中的历史副本不在清理范围内。"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "取消")
                    alert.addButton(withTitle: "删除分析数据")
                    if alert.runModal() == .alertSecondButtonReturn { library.clearAnalysisData() }
                }
                .disabled(organization.isClearing)
                Button("重新建立事件索引") { organization.resumeIndexing(library.photos) }
                    .disabled(!library.canReadLibrary || organization.isClearing)
            }
        }
    }
}
