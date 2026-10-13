import SwiftUI

private struct PhotoBrowserModeKey: FocusedValueKey {
    typealias Value = Binding<GalleryMode>
}

private struct PhotoSearchActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var photoBrowserMode: Binding<GalleryMode>? {
        get { self[PhotoBrowserModeKey.self] }
        set { self[PhotoBrowserModeKey.self] = newValue }
    }
    var focusPhotoSearch: (() -> Void)? {
        get { self[PhotoSearchActionKey.self] }
        set { self[PhotoSearchActionKey.self] = newValue }
    }
}

/// Scene-scoped native commands work in the active window, without a global
/// key monitor that could swallow typing, system keys, or detail-view gestures.
struct PhotoBrowserCommands: Commands {
    @ObservedObject var library: PhotoLibraryModel
    @FocusedValue(\.photoBrowserMode) private var mode
    @FocusedValue(\.focusPhotoSearch) private var focusSearch

    var body: some Commands {
        CommandMenu("浏览") {
            Button("搜索照片") { focusSearch?() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(focusSearch == nil || mode == nil)
            Divider()
            ForEach(GalleryMode.allCases) { item in
                Button {
                    withAnimation(.easeOut(duration: 0.24)) { mode?.wrappedValue = item }
                } label: {
                    if mode?.wrappedValue == item {
                        Label(item.rawValue, systemImage: "checkmark")
                    } else { Text(item.rawValue) }
                }
                .keyboardShortcut(item.shortcut, modifiers: .command)
                .disabled(mode == nil)
            }
        }
        CommandMenu("图库") {
            Button("刷新照片") { library.refresh() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!library.canReadLibrary || library.isLoading)
            Button(library.isAnalyzing ? "停止识别照片主题" : "识别全部照片主题") {
                library.isAnalyzing ? library.cancelAnalysis() : library.analyzeThemes()
            }
            .disabled(!library.canReadLibrary || library.photos.isEmpty)
        }
    }
}
