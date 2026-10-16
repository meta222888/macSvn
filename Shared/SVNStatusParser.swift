import Foundation

struct SVNStatusItem: Identifiable, Equatable {
    var id: String { path }
    var path: String
    var item: String
    var displayName: String
    var isCommitSelectable: Bool
    var isSelected: Bool
}

enum SVNStatusParser {
    static func parse(xml data: Data) throws -> [SVNStatusItem] {
        let parser = XMLStatusParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        guard xml.parse() else {
            throw NSError(
                domain: "SVNStatusParser",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: parser.errorMessage ?? "无法解析 svn status 输出"]
            )
        }
        return parser.items.map { mapItem($0) }
    }

    private static func mapItem(_ raw: (path: String, item: String)) -> SVNStatusItem {
        let item = raw.item
        switch item {
        case "modified":
            return SVNStatusItem(path: raw.path, item: item, displayName: "修改", isCommitSelectable: true, isSelected: true)
        case "added":
            return SVNStatusItem(path: raw.path, item: item, displayName: "新增", isCommitSelectable: true, isSelected: true)
        case "deleted":
            return SVNStatusItem(path: raw.path, item: item, displayName: "删除", isCommitSelectable: true, isSelected: true)
        case "replaced":
            return SVNStatusItem(path: raw.path, item: item, displayName: "替换", isCommitSelectable: true, isSelected: true)
        case "unversioned":
            // Selectable: will be `svn add`ed before commit when checked.
            return SVNStatusItem(path: raw.path, item: item, displayName: "未纳入版本控制", isCommitSelectable: true, isSelected: false)
        case "missing":
            return SVNStatusItem(path: raw.path, item: item, displayName: "文件缺失", isCommitSelectable: false, isSelected: false)
        case "conflicted":
            return SVNStatusItem(path: raw.path, item: item, displayName: "冲突", isCommitSelectable: false, isSelected: false)
        default:
            return SVNStatusItem(path: raw.path, item: item, displayName: item, isCommitSelectable: false, isSelected: false)
        }
    }
}

private final class XMLStatusParser: NSObject, XMLParserDelegate {
    var items: [(path: String, item: String)] = []
    var errorMessage: String?
    private var currentPath: String?
    private var currentItem: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "entry" {
            currentPath = attributeDict["path"]
            currentItem = nil
        } else if elementName == "wc-status" {
            currentItem = attributeDict["item"]
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "entry", let path = currentPath {
            let item = currentItem ?? "none"
            items.append((path: path, item: item))
            currentPath = nil
            currentItem = nil
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        errorMessage = parseError.localizedDescription
    }
}
