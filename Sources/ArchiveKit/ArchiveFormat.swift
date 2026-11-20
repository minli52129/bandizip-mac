//
//  ArchiveFormat.swift
//  ArchiveKit
//

import Foundation

/// 可创建的压缩格式。
public enum ArchiveFormat: String, CaseIterable, Identifiable, Sendable {
    case zip
    case sevenZip
    case tar
    case tarGz
    case tarBz2
    case tarXz

    public var id: String { rawValue }

    /// 传给 C 层的格式标识
    public var cIdentifier: String {
        switch self {
        case .zip: return "zip"
        case .sevenZip: return "7z"
        case .tar: return "tar"
        case .tarGz: return "tar.gz"
        case .tarBz2: return "tar.bz2"
        case .tarXz: return "tar.xz"
        }
    }

    public var displayName: String {
        switch self {
        case .zip: return "ZIP"
        case .sevenZip: return "7Z"
        case .tar: return "TAR"
        case .tarGz: return "TAR.GZ"
        case .tarBz2: return "TAR.BZ2"
        case .tarXz: return "TAR.XZ"
        }
    }

    public var fileExtension: String {
        switch self {
        case .zip: return "zip"
        case .sevenZip: return "7z"
        case .tar: return "tar"
        case .tarGz: return "tar.gz"
        case .tarBz2: return "tar.bz2"
        case .tarXz: return "tar.xz"
        }
    }

    public var supportsPassword: Bool {
        switch self {
        case .zip, .sevenZip: return true
        default: return false
        }
    }

    public var supportsLevel: Bool {
        switch self {
        case .tar: return false
        default: return true
        }
    }

    public var summary: String {
        switch self {
        case .zip: return "兼容性最好，Windows / macOS 都原生支持"
        case .sevenZip: return "压缩率最高，需第三方工具解压"
        case .tar: return "仅打包不压缩，适合归档"
        case .tarGz: return "打包 + gzip，macOS / Linux 通用"
        case .tarBz2: return "打包 + bzip2，压缩率略高于 gzip"
        case .tarXz: return "打包 + xz，压缩率最高但速度慢"
        }
    }

    /// 根据文件扩展名推断格式（用于新建压缩包时给出默认名）
    public static func detect(from url: URL) -> ArchiveFormat? {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") { return .tarGz }
        if name.hasSuffix(".tar.bz2") || name.hasSuffix(".tbz2") || name.hasSuffix(".tbz") { return .tarBz2 }
        if name.hasSuffix(".tar.xz") || name.hasSuffix(".txz") { return .tarXz }
        switch url.pathExtension.lowercased() {
        case "zip", "cbz": return .zip
        case "7z": return .sevenZip
        case "tar": return .tar
        default: return nil
        }
    }

    /// 系统「打开方式」里能识别的压缩包扩展名
    public static let archiveExtensions: Set<String> = [
        "zip", "7z", "rar", "tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz",
        "lz", "lzma", "z", "alz", "egg", "iso", "cab", "jar", "war", "apk", "xpi",
        "cpio", "ar", "deb", "rpm", "cbz", "cbr", "zipx"
    ]

    public static func isArchive(url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }
        if isDirectory.boolValue {
            return false
        }
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".tar.gz") || name.hasSuffix(".tar.bz2") || name.hasSuffix(".tar.xz") {
            return true
        }
        return archiveExtensions.contains(url.pathExtension.lowercased())
    }

    /// 展示用的格式标签，例如 "TAR.GZ" -> "TGZ"
    public static func shortLabel(for url: URL) -> String {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") { return "TAR.GZ" }
        if name.hasSuffix(".tar.bz2") || name.hasSuffix(".tbz2") || name.hasSuffix(".tbz") { return "TAR.BZ2" }
        if name.hasSuffix(".tar.xz") || name.hasSuffix(".txz") { return "TAR.XZ" }
        let ext = url.pathExtension.uppercased()
        return ext.isEmpty ? "归档" : ext
    }
}
