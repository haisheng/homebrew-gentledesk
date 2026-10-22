import Foundation
import AppKit
import CryptoKit

enum HostError: Error { case message(String) }
let fm = FileManager.default
let input = FileHandle.standardInput
let output = FileHandle.standardOutput
let support = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/DeskAssit", isDirectory: true)
let selectionFile = support.appendingPathComponent("selection.json")
let searchSelectionFile = support.appendingPathComponent("search-folders.json")
let binaryDirectory = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent()

func readExactly(_ count: Int) throws -> Data? {
    var data = Data()
    while data.count < count {
        let chunk = try input.read(upToCount: count - data.count) ?? Data()
        if chunk.isEmpty { if data.isEmpty { return nil }; throw HostError.message("消息被截断。") }
        data.append(chunk)
    }
    return data
}
func frame(_ object: [String: Any]) throws -> Data {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    guard data.count <= 1_000_000 else { throw HostError.message("桌面项目过多，请缩小同步范围。") }
    var count = UInt32(data.count).littleEndian
    var result = withUnsafeBytes(of: &count) { Data($0) }
    result.append(data)
    return result
}
func send(_ object: [String: Any]) { if let data = try? frame(object) { try? output.write(contentsOf: data) } }
func itemID(_ url: URL) -> String { SHA256.hash(data: Data(url.standardizedFileURL.path.utf8)).map { String(format: "%02x", $0) }.joined() }
func roots() throws -> [URL] {
    guard let data = try? Data(contentsOf: selectionFile), let saved = try? JSONSerialization.jsonObject(with: data) as? [String: String], let path = saved["path"], path.hasPrefix("/") else { throw HostError.message("尚未选择桌面，请在连接向导中重新选择。") }
    var root = URL(fileURLWithPath: path, isDirectory: true)
    if let encoded = saved["bookmark"], let bookmark = Data(base64Encoded: encoded) {
        var stale = false
        if let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) { root = resolved; _ = root.startAccessingSecurityScopedResource() }
    }
    guard (try? root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { throw HostError.message("已选择的桌面不可访问，请重新选择并授权。") }
    return [root.standardizedFileURL]
}
func children(_ root: URL) throws -> [URL] {
    try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isApplicationKey, .isHiddenKey], options: [.skipsHiddenFiles]).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }.prefix(250).map { $0 }
}
func iconData(_ path: String) -> String {
    let image = NSWorkspace.shared.icon(forFile: path)
    let size = NSSize(width: 32, height: 32)
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return "" }
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]), data.count < 6000 else { return "" }
    return "data:image/png;base64," + data.base64EncodedString()
}
func inventory(_ selected: [URL], includeIcons: Bool = true) throws -> [[String: String]] {
    var items: [[String: String]] = []
    for root in selected {
        for url in try children(root) {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isApplicationKey])
            let kind = values?.isApplication == true ? "app" : values?.isDirectory == true ? "folder" : "file"
            items.append(["id": itemID(url), "name": fm.displayName(atPath: url.path), "kind": kind, "icon": includeIcons ? iconData(url.path) : ""])
            if items.count == 250 { break }
        }
    }
    if let data = try? JSONSerialization.data(withJSONObject: items), data.count > 850_000 { items = items.map { var item = $0; item["icon"] = ""; return item } }
    return items
}
func configure() throws -> [String: Any] {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    NSApp.activate(ignoringOtherApps: true)
    let panel = NSOpenPanel()
    panel.title = "GentleDesk · 选择要同步的桌面"
    panel.message = "仅读取此文件夹内项目的名称、类型和图标。不会读取文档内容，也不会修改或删除文件。本地搜索需另行授权目录。"
    panel.prompt = "选择并同步"
    panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
    panel.directoryURL = fm.urls(for: .desktopDirectory, in: .userDomainMask).first
    guard panel.runModal() == .OK, let url = panel.url else { throw HostError.message("已取消选择，没有读取桌面。") }
    // Validate access before persisting the selection.
    let items = try inventory([url])
    try fm.createDirectory(at: support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let bookmark = (try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil))?.base64EncodedString() ?? ""
    let saved = try JSONSerialization.data(withJSONObject: ["path": url.standardizedFileURL.path, "bookmark": bookmark])
    try saved.write(to: selectionFile, options: .atomic)
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: selectionFile.path)
    return ["ok": true, "items": items]
}
func resolve(_ id: String, selected: [URL]) throws -> URL {
    guard id.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw HostError.message("无效的本地入口。") }
    for root in selected { for url in try children(root) { if itemID(url) == id { return url } } }
    throw HostError.message("项目已移动或删除，请重新同步桌面。")
}
// Searches only user-selected folders and known application directories. No document contents are read.
func configureSearch() throws -> [String: Any] {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory); NSApp.activate(ignoringOtherApps: true)
    let panel = NSOpenPanel()
    panel.title = "GentleDesk · 选择文件搜索范围"
    panel.message = "搜索所选文件夹及子文件夹的名称和位置，并搜索系统应用目录。不读取文档正文，不上传结果。最多选择 5 个文件夹。"
    panel.prompt = "允许本地搜索"
    panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = true
    panel.directoryURL = fm.urls(for: .desktopDirectory, in: .userDomainMask).first
    guard panel.runModal() == .OK else { throw HostError.message("已取消选择，没有读取桌面。") }
    guard !panel.urls.isEmpty, panel.urls.count <= 5 else { throw HostError.message("最多选择 5 个搜索文件夹。") }
    var saved: [[String: String]] = []
    for url in panel.urls {
        let canonical = url.resolvingSymlinksInPath().standardizedFileURL
        let bookmark = (try? canonical.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil))?.base64EncodedString() ?? ""
        saved.append(["path": canonical.path, "bookmark": bookmark])
    }
    try fm.createDirectory(at: support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try JSONSerialization.data(withJSONObject: saved).write(to: searchSelectionFile, options: .atomic)
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: searchSelectionFile.path)
    return ["ok": true, "folders": saved.count]
}
func searchAllowedRoots() -> [(URL, Bool)] {
    var allowed: [(URL, Bool)] = []
    for path in ["/Applications", "/System/Applications", "/System/Cryptexes/App/System/Applications", fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path] {
        let url = URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
        if fm.fileExists(atPath: url.path) { allowed.append((url, true)) }
    }
    if let data = try? Data(contentsOf: searchSelectionFile), let saved = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
        for item in saved.prefix(5) {
            guard let path = item["path"], path.hasPrefix("/") else { continue }
            var url = URL(fileURLWithPath: path, isDirectory: true)
            if let encoded = item["bookmark"], let bookmark = Data(base64Encoded: encoded) {
                var stale = false
                if let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) { url = resolved; _ = url.startAccessingSecurityScopedResource() }
            }
            allowed.append((url.resolvingSymlinksInPath().standardizedFileURL, false))
        }
    }
    return allowed
}
func inside(_ url: URL, root: URL) -> Bool { let path = url.standardizedFileURL.path; let base = root.standardizedFileURL.path; return path == base || path.hasPrefix(base.hasSuffix("/") ? base : base + "/") }
func searchLocal(_ query: String, allowed: [(URL, Bool)]? = nil) throws -> [[String: String]] {
    let words = query.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: { $0.isWhitespace }).map(String.init)
    guard query.count <= 100, !words.isEmpty else { return [] }
    let deadline = Date().addingTimeInterval(1.5)
    var results: [[String: String]] = [], seen = Set<String>(), visited = 0
    for (root, applicationsOnly) in allowed ?? searchAllowedRoots() {
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isApplicationKey, .isSymbolicLinkKey, .isHiddenKey], options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _,_ in true }) else { continue }
        while let raw = enumerator.nextObject() as? URL {
            visited += 1
            if visited > 12000 || Date() > deadline { return results }
            let info = try? raw.resourceValues(forKeys: [.isDirectoryKey, .isApplicationKey, .isSymbolicLinkKey])
            if info?.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            let url = raw.standardizedFileURL
            guard url.resolvingSymlinksInPath().path == url.path, inside(url, root: root), !seen.contains(url.path) else { continue }
            let isApp = info?.isApplication == true
            if applicationsOnly && !isApp { continue }
            let name = fm.displayName(atPath: url.path)
            guard words.allSatisfy({ name.localizedStandardContains($0) }) else { continue }
            seen.insert(url.path)
            results.append(["id": itemID(url), "name": name, "kind": isApp ? "app" : info?.isDirectory == true ? "folder" : "file", "path": url.path])
            if results.count >= 30 { return results }
        }
    }
    return results
}
func openSearchResult(_ request: [String: Any]) throws -> [String: Any] {
    guard let path = request["path"] as? String, path.hasPrefix("/"), path.count < 4096,
          let id = request["id"] as? String else { throw HostError.message("无效的本地入口。") }
    let requested = URL(fileURLWithPath: path).standardizedFileURL
    let url = requested.resolvingSymlinksInPath().standardizedFileURL
    guard itemID(requested) == id, requested.path == url.path, fm.fileExists(atPath: url.path) else { throw HostError.message("项目已移动或删除，请重新同步桌面。") }
    let isApp = (try? url.resourceValues(forKeys: [.isApplicationKey]).isApplication) == true
    guard searchAllowedRoots().contains(where: { inside(url, root: $0.0) && (!$0.1 || isApp) }) else { throw HostError.message("此项目不在已授权的搜索范围内。") }
    guard NSWorkspace.shared.open(url) else { throw HostError.message("系统无法打开此项目。") }
    return ["ok": true]
}
func handle(_ request: [String: Any]) throws -> [String: Any] {
    guard let action = request["action"] as? String else { throw HostError.message("缺少操作类型。") }
    switch action {
    case "status": return ["ok": true, "version": "1.3.0", "capabilities": ["search": true, "fill": false, "biometric": false]]
    case "search.configure": return try configureSearch()
    case "search.forget":
        if fm.fileExists(atPath: searchSelectionFile.path) { try fm.removeItem(at: searchSelectionFile) }
        return ["ok": true]
    case "search": return ["ok": true, "items": try searchLocal(request["query"] as? String ?? "")]
    case "search.open": return try openSearchResult(request)
    case "configure": return try configure()
    case "scan": return ["ok": true, "items": try inventory(roots())]
    case "open":
        guard let id = request["id"] as? String else { throw HostError.message("缺少入口 ID。") }
        let url = try resolve(id, selected: roots())
        guard NSWorkspace.shared.open(url) else { throw HostError.message("系统无法打开此项目。") }
        return ["ok": true]
    case "forget":
        if fm.fileExists(atPath: selectionFile.path) { try fm.removeItem(at: selectionFile) }
        if fm.fileExists(atPath: searchSelectionFile.path) { try fm.removeItem(at: searchSelectionFile) }
        return ["ok": true]
    default: throw HostError.message("不支持的操作。")
    }
}
func selfTest() throws {
    let fixture = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fm.createDirectory(at: fixture, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: fixture) }
    try Data("fixture".utf8).write(to: fixture.appendingPathComponent("测试 file.txt"))
    try Data().write(to: fixture.appendingPathComponent(".hidden"))
    try fm.createDirectory(at: fixture.appendingPathComponent("Folder"), withIntermediateDirectories: true)
    let items = try inventory([fixture], includeIcons: false)
    guard items.count == 2, items.allSatisfy({ $0["id"]?.count == 64 }), !items.description.contains(fixture.path) else { throw HostError.message("Inventory self-test failed") }
    let resolved = try resolve(items[0]["id"]!, selected: [fixture])
    guard resolved.deletingLastPathComponent().standardizedFileURL.path == fixture.standardizedFileURL.path else { throw HostError.message("Path isolation failed") }
    do { _ = try resolve(String(repeating: "0", count: 64), selected: [fixture]); throw HostError.message("Unknown ID was accepted") } catch HostError.message(let message) { if message == "Unknown ID was accepted" { throw HostError.message(message) } }
    let found = try searchLocal("测试", allowed: [(fixture, false)])
    guard found.count == 1, found[0]["name"] == "测试 file.txt", try searchLocal(".hidden", allowed: [(fixture, false)]).isEmpty else { throw HostError.message("Search isolation failed") }
    try fm.createDirectory(at: fixture.appendingPathComponent("Nested"), withIntermediateDirectories: true)
    try Data().write(to: fixture.appendingPathComponent("Nested/needle.txt"))
    try fm.createSymbolicLink(at: fixture.appendingPathComponent("Escape"), withDestinationURL: fixture.deletingLastPathComponent())
    guard try searchLocal("needle", allowed: [(fixture, false)]).count == 1,
          try searchLocal("Escape", allowed: [(fixture, false)]).isEmpty,
          try searchLocal("测试", allowed: [(fixture, true)]).isEmpty,
          try searchLocal(String(repeating: "x", count: 101), allowed: [(fixture, false)]).isEmpty,
          !inside(fixture.appendingPathComponent("../sibling"), root: fixture) else { throw HostError.message("Recursive search scope test failed") }
    for i in 0..<40 { try Data().write(to: fixture.appendingPathComponent("limit-\(i).txt")) }
    guard try searchLocal("limit", allowed: [(fixture, false)]).count == 30 else { throw HostError.message("Search bound test failed") }
    let encoded = try frame(["ok": true, "text": "中文"])
    let expected = UInt32(encoded[0]) | UInt32(encoded[1]) << 8 | UInt32(encoded[2]) << 16 | UInt32(encoded[3]) << 24
    guard expected == encoded.count - 4, (try JSONSerialization.jsonObject(with: encoded.dropFirst(4)) as? [String: Any])?["text"] as? String == "中文" else { throw HostError.message("Framing self-test failed") }
    print("PASS: macOS inventory, recursive scoped search, symlink isolation, hidden files, Unicode, result bounds and native messaging framing")
}

if CommandLine.arguments.contains("--self-test") {
    do { try selfTest() } catch { fputs("Self-test failed: \(error)\n", stderr); exit(1) }
    exit(0)
}
let origin = CommandLine.arguments.dropFirst().first ?? ""
let allowed = (try? String(contentsOf: binaryDirectory.appendingPathComponent("allowed-extension.txt"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
guard allowed.range(of: "^[a-p]{32}$", options: .regularExpression) != nil, origin == "chrome-extension://\(allowed)/" else { exit(1) }
do {
    while let header = try readExactly(4) {
        let length = Int(UInt32(header[0]) | UInt32(header[1]) << 8 | UInt32(header[2]) << 16 | UInt32(header[3]) << 24)
        guard length > 0, length <= 65536, let body = try readExactly(length) else { break }
        do {
            guard let request = try JSONSerialization.jsonObject(with: body) as? [String: Any] else { throw HostError.message("无效请求。") }
            send(try handle(request))
        } catch HostError.message(let message) { send(["ok": false, "error": message]) }
        catch { send(["ok": false, "error": "无法访问所选桌面，请检查系统权限并重新选择。"] ) }
    }
} catch { exit(1) }
