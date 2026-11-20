//
//  ArchiveEntry.swift
//  ArchiveKit
//

import Foundation

/// 压缩包里的一个条目。
public struct ArchiveEntry: Identifiable, Hashable, Sendable {
    public let id: Int
    /// 压缩包内的相对路径（使用 "/" 分隔）
    public let path: String
    /// 原始大小，未知为 0
    public let size: Int64
    /// 压缩后大小，未知为 -1
    public let compressedSize: Int64
    public let modified: Date?
    public let isDirectory: Bool
    public let mode: UInt32
    public let isEncrypted: Bool

    public init(id: Int,
                path: String,
                size: Int64,
                compressedSize: Int64 = -1,
                modified: Date? = nil,
                isDirectory: Bool = false,
                mode: UInt32 = 0,
                isEncrypted: Bool = false) {
        self.id = id
        self.path = path
        self.size = size
        self.compressedSize = compressedSize
        self.modified = modified
        self.isDirectory = isDirectory
        self.mode = mode
        self.isEncrypted = isEncrypted
    }

    /// 去掉路径后的文件名
    public var name: String {
        var trimmed = path
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        guard let index = trimmed.lastIndex(of: "/") else {
            return trimmed
        }
        return String(trimmed[trimmed.index(after: index)...])
    }

    /// 父目录路径（根目录为空字符串）
    public var parentPath: String {
        var trimmed = path
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        guard let index = trimmed.lastIndex(of: "/") else {
            return ""
        }
        return String(trimmed[..<index])
    }

    public var pathExtension: String {
        (name as NSString).pathExtension.lowercased()
    }

    /// 压缩率（0~1），无法计算时为 nil
    public var ratio: Double? {
        guard compressedSize > 0, size > 0 else { return nil }
        return Double(compressedSize) / Double(size)
    }

    public var isSymbolicLink: Bool {
        (mode & 0o170000) == 0o120000
    }
}

/// 一次列目录的结果。
public struct ArchiveListing: Sendable {
    public let entries: [ArchiveEntry]
    /// 解压后的总字节数，-1 表示无法确定
    public let totalSize: Int64
    public let isEncrypted: Bool

    public init(entries: [ArchiveEntry], totalSize: Int64, isEncrypted: Bool) {
        self.entries = entries
        self.totalSize = totalSize
        self.isEncrypted = isEncrypted
    }

    public var fileCount: Int {
        entries.filter { !$0.isDirectory }.count
    }

    public var directoryCount: Int {
        entries.filter { $0.isDirectory }.count
    }
}
