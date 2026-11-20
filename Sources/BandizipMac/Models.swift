//
//  Models.swift
//  BandizipMac
//

import Foundation
import SwiftUI
import ArchiveKit

// MARK: - 已打开的压缩包

struct OpenArchive: Identifiable {
    let id = UUID()
    let url: URL
    var listing: ArchiveListing
    /// 压缩包本身的体积，用于计算整体压缩率
    var compressedBytes: Int64
    var formatLabel: String
    var password: String?

    var totalSize: Int64 { listing.totalSize }
    var entries: [ArchiveEntry] { listing.entries }

    var overallRatio: Double? {
        guard compressedBytes > 0, listing.totalSize > 0 else { return nil }
        return Double(compressedBytes) / Double(listing.totalSize)
    }
}

// MARK: - 排序

enum SortKey: String, CaseIterable {
    case name
    case size
    case date

    var title: String {
        switch self {
        case .name: return "名称"
        case .size: return "大小"
        case .date: return "修改日期"
        }
    }
}

// MARK: - 路径面包屑

struct BreadcrumbItem: Identifiable, Hashable {
    let id: String
    let title: String
    let prefix: String
}

// MARK: - 创建压缩包草稿

struct CompressDraft: Identifiable {
    let id = UUID()
    var items: [URL]
    var format: ArchiveFormat
    var level: Int
    var usePassword: Bool
    var password: String
    var destination: URL
    var estimatedSize: Int64
}

// MARK: - 解压草稿

struct ExtractDraft: Identifiable {
    let id = UUID()
    var archiveURL: URL
    var destination: URL
    var policy: ExtractPolicy
    var password: String
    var passwordRequired: Bool
    var onlyPaths: [String]?
    var openAfterExtract: Bool

    var scopeDescription: String {
        if let onlyPaths = onlyPaths {
            return "解压所选 \(onlyPaths.count) 项"
        }
        return "解压全部内容"
    }
}

// MARK: - 进度

final class ProgressState: ObservableObject, Identifiable {
    let id = UUID()

    @Published var title: String
    @Published var fraction: Double = 0
    @Published var detail: String = ""
    @Published var speedText: String = ""
    @Published var remainingText: String = ""
    @Published var isDeterminate: Bool = true
    @Published var isFinished: Bool = false

    let totalHint: Int64
    private(set) var isCancelled = false

    private var startedAt = Date()
    private var lastUpdate = Date()
    private var lastBytes: Int64 = 0
    private var speed: Double = 0

    init(title: String, totalHint: Int64, isDeterminate: Bool = true) {
        self.title = title
        self.totalHint = totalHint
        self.isDeterminate = isDeterminate && totalHint > 0
        self.startedAt = Date()
        self.lastUpdate = Date()
    }

    func cancel() {
        isCancelled = true
        detail = "正在取消…"
    }

    /// 必须在主线程调用
    func update(done: Int64, total: Int64) {
        let now = Date()
        var totalValue = total

        if totalValue <= 0, totalHint > 0 {
            totalValue = totalHint
        }
        if totalValue > 0 {
            isDeterminate = true
            fraction = min(1.0, max(0.0, Double(done) / Double(totalValue)))
        } else {
            isDeterminate = false
        }

        let elapsed = now.timeIntervalSince(lastUpdate)
        if elapsed >= 0.25 {
            let delta = Double(done - lastBytes)
            let instant = delta / elapsed
            speed = speed == 0 ? instant : speed * 0.7 + instant * 0.3
            lastUpdate = now
            lastBytes = done
            speedText = Fmt.speed(speed)
            if totalValue > 0, speed > 0 {
                remainingText = Fmt.remaining(Double(totalValue - done) / speed)
            } else {
                remainingText = ""
            }
        }

        if totalValue > 0 {
            detail = "\(Fmt.bytes(done)) / \(Fmt.bytes(totalValue))"
        } else {
            detail = Fmt.bytes(done)
        }
    }
}

// MARK: - 文件图标

enum FileIcon {
    static func symbol(for entry: ArchiveEntry) -> String {
        if entry.isDirectory { return "folder.fill" }
        switch entry.pathExtension {
        case "png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "bmp", "svg", "ico":
            return "photo.fill"
        case "mp4", "mov", "mkv", "avi", "webm", "m4v", "wmv", "flv":
            return "film.fill"
        case "mp3", "wav", "flac", "aac", "m4a", "ogg", "opus":
            return "music.note"
        case "pdf":
            return "doc.richtext.fill"
        case "app", "dmg", "pkg", "exe", "msi":
            return "shippingbox.fill"
        case "zip", "7z", "rar", "tar", "gz", "bz2", "xz", "tgz", "alz", "egg":
            return "doc.zipper"
        case "txt", "md", "rtf", "log", "json", "xml", "yml", "yaml", "csv",
             "swift", "c", "h", "cpp", "m", "mm", "py", "js", "ts", "html", "css", "sh":
            return "doc.text.fill"
        default:
            return "doc.fill"
        }
    }

    static func tint(for entry: ArchiveEntry) -> Color {
        if entry.isDirectory { return Color.accentColor }
        switch entry.pathExtension {
        case "png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "bmp", "svg":
            return Color(red: 0.55, green: 0.35, blue: 0.85)
        case "mp4", "mov", "mkv", "avi", "webm":
            return Color(red: 0.85, green: 0.35, blue: 0.45)
        case "mp3", "wav", "flac", "aac", "m4a":
            return Color(red: 0.20, green: 0.62, blue: 0.45)
        case "pdf":
            return Color(red: 0.80, green: 0.28, blue: 0.28)
        case "zip", "7z", "rar", "tar", "gz", "bz2", "xz":
            return Color(red: 0.85, green: 0.55, blue: 0.20)
        default:
            return Color(nsColor: .secondaryLabelColor)
        }
    }
}
