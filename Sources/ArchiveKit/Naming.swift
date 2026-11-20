//
//  Naming.swift
//  ArchiveKit
//

import Foundation

public enum ArchiveNaming {

    /// 去掉压缩包的多段扩展名，得到「干净」的名字
    /// 例如 report.tar.gz -> report
    public static func baseName(for url: URL) -> String {
        let name = url.lastPathComponent
        let lower = name.lowercased()
        let compound = [".tar.gz", ".tar.bz2", ".tar.xz", ".tgz", ".tbz2", ".tbz", ".txz"]
        for suffix in compound where lower.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return url.deletingPathExtension().lastPathComponent
    }

    /// 给压缩包挑一个不冲突的新文件名
    public static func uniqueDestination(in directory: URL, baseName: String, fileExtension: String) -> URL {
        let manager = FileManager.default
        var candidate = directory.appendingPathComponent("\(baseName).\(fileExtension)")
        var counter = 2
        while manager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(counter).\(fileExtension)")
            counter += 1
        }
        return candidate
    }
}
