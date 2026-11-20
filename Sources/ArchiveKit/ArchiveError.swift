//
//  ArchiveError.swift
//  ArchiveKit
//

import Foundation

public struct ArchiveError: LocalizedError {
    public let message: String
    public let needsPassword: Bool

    public init(message: String, needsPassword: Bool = false) {
        self.message = message
        self.needsPassword = needsPassword
    }

    public var errorDescription: String? { message }

    /// 根据 libarchive 的报错文本判断是否是「需要密码 / 密码错误」
    public static func classify(_ raw: String) -> ArchiveError {
        let lower = raw.lowercased()
        let passwordKeywords = ["passphrase", "password", "encrypted", "decrypt", "密码"]
        let needs = passwordKeywords.contains { lower.contains($0) }
        if needs {
            if lower.contains("incorrect") || lower.contains("invalid") || lower.contains("wrong") || lower.contains("校验") {
                return ArchiveError(message: "密码不正确，请重新输入", needsPassword: true)
            }
            return ArchiveError(message: "该压缩包已加密，请输入密码", needsPassword: true)
        }
        if lower.contains("unsupported") || lower.contains("not supported") {
            return ArchiveError(message: "当前系统不支持该压缩格式\n\(raw)")
        }
        if lower.contains("truncated") || lower.contains("damaged") || lower.contains("corrupt") {
            return ArchiveError(message: "压缩包已损坏或不完整")
        }
        return ArchiveError(message: raw)
    }
}

public struct ArchiveCancelled: Error {
    public init() {}
}
