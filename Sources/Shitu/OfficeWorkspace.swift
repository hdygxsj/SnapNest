import SwiftUI

@MainActor final class OfficeModel: ObservableObject {
    let tutorials = TutorialStore()
    let shelf = FileShelfStore()
    let scenes = WorkSceneStore()
    let comparison = ComparisonStore()
    @Published var page = 0
}
struct OfficeWorkspace: View {
    @ObservedObject var model: OfficeModel
    @ObservedObject private var pro = ProStore.shared
    var upgrade: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Picker("办公工具", selection: $model.page) {
                    Text("图文教程").tag(0); Text("暂存篮").tag(1); Text("工作现场").tag(2); Text("截图对比").tag(3)
                }.pickerStyle(.segmented)
                Text("PRO").font(.caption.bold()).foregroundStyle(.secondary)
            }
            if !pro.isPro {
                HStack {
                    Text("Pro 办公工具 · 本地处理，已有资料可查看").font(.caption)
                    Spacer(); Button("查看 Pro") { upgrade() }.buttonStyle(.borderedProminent)
                }.padding(10).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            Group {
                switch model.page {
                case 0: TutorialWorkspace(store: model.tutorials)
                case 1: FileShelfWorkspace(store: model.shelf)
                case 2: WorkScenesWorkspace(store: model.scenes)
                default: ComparisonWorkspace(store: model.comparison)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.padding(22)
    }
}
