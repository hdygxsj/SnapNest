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
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Picker("办公工具", selection: $model.page) {
                    Text("图文教程").tag(0); Text("暂存篮").tag(1); Text("工作现场").tag(2); Text("截图对比").tag(3)
                }.pickerStyle(.segmented)
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
