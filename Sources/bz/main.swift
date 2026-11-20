//
//  main.swift
//  bz — Bandizip for Mac 的命令行前端
//

import Foundation
import ArchiveKit

// MARK: - 输出工具

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func usage() -> String {
    """
    bz — Bandizip for Mac 命令行工具

    用法:
      bz l <压缩包> [密码]                 列出内容
      bz x <压缩包> [选项]                 解压
      bz c <输出文件> <文件或目录…> [选项]  创建压缩包
      bz t <压缩包> [密码]                 完整性校验
      bz f                                列出本机支持的压缩格式

    x 的选项:
      -o <目录>       解压到指定目录（默认与压缩包同目录下的同名文件夹）
      -p <密码>       压缩包密码
      --overwrite     覆盖同名文件（默认）
      --skip          跳过同名文件
      --rename        自动重命名

    c 的选项:
      -p <密码>       设置密码（仅 zip / 7z）
      -l <1-9>        压缩级别（默认 5）
      -f <格式>       zip | 7z | tar | tar.gz | tar.bz2 | tar.xz
                      （不指定时按输出文件扩展名推断）
    """
}

func humanSize(_ value: Int64) -> String {
    if value < 0 { return "—" }
    let units = ["B", "KB", "MB", "GB", "TB"]
    var size = Double(value)
    var index = 0
    while size >= 1024, index < units.count - 1 {
        size /= 1024
        index += 1
    }
    return index == 0 ? "\(Int(size)) B" : String(format: "%.1f %@", size, units[index])
}

func pad(_ text: String, _ width: Int) -> String {
    if text.count >= width { return text }
    return String(repeating: " ", count: width - text.count) + text
}

func fileURL(_ path: String) -> URL {
    URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
}

// MARK: - 命令

func runList(_ args: [String]) throws {
    guard let path = args.first else { fail("用法：bz l <压缩包> [密码]") }
    let url = fileURL(path)
    let listing = try ArchiveService.shared.list(archiveAt: url,
                                                password: args.count > 1 ? args[1] : nil)

    print("\(url.lastPathComponent)  ·  \(listing.fileCount) 个文件, \(listing.directoryCount) 个文件夹  ·  \(humanSize(listing.totalSize))")
    print(String(repeating: "-", count: 60))
    for entry in listing.entries {
        let sizeText = entry.isDirectory ? "<DIR>" : humanSize(entry.size)
        print("\(pad(sizeText, 12))  \(entry.path)\(entry.isEncrypted ? "  [encrypted]" : "")")
    }
}

func runExtract(_ args: [String]) throws {
    guard let path = args.first else { fail("用法：bz x <压缩包> [-o 目录] [-p 密码]") }
    let archiveURL = fileURL(path)

    var outputDirectory: URL?
    var password: String?
    var policy: ExtractPolicy = .overwrite

    var index = 1
    while index < args.count {
        switch args[index] {
        case "-o":
            index += 1
            if index < args.count { outputDirectory = fileURL(args[index]) }
        case "-p":
            index += 1
            if index < args.count { password = args[index] }
        case "--skip":
            policy = .skip
        case "--rename":
            policy = .rename
        case "--overwrite":
            policy = .overwrite
        default:
            fail("未知选项：\(args[index])")
        }
        index += 1
    }

    let destination = outputDirectory ?? archiveURL
        .deletingLastPathComponent()
        .appendingPathComponent(ArchiveNaming.baseName(for: archiveURL), isDirectory: true)

    let listing = try ArchiveService.shared.list(archiveAt: archiveURL, password: password)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

    var lastPercent = -1
    try ArchiveService.shared.extract(archiveAt: archiveURL,
                                      to: destination,
                                      policy: policy,
                                      password: password,
                                      totalHint: listing.totalSize,
                                      progress: { done, total in
                                          guard total > 0 else { return }
                                          let percent = Int(Double(done) / Double(total) * 100)
                                          if percent != lastPercent {
                                              lastPercent = percent
                                              FileHandle.standardError.write(Data("\r解压中 \(percent)%".utf8))
                                          }
                                      })
    FileHandle.standardError.write(Data("\r解压完成：\(destination.path)\n".utf8))
}

func runCreate(_ args: [String]) throws {
    guard args.count >= 2 else { fail("用法：bz c <输出文件> <文件或目录…> [-p 密码] [-l 级别] [-f 格式]") }

    let outputURL = fileURL(args[0])
    var items: [URL] = []
    var password: String?
    var level = 5
    var formatText: String?

    var index = 1
    while index < args.count {
        switch args[index] {
        case "-p":
            index += 1
            if index < args.count { password = args[index] }
        case "-l":
            index += 1
            if index < args.count { level = Int(args[index]) ?? 5 }
        case "-f":
            index += 1
            if index < args.count { formatText = args[index] }
        default:
            items.append(fileURL(args[index]))
        }
        index += 1
    }

    guard !items.isEmpty else { fail("没有要压缩的文件") }

    var format: ArchiveFormat = ArchiveFormat.detect(from: outputURL) ?? .zip
    if let formatText = formatText {
        switch formatText.lowercased() {
        case "zip": format = .zip
        case "7z", "7zip": format = .sevenZip
        case "tar": format = .tar
        case "tar.gz", "tgz", "gz": format = .tarGz
        case "tar.bz2", "tbz2", "bz2": format = .tarBz2
        case "tar.xz", "txz", "xz": format = .tarXz
        default: fail("不支持的格式：\(formatText)")
        }
    }

    try ArchiveService.shared.create(items: items,
                                     destination: outputURL,
                                     format: format,
                                     level: level,
                                     password: password)
    print("已创建：\(outputURL.path)")
}

func runTest(_ args: [String]) throws {
    guard let path = args.first else { fail("用法：bz t <压缩包> [密码]") }
    let url = fileURL(path)
    let listing = try ArchiveService.shared.test(archiveAt: url,
                                                 password: args.count > 1 ? args[1] : nil)
    print("校验通过：\(listing.fileCount) 个文件, \(listing.directoryCount) 个文件夹")
}

func runFormats() {
    for format in ArchiveFormat.allCases {
        let supported = ArchiveService.shared.availableFormats().contains(format)
        print("\(pad(format.displayName, 10))  \(supported ? "支持" : "不支持")")
    }
}

// MARK: - 入口

let arguments = Array(CommandLine.arguments.dropFirst())

guard let command = arguments.first else {
    print(usage())
    exit(2)
}

let rest = Array(arguments.dropFirst())

do {
    switch command {
    case "l", "list":
        try runList(rest)
    case "x", "extract":
        try runExtract(rest)
    case "c", "create":
        try runCreate(rest)
    case "t", "test":
        try runTest(rest)
    case "f", "formats":
        runFormats()
    case "-h", "--help", "help":
        print(usage())
    default:
        fail("未知命令：\(command)\n\n" + usage())
    }
} catch {
    fail("错误：\(error.localizedDescription)")
}
