import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TutorialWorkspace: View {
    @ObservedObject var store: TutorialStore
    @Environment(\.colorScheme) private var scheme
    @State private var editing: TutorialEditing?
    @State private var deletion: TutorialDeletion?
    @State private var confirmDeletion = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("图文教程").font(.title2.bold())
                Spacer()
                Button("新建", systemImage: "plus") { store.perform { try store.create() } }
            }
            Text("图片保存在本机；添加步骤、标注并导出 PDF 或长图。").font(.caption).foregroundStyle(.secondary)
            if !store.projects.isEmpty {
                Picker("教程", selection: $store.selectedID) {
                    ForEach(store.projects) { project in Text(project.title).tag(Optional(project.id)) }
                }
            }
            if let project = store.selected {
                TextField("教程标题", text: Binding(get: { store.selected?.title ?? "" }, set: { title in store.perform { try store.rename(project.id, title: title) } }))
                HStack {
                    Button("导入图片", systemImage: "photo.badge.plus") { pick(project.id) }
                    Button("截图添加", systemImage: "viewfinder") { store.beginCapture() }
                    Menu("导出") {
                        Button("PDF（每步一页）") { export(project.id, pdf: true) }
                        Button("长图 PNG") { export(project.id, pdf: false) }
                    }.disabled(project.steps.isEmpty)
                    Spacer()
                    Button("删除教程", role: .destructive) { deletion = TutorialDeletion(project: project.id, step: nil); confirmDeletion = true }
                }.controlSize(.small)
                if project.steps.isEmpty {
                    ContentUnavailableView("还没有步骤", systemImage: "list.number", description: Text("导入图片或截图，开始制作教程。"))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(Array(project.steps.enumerated()), id: \.element.id) { index, step in
                                stepCard(project, step: step, index: index)
                            }
                        }
                    }
                }
            } else { ContentUnavailableView("创建第一份教程", systemImage: "doc.richtext", description: Text("将操作过程整理为编号图文步骤。")) }
            if let message = store.message { Text(message).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
        }
        .tint(WorkspaceTheme.accent(scheme))
        .confirmationDialog("永久删除所选内容及其本地图片？", isPresented: $confirmDeletion, titleVisibility: .visible) {
            Button("永久删除", role: .destructive) {
                guard let target = deletion else { return }
                store.perform {
                    if let step = target.step { try store.remove(target.project, step: step) }
                    else { try store.removeProject(target.project) }
                }
                deletion = nil
            }
            Button("取消", role: .cancel) { deletion = nil }
        } message: { Text("此操作无法撤销，导入前的原始文件不受影响。") }
        .sheet(item: $editing) { value in
            TutorialAnnotationEditor(document: value.document, error: store.message) {
                guard let image = value.document.render() else { store.message = "标注渲染失败。"; return }
                store.perform { try store.add(image, project: value.project, replacing: value.step) }
                if store.message == nil { editing = nil }
            } cancel: { editing = nil }
            .onAppear { store.panelActivity?(true) }
            .onDisappear { store.panelActivity?(false) }
        }
    }
    private func stepCard(_ project: TutorialProject, step: TutorialStep, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("步骤 \(index + 1)").font(.headline)
                Spacer()
                Button { store.perform { try store.move(project.id, step: step.id, offset: -1) } } label: { Image(systemName: "arrow.up") }.disabled(index == 0).help("上移步骤")
                Button { store.perform { try store.move(project.id, step: step.id, offset: 1) } } label: { Image(systemName: "arrow.down") }.disabled(index == project.steps.count - 1).help("下移步骤")
                Button("标注") {
                    if let image = store.image(step) { editing = TutorialEditing(project: project.id, step: step.id, document: EditorDocument(image: image)) }
                    else { store.message = "图片丢失，无法标注。" }
                }
                Button("替换") { pick(project.id, replacing: step.id) }
                Button(role: .destructive) { deletion = TutorialDeletion(project: project.id, step: step.id); confirmDeletion = true } label: { Image(systemName: "trash") }.help("删除步骤")
            }.controlSize(.small)
            if let image = store.image(step) {
                Image(decorative: image, scale: 1).resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 190)
            } else { Label("图片丢失，请替换图片", systemImage: "exclamationmark.triangle").foregroundStyle(.orange).frame(height: 80) }
            TextField("添加操作说明（最多 500 字）", text: Binding(get: {
                store.projects.first(where: { $0.id == project.id })?.steps.first(where: { $0.id == step.id })?.caption ?? ""
            }, set: { text in store.perform { try store.caption(project.id, step: step.id, text: text) } }), axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder)
        }.padding(12).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }
    private func pick(_ project: UUID, replacing: UUID? = nil) {
        store.panelActivity?(true); defer { store.panelActivity?(false) }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = replacing == nil
        if panel.runModal() == .OK {
            store.perform { for url in panel.urls { try store.importImage(url, project: project, replacing: replacing) } }
        }
    }
    private func export(_ project: UUID, pdf: Bool) {
        store.panelActivity?(true); defer { store.panelActivity?(false) }
        let panel = NSSavePanel(); panel.allowedContentTypes = pdf ? [.pdf] : [.png]
        panel.nameFieldStringValue = "教程.\(pdf ? "pdf" : "png")"
        if panel.runModal() == .OK, let url = panel.url { store.perform { try store.export(project, to: url, pdf: pdf) } }
    }
}

private struct TutorialEditing: Identifiable {
    let id = UUID()
    let project: UUID
    let step: UUID
    let document: EditorDocument
}
private struct TutorialAnnotationEditor: View {
    @ObservedObject var document: EditorDocument
    var error: String?
    var save: () -> Void
    var cancel: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Picker("工具", selection: $document.tool) { ForEach(EditorTool.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 140)
                ColorPicker("颜色", selection: $document.color).labelsHidden()
                Slider(value: $document.lineWidth, in: 1...16).frame(width: 80)
                Button("撤销") { document.undo() }
                Button("重做") { document.redo() }
                Spacer()
                Button("取消", action: cancel)
                Button("保存标注", action: save).buttonStyle(.borderedProminent)
            }
            GeometryReader { geometry in
                let scale = min(geometry.size.width / CGFloat(document.image.width), geometry.size.height / CGFloat(document.image.height))
                EditorCanvas(document: document, cancel: cancel, save: save)
                    .frame(width: CGFloat(document.image.width) * scale, height: CGFloat(document.image.height) * scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            Text("保存后标注合并到步骤图片；关闭前可撤销。\(document.message)").font(.caption).foregroundStyle(.secondary)
        }.padding().frame(width: 800, height: 580)
    }
}

private struct TutorialDeletion { let project: UUID; let step: UUID? }
