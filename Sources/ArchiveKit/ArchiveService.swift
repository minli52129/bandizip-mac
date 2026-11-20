//
//  ArchiveService.swift
//  ArchiveKit
//

import Foundation
import CArchive

/// 压缩包读写服务。所有方法都是同步的，调用方自己放到后台线程执行。
public final class ArchiveService {

    public static let shared = ArchiveService()

    public init() {}

    // MARK: - 能力探测

    /// 当前系统真正可写的格式（libarchive 编译选项不同，能力可能不同）
    public func availableFormats() -> [ArchiveFormat] {
        ArchiveFormat.allCases.filter { format in
            format.cIdentifier.withCString { bz_format_supported($0) == 1 }
        }
    }

    // MARK: - 列出内容

    public func list(archiveAt url: URL, password: String? = nil) throws -> ArchiveListing {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let reader = url.path.withCString { path -> OpaquePointer? in
            withCStringOrNil(password) { passphrase in
                bz_reader_open(path, passphrase, &errorPointer)
            }
        }

        guard let reader = reader else {
            let raw = takeError(&errorPointer) ?? "无法打开压缩包"
            throw ArchiveError.classify(raw)
        }
        defer { bz_reader_close(reader) }

        var entries: [ArchiveEntry] = []
        var encrypted = false
        var index = 0

        while true {
            var info = bz_entry_info()
            let result = bz_reader_next(reader, &info)

            if result == 0 { break }
            if result < 0 {
                let raw: String
                if let message = bz_reader_error(reader) {
                    raw = String(cString: message)
                } else {
                    raw = "读取压缩包失败"
                }
                throw ArchiveError.classify(raw)
            }

            guard let rawPath = info.path else { continue }
            let path = String(cString: rawPath)
            if path.isEmpty { continue }
            if info.is_encrypted == 1 { encrypted = true }

            entries.append(ArchiveEntry(
                id: index,
                path: path,
                size: info.size > 0 ? info.size : 0,
                compressedSize: info.compressed_size,
                modified: info.mtime > 0 ? Date(timeIntervalSince1970: TimeInterval(info.mtime)) : nil,
                isDirectory: info.is_dir == 1,
                mode: info.mode,
                isEncrypted: info.is_encrypted == 1
            ))
            index += 1
        }

        if bz_reader_has_encrypted(reader) == 1 { encrypted = true }

        return ArchiveListing(entries: entries,
                              totalSize: bz_reader_total_size(reader),
                              isEncrypted: encrypted)
    }

    // MARK: - 解压

    @discardableResult
    public func extract(archiveAt url: URL,
                        to destination: URL,
                        policy: ExtractPolicy = .overwrite,
                        password: String? = nil,
                        onlyPaths: [String]? = nil,
                        totalHint: Int64 = -1,
                        progress: ((Int64, Int64) -> Void)? = nil,
                        isCancelled: (() -> Bool)? = nil,
                        onExists: ((String) -> ExtractPolicy)? = nil) throws -> Int64 {

        var errorPointer: UnsafeMutablePointer<CChar>?
        let reader = url.path.withCString { path -> OpaquePointer? in
            withCStringOrNil(password) { passphrase in
                bz_reader_open(path, passphrase, &errorPointer)
            }
        }

        guard let reader = reader else {
            let raw = takeError(&errorPointer) ?? "无法打开压缩包"
            throw ArchiveError.classify(raw)
        }
        defer { bz_reader_close(reader) }

        let box = CallbackBox()
        box.progress = progress
        box.isCancelled = isCancelled
        if let handler = onExists {
            box.onExists = { path in Int32(handler(path).rawValue) }
        }
        let context = Unmanaged.passUnretained(box).toOpaque()

        var cPaths: [UnsafePointer<CChar>?] = []
        if let onlyPaths = onlyPaths, !onlyPaths.isEmpty {
            for path in onlyPaths {
                let duplicated = strdup(path)
                cPaths.append(duplicated.map { UnsafePointer($0) })
            }
        }
        defer {
            for pointer in cPaths {
                if let pointer = pointer {
                    free(UnsafeMutableRawPointer(mutating: pointer))
                }
            }
        }

        let result: Int32 = destination.path.withCString { destinationPath in
            cPaths.withUnsafeBufferPointer { buffer in
                bz_reader_extract(reader,
                                  destinationPath,
                                  Int32(policy.rawValue),
                                  totalHint,
                                  buffer.baseAddress,
                                  Int32(cPaths.count),
                                  bzProgressTrampoline,
                                  bzExistsTrampoline,
                                  bzCancelTrampoline,
                                  context,
                                  &errorPointer)
            }
        }

        if result == -3 { throw ArchiveCancelled() }
        if result != 0 {
            let raw = takeError(&errorPointer) ?? "解压失败"
            throw ArchiveError.classify(raw)
        }
        return totalHint > 0 ? totalHint : 0
    }

    // MARK: - 创建

    public func create(items: [URL],
                       destination: URL,
                       format: ArchiveFormat,
                       level: Int = 5,
                       password: String? = nil,
                       progress: ((Int64) -> Void)? = nil,
                       isCancelled: (() -> Bool)? = nil) throws {

        guard !items.isEmpty else {
            throw ArchiveError(message: "请先选择要压缩的文件")
        }
        if let password = password, !password.isEmpty, !format.supportsPassword {
            throw ArchiveError(message: "\(format.displayName) 格式不支持密码保护")
        }

        let fileManager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try? fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        if fileManager.fileExists(atPath: destination.path) {
            try? fileManager.removeItem(at: destination)
        }

        var errorPointer: UnsafeMutablePointer<CChar>?
        let writer = destination.path.withCString { path -> OpaquePointer? in
            format.cIdentifier.withCString { identifier in
                withCStringOrNil(password) { passphrase in
                    bz_writer_open(path, identifier, Int32(level), passphrase, &errorPointer)
                }
            }
        }

        guard let writer = writer else {
            let raw = takeError(&errorPointer) ?? "无法创建压缩包"
            throw ArchiveError.classify(raw)
        }

        let box = CallbackBox()
        box.progress = { done, _ in progress?(done) }
        box.isCancelled = isCancelled
        let context = Unmanaged.passUnretained(box).toOpaque()

        var failureMessage: String?

        for item in items {
            if isCancelled?() == true {
                bz_writer_abort(writer)
                throw ArchiveCancelled()
            }
            let entryName = item.lastPathComponent
            let result: Int32 = item.path.withCString { filePath in
                entryName.withCString { name in
                    bz_writer_add(writer,
                                  filePath,
                                  name,
                                  bzProgressTrampoline,
                                  bzCancelTrampoline,
                                  context,
                                  &errorPointer)
                }
            }
            if result == -3 {
                bz_writer_abort(writer)
                throw ArchiveCancelled()
            }
            if result != 0 && failureMessage == nil {
                failureMessage = takeError(&errorPointer) ?? "写入「\(entryName)」失败"
            }
        }

        if let message = failureMessage {
            bz_writer_abort(writer)
            throw ArchiveError.classify(message)
        }

        if bz_writer_close(writer, &errorPointer) != 0 {
            let raw = takeError(&errorPointer) ?? "关闭压缩包失败"
            throw ArchiveError.classify(raw)
        }
    }

    // MARK: - 完整性校验

    /// 遍历并读取所有条目数据（相当于 Bandizip 的「测试」）
    @discardableResult
    public func test(archiveAt url: URL,
                     password: String? = nil,
                     progress: ((Int64, Int64) -> Void)? = nil,
                     isCancelled: (() -> Bool)? = nil) throws -> ArchiveListing {
        let listing = try list(archiveAt: url, password: password)
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("bz-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        try extract(archiveAt: url,
                    to: temp,
                    policy: .overwrite,
                    password: password,
                    totalHint: listing.totalSize,
                    progress: progress,
                    isCancelled: isCancelled)
        return listing
    }
}
