import Foundation

/// 内置动作的唯一清单。Host、FinderSync、设置页和测试均从这里取得相同实例集合。
public enum DefaultActionRegistry {
    public static func makeActions() -> [MenuAction] {
        let newFileActions: [MenuAction] = SupportedFileType.allCases.map {
            NewFileAction(fileType: $0)
        }
        let fileManageActions: [MenuAction] = [
            FileManageAction(type: .cut),
            FileManageAction(type: .paste),
            FileManageAction(type: .permanentDelete),
            FileManageAction(type: .copyPath),
            FileManageAction(type: .copyName),
            FileManageAction(type: .copyTo),
            FileManageAction(type: .moveTo)
        ]
        let terminalActions: [MenuAction] = TerminalEditorType.allCases.map {
            TerminalOpenAction(type: $0)
        }
        let utilityActions: [MenuAction] = [
            UtilityAction(type: .calculateMD5),
            UtilityAction(type: .calculateSHA256),
            UtilityAction(type: .toggleHiddenFiles),
            UtilityAction(type: .textToQRCode),
            UtilityAction(type: .convertToPNG),
            UtilityAction(type: .convertToJPEG)
        ]

        return newFileActions + fileManageActions + terminalActions + utilityActions
    }

    @discardableResult
    public static func registerAll(into dispatcher: ActionDispatcher = .shared) -> [MenuAction] {
        let actions = makeActions()
        actions.forEach(dispatcher.register(action:))
        return actions
    }
}
