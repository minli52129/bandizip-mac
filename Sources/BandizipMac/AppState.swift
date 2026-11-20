//
//  AppState.swift
//  BandizipMac
//

import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ArchiveKit

final class AppState: ObservableObject {

    static let shared = AppState()

    // MARK: - 文档内容

    @Published var archive: OpenArchive? {
        didSet { refreshVisible() }
    }

    @Published private(set) var visibleEntries: [ArchiveEntry] = []
    @Published var selectedIDs: Set<Int> = []

    @Published var currentPrefix: String = "" {
        didSet { refreshVisible() }
    }

    @Published var searchText: String = "" {
        didSet { refreshVisible() }
    }

    @Published var sortKey: SortKey = .name {
        didSet { refreshVisible() }
    }

    @Published var sortAscending: Bool = true {
        didSet { refreshVisible() }
    }

    // MARK: - 界面状态

    @Published var recentFiles: [URL] = []
    @Published var compressDraft: CompressDraft?
    @Published var extractDraft: ExtractDraft?
    @Published var progress: ProgressState?
    @Published var alertMessage: String = ""
    @Published var showAlert: Bool = false
    @Published var isDropTarget: Bool = false
    @Published var availableFormats: [ArchiveFormat] = ArchiveFormat.allCases

    let preferences = Preferences.shared
    private let service = ArchiveService.shared
    private let recentKey = "recent.archive.paths"

    private init() {
        loadRecent()
        DispatchQueue.global(qos: .utility).async {
            let formats = ArchiveService.shared.availableFormats()
            guard !formats.isEmpty else { return }
            DispatchQueue.main.async {
                self.availableFormats = formats
            }
        }
    }

    // MARK: - 列表计算

    func refreshVisible() {
        guard let archive = archive else {
            if !visibleEntries.isEmpty { visibleEntries = [] }
            return
        }

        let prefix = currentPrefix
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var result: [ArchiveEntry] = []

        for entry in archive.entries {
            guard entry.path.hasPrefix(prefix) else { continue }

            var remainder = String(entry.path.dropFirst(prefix.count))
            while remainder.hasSuffix("/") { remainder.removeLast() }
            if remainder.isEmpty { continue }

            if search.isEmpty {
                if remainder.contains("/") { continue }
            } else if !entry.name.lowercased().contains(search) {
                continue
            }
            result.append(entry)
        }

        result.sort(by: areInIncreasingOrder)
        visibleEntries = result
    }

    private func areInIncreasingOrder(_ lhs: ArchiveEntry, _ rhs: ArchiveEntry) -> Bool {
        if lhs.isDirectory != rhs.isDirectory {
            return lhs.isDirectory
        }
        switch sortKey {
        case .name:
            let order = lhs.name.localizedStandardCompare(rhs.name)
            if order == .orderedSame { return lhs.path < rhs.path }
            return sortAscending ? order == .orderedAscending : order == .orderedDescending
        case .size:
            if lhs.size == rhs.size { return lhs.name < rhs.name }
            return sortAscending ? lhs.size < rhs.size : lhs.size > rhs.size
        case .date:
            let left = lhs.modified ?? Date.distantPast
            let right = rhs.modified ?? Date.distantPast
            if left == right { return lhs.name < rhs.name }
            return sortAscending ? left < right : left > right
        }
    }

    var selectedEntries: [ArchiveEntry] {
        visibleEntries.filter { selectedIDs.contains($0.id) }
    }

    var selectedPaths: [String] {
        selectedEntries.map { $0.path }
    }

    var breadcrumb: [BreadcrumbItem] {
        var items: [BreadcrumbItem] = []
        let rootTitle = archive?.url.lastPathComponent ?? "压缩包"
        items.append(BreadcrumbItem(id: "root", title: rootTitle, prefix: ""))
        guard !currentPrefix.isEmpty else { return items }

        var accumulated = ""
        for component in currentPrefix.split(separator: "/") {
            accumulated += String(component) + "/"
            items.append(BreadcrumbItem(id: accumulated, title: String(component), prefix: accumulated))
        }
        return items
    }

    // MARK: - 导航

    func enter(_ entry: ArchiveEntry) {
        guard entry.isDirectory else { return }
        var path = entry.path
        while path.hasSuffix("/") { path.removeLast() }
        currentPrefix = path + "/"
        selectedIDs = []
    }

    func goUp() {
        guard !currentPrefix.isEmpty else { return }
        var path = currentPrefix
        while path.hasSuffix("/") { path.removeLast() }
        if let index = path.lastIndex(of: "/") {
            currentPrefix = String(path[..<index]) + "/"
        } else {
            currentPrefix = ""
        }
        selectedIDs = []
    }

    func jump(to prefix: String) {
        currentPrefix = prefix
        selectedIDs = []
    }

    func toggleSort(_ key: SortKey) {
        if sortKey == key {
            sortAscending.toggle()
        } else {
            sortKey = key
            sortAscending = true
        }
    }

    func selectAll() {
        selectedIDs = Set(visibleEntries.map { $0.id })
    }

    func clearSelection() {
        selectedIDs = []
    }

    // MARK: - 打开压缩包

    func promptOpen() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "选择要打开的压缩包"
        panel.prompt = "打开"
        if panel.runModal() == .OK, let url = panel.url {
            openArchive(url: url)
        }
    }

    func openArchive(url: URL, password: String? = nil) {
        guard ArchiveFormat.isArchive(url: url) else {
            presentAlert("「\(url.lastPathComponent)」不是可识别的压缩包。\n支持 ZIP / 7Z / RAR / TAR / GZ / BZ2 / XZ / ISO 等格式。")
            return
        }

        let progressState = ProgressState(title: "正在读取「\(url.lastPathComponent)」", totalHint: -1, isDeterminate: false)
        progress = progressState

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let listing = try ArchiveService.shared.list(archiveAt: url, password: password)
                var fileSize: Int64 = 0
                if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let size = attributes[.size] as? NSNumber {
                    fileSize = size.int64Value
                }
                DispatchQueue.main.async {
                    self.progress = nil
                    self.archive = OpenArchive(url: url,
                                               listing: listing,
                                               compressedBytes: fileSize,
                                               formatLabel: ArchiveFormat.shortLabel(for: url),
                                               password: password)
                    self.currentPrefix = ""
                    self.selectedIDs = []
                    self.rememberRecent(url)
                }
            } catch {
                DispatchQueue.main.async {
                    self.progress = nil
                    if let archiveError = error as? ArchiveError, archiveError.needsPassword {
                        if let newPassword = self.promptPassword(title: "需要密码", message: archiveError.message) {
                            self.openArchive(url: url, password: newPassword)
                        }
                    } else {
                        self.presentAlert(error.localizedDescription)
                    }
                }
            }
        }
    }

    func closeArchive() {
        archive = nil
        currentPrefix = ""
        selectedIDs = []
        searchText = ""
    }

    func revealArchiveInFinder() {
        guard let archive = archive else { return }
        NSWorkspace.shared.activateFileViewerSelecting([archive.url])
    }

    /// 双击条目：目录进入，文件解压到临时目录后直接打开
    func activate(_ entry: ArchiveEntry) {
        if entry.isDirectory {
            enter(entry)
            return
        }
        openEntry(entry)
    }

    func openEntry(_ entry: ArchiveEntry) {
        guard let archive = archive else { return }
        if entry.isDirectory {
            enter(entry)
            return
        }

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("BandizipPreview", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let progressState = ProgressState(title: "正在打开「\(entry.name)」", totalHint: entry.size)
        progress = progressState

        let archiveURL = archive.url
        let password = archive.password
        let entryPath = entry.path
        let entrySize = entry.size

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
                try ArchiveService.shared.extract(archiveAt: archiveURL,
                                                  to: temp,
                                                  policy: .overwrite,
                                                  password: password,
                                                  onlyPaths: [entryPath],
                                                  totalHint: entrySize,
                                                  progress: { done, total in
                                                      DispatchQueue.main.async {
                                                          progressState.update(done: done, total: total)
                                                      }
                                                  },
                                                  isCancelled: { false })
                let target = temp.appendingPathComponent(entryPath)
                DispatchQueue.main.async {
                    self.progress = nil
                    NSWorkspace.shared.open(target)
                }
            } catch {
                DispatchQueue.main.async {
                    self.progress = nil
                    self.presentAlert(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - 解压

    func promptExtract(selectionOnly: Bool) {
        guard let archive = archive else { return }
        if selectionOnly && selectedIDs.isEmpty {
            presentAlert("请先在列表中选择要解压的项目。")
            return
        }

        let baseName = AppState.baseName(for: archive.url)
        let parent = archive.url.deletingLastPathComponent()
        let destination = preferences.extractToSubfolder
            ? parent.appendingPathComponent(baseName, isDirectory: true)
            : parent

        var draft = ExtractDraft(archiveURL: archive.url,
                                 destination: destination,
                                 policy: preferences.overwritePolicy,
                                 password: archive.password ?? "",
                                 passwordRequired: archive.listing.isEncrypted,
                                 onlyPaths: selectionOnly ? selectedPaths : nil,
                                 openAfterExtract: preferences.revealAfterExtract)

        if archive.listing.isEncrypted && (archive.password ?? "").isEmpty {
            draft.passwordRequired = true
        }
        extractDraft = draft
    }

    func startExtract(_ draft: ExtractDraft) {
        performExtract(draft, allowPasswordRetry: true)
    }

    /// 「逐项询问」在真正开始前统一确认一次，避免解压途中反复弹窗
    private func resolveOverwritePolicy(_ draft: ExtractDraft) -> ExtractPolicy? {
        guard let archive = archive else { return .overwrite }

        let manager = FileManager.default
        var conflicts = 0
        for entry in archive.entries where !entry.isDirectory {
            if let only = draft.onlyPaths, !only.isEmpty, !Self.path(entry.path, matchesAnyOf: only) {
                continue
            }
            let target = draft.destination.appendingPathComponent(entry.path)
            if manager.fileExists(atPath: target.path) {
                conflicts += 1
            }
        }

        guard conflicts > 0 else { return .overwrite }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "有 \(conflicts) 个同名文件"
        alert.informativeText = "目标文件夹中已经存在同名文件，请选择处理方式。"
        alert.addButton(withTitle: "覆盖")
        alert.addButton(withTitle: "跳过")
        alert.addButton(withTitle: "自动重命名")
        alert.addButton(withTitle: "取消")

        switch alert.runModal() {
        case .alertFirstButtonReturn: return .overwrite
        case .alertSecondButtonReturn: return .skip
        case .alertThirdButtonReturn: return .rename
        default: return nil
        }
    }

    static func path(_ entryPath: String, matchesAnyOf prefixes: [String]) -> Bool {
        var normalized = entryPath
        while normalized.hasSuffix("/") { normalized.removeLast() }
        for prefix in prefixes {
            var candidate = prefix
            while candidate.hasSuffix("/") { candidate.removeLast() }
            if normalized == candidate { return true }
            if normalized.hasPrefix(candidate + "/") { return true }
        }
        return false
    }

    private func performExtract(_ draft: ExtractDraft, allowPasswordRetry: Bool) {
        var draft = draft
        if draft.policy == .ask {
            guard let resolved = resolveOverwritePolicy(draft) else { return }
            draft.policy = resolved
        }

        let totalHint = archive?.totalSize ?? -1
        let progressState = ProgressState(title: draft.onlyPaths == nil ? "正在解压" : "正在解压所选项目",
                                          totalHint: totalHint,
                                          isDeterminate: totalHint > 0)
        progress = progressState
        let password = draft.password.isEmpty ? nil : draft.password
        let archiveURL = draft.archiveURL
        let destination = draft.destination
        let onlyPaths = draft.onlyPaths
        let policy = draft.policy

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                try ArchiveService.shared.extract(archiveAt: archiveURL,
                                                  to: destination,
                                                  policy: policy,
                                                  password: password,
                                                  onlyPaths: onlyPaths,
                                                  totalHint: totalHint,
                                                  progress: { done, total in
                                                      DispatchQueue.main.async {
                                                          progressState.update(done: done, total: total)
                                                      }
                                                  },
                                                  isCancelled: { progressState.isCancelled })
                DispatchQueue.main.async {
                    self.progress = nil
                    if draft.openAfterExtract {
                        NSWorkspace.shared.activateFileViewerSelecting([destination])
                    }
                }
            } catch is ArchiveCancelled {
                DispatchQueue.main.async { self.progress = nil }
            } catch {
                DispatchQueue.main.async {
                    self.progress = nil
                    if let archiveError = error as? ArchiveError,
                       archiveError.needsPassword,
                       allowPasswordRetry,
                       let newPassword = self.promptPassword(title: "密码错误或缺失", message: archiveError.message) {
                        var retry = draft
                        retry.password = newPassword
                        self.performExtract(retry, allowPasswordRetry: false)
                    } else {
                        self.presentAlert(error.localizedDescription)
                    }
                }
            }
        }
    }

    // MARK: - 创建压缩包

    func promptNewArchive() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "选择要压缩的文件或文件夹"
        panel.prompt = "选择"
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            presentCompress(items: panel.urls)
        }
    }

    func presentCompress(items: [URL]) {
        guard !items.isEmpty else { return }
        let format = preferences.defaultFormat
        let baseName = items.count == 1 ? AppState.baseName(for: items[0]) : "归档"
        let directory = items[0].deletingLastPathComponent()

        var destination = directory.appendingPathComponent("\(baseName).\(format.fileExtension)")
        var counter = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("\(baseName) \(counter).\(format.fileExtension)")
            counter += 1
        }
        compressDraft = CompressDraft(items: items,
                                      format: format,
                                      level: preferences.defaultLevel,
                                      usePassword: false,
                                      password: "",
                                      destination: destination,
                                      estimatedSize: FileSizeCalculator.total(of: items))
    }

    func startCompress(_ draft: CompressDraft) {
        let progressState = ProgressState(title: "正在压缩",
                                          totalHint: draft.estimatedSize,
                                          isDeterminate: draft.estimatedSize > 0)
        progress = progressState

        let estimated = draft.estimatedSize
        let destination = draft.destination
        let password = draft.usePassword && !draft.password.isEmpty ? draft.password : nil

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try ArchiveService.shared.create(items: draft.items,
                                                 destination: destination,
                                                 format: draft.format,
                                                 level: draft.level,
                                                 password: password,
                                                 progress: { done in
                                                     DispatchQueue.main.async {
                                                         progressState.update(done: done, total: estimated)
                                                     }
                                                 },
                                                 isCancelled: { progressState.isCancelled })
                DispatchQueue.main.async {
                    self.progress = nil
                    self.openArchive(url: destination)
                }
            } catch is ArchiveCancelled {
                DispatchQueue.main.async { self.progress = nil }
            } catch {
                DispatchQueue.main.async {
                    self.progress = nil
                    self.presentAlert(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - 校验

    func testCurrentArchive() {
        guard let archive = archive else { return }
        let progressState = ProgressState(title: "正在校验压缩包", totalHint: archive.totalSize, isDeterminate: archive.totalSize > 0)
        progress = progressState
        let archiveURL = archive.url
        let password = archive.password
        let total = archive.totalSize

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let listing = try ArchiveService.shared.test(archiveAt: archiveURL,
                                                             password: password,
                                                             progress: { done, totalBytes in
                                                                 DispatchQueue.main.async {
                                                                     progressState.update(done: done, total: totalBytes > 0 ? totalBytes : total)
                                                                 }
                                                             },
                                                             isCancelled: { progressState.isCancelled })
                DispatchQueue.main.async {
                    self.progress = nil
                    self.presentAlert("校验完成：\(listing.fileCount) 个文件、\(listing.directoryCount) 个文件夹，未发现错误。")
                }
            } catch is ArchiveCancelled {
                DispatchQueue.main.async { self.progress = nil }
            } catch {
                DispatchQueue.main.async {
                    self.progress = nil
                    self.presentAlert("校验失败：\(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - 拖放 / 外部打开

    func handleDrop(providers: [NSItemProvider]) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                var resolved: URL?
                if let data = item as? Data {
                    resolved = URL(dataRepresentation: data, relativeTo: nil)
                } else if let itemURL = item as? URL {
                    resolved = itemURL
                }
                if let resolved = resolved {
                    lock.lock()
                    urls.append(resolved)
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            self.handleOpenURLs(urls)
        }
    }

    func handleOpenURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let archives = urls.filter { ArchiveFormat.isArchive(url: $0) }
        let others = urls.filter { !ArchiveFormat.isArchive(url: $0) }

        if !others.isEmpty {
            presentCompress(items: others)
        }
        if let first = archives.first {
            openArchive(url: first)
        }
    }

    // MARK: - 最近打开

    private func loadRecent() {
        let paths = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
        recentFiles = paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func rememberRecent(_ url: URL) {
        var paths = recentFiles.map { $0.path }
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        if paths.count > 12 {
            paths = Array(paths.prefix(12))
        }
        recentFiles = paths.map { URL(fileURLWithPath: $0) }
        UserDefaults.standard.set(paths, forKey: recentKey)
    }

    func clearRecent() {
        recentFiles = []
        UserDefaults.standard.removeObject(forKey: recentKey)
    }

    // MARK: - 辅助

    static func baseName(for url: URL) -> String {
        ArchiveNaming.baseName(for: url)
    }

    func presentAlert(_ message: String) {
        alertMessage = message
        showAlert = true
    }

    func promptPassword(title: String, message: String) -> String? {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "压缩包密码"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue
        return value.isEmpty ? nil : value
    }
}
