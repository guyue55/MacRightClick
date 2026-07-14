import AppKit
import SwiftUI

/// File Provider 降级入口的轻量动作面板。
/// 动作显隐已由 FinderServiceCatalog 决定，本视图只负责展示和选择。
struct FinderServicePaletteView: View {
    let items: [FinderServiceActionItem]
    let selectionSummary: String
    let onSelect: (String) -> Void

    @State private var query = ""
    @State private var scope: FinderServicePaletteScope = .all

    private var sections: [FinderServicePaletteSection] {
        FinderServicePaletteBuilder.sections(items: items, scope: scope, query: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(selectionSummary)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(items.count) 个可用动作")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            Picker("动作分类", selection: $scope) {
                ForEach(FinderServicePaletteScope.allCases) { item in
                    Text(item.localizedName).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if sections.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                    Text(query.isEmpty ? "这个分类暂无可用动作" : "没有匹配的动作")
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(sections) { section in
                        Section(section.title) {
                            ForEach(section.items) { item in
                                actionButton(item)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .searchable(text: $query, prompt: "搜索动作")
        .frame(minWidth: 420, idealWidth: 460, minHeight: 360, idealHeight: 520)
    }

    private func actionButton(_ item: FinderServiceActionItem) -> some View {
        Button {
            onSelect(item.actionID)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.iconName ?? "gearshape")
                    .foregroundStyle(item.isHighRisk ? Color.orange : Color.accentColor)
                    .frame(width: 20, height: 20)

                Text(item.title)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)

                if item.isHighRisk {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .help("高级动作")
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
    }
}

@MainActor
final class FinderServicePaletteController: NSObject {
    static let shared = FinderServicePaletteController()

    private let panel: NSPanel

    private override init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.title = "右键助手"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 420, height: 360)
        panel.maxSize = NSSize(width: 620, height: 720)
    }

    func show(
        items: [FinderServiceActionItem],
        selectedPaths: [String],
        onSelect: @escaping (String) -> Void
    ) {
        let summary = Self.selectionSummary(paths: selectedPaths)
        let content = FinderServicePaletteView(
            items: items,
            selectionSummary: summary,
            onSelect: { [weak self] actionID in
                self?.panel.orderOut(nil)
                onSelect(actionID)
            }
        )
        panel.contentView = NSHostingView(rootView: content)
        positionNearPointer()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private static func selectionSummary(paths: [String]) -> String {
        guard paths.count == 1, let path = paths.first else {
            return "已选择 \(paths.count) 个项目"
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private func positionNearPointer() {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) else {
            panel.center()
            return
        }

        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: min(max(pointer.x - size.width / 2, visible.minX), visible.maxX - size.width),
            y: min(max(pointer.y - size.height + 36, visible.minY), visible.maxY - size.height)
        )
        panel.setFrameOrigin(origin)
    }
}
