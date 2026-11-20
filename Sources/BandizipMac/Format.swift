//
//  Format.swift
//  BandizipMac
//
//  体积 / 时间 / 比率等展示格式化。
//

import Foundation

enum Fmt {

    static func bytes(_ value: Int64) -> String {
        if value < 0 { return "—" }
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var size = Double(value)
        var index = 0
        while size >= 1024, index < units.count - 1 {
            size /= 1024
            index += 1
        }
        if index == 0 {
            return "\(Int(size)) B"
        }
        return String(format: "%.2f %@", size, units[index])
    }

    static func bytesOptional(_ value: Int64) -> String {
        value > 0 ? bytes(value) : "—"
    }

    static func speed(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond > 0 else { return "" }
        return bytes(Int64(bytesPerSecond)) + "/s"
    }

    static func ratio(_ value: Double?) -> String {
        guard let value = value, value > 0 else { return "—" }
        return String(format: "%.0f%%", value * 100)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter
    }()

    static func date(_ value: Date?) -> String {
        guard let value = value else { return "—" }
        return dateFormatter.string(from: value)
    }

    static func remaining(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "" }
        if seconds < 60 {
            return String(format: "剩余 %.0f 秒", seconds)
        }
        if seconds < 3600 {
            return String(format: "剩余 %.0f 分", seconds / 60)
        }
        return String(format: "剩余 %.1f 小时", seconds / 3600)
    }
}

enum FileSizeCalculator {
    static func total(of urls: [URL]) -> Int64 {
        let manager = FileManager.default
        var total: Int64 = 0

        for url in urls {
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }

            if !isDirectory.boolValue {
                if let attributes = try? manager.attributesOfItem(atPath: url.path),
                   let size = attributes[.size] as? NSNumber {
                    total += size.int64Value
                }
                continue
            }

            if let enumerator = manager.enumerator(at: url,
                                                   includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                                   options: [.skipsHiddenFiles],
                                                   errorHandler: nil) {
                for case let child as URL in enumerator {
                    guard let values = try? child.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                          values.isRegularFile == true else { continue }
                    total += Int64(values.fileSize ?? 0)
                }
            }
        }
        return total
    }
}
