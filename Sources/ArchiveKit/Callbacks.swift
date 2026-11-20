//
//  Callbacks.swift
//  ArchiveKit
//
//  C 回调不能捕获上下文，这里用一个盒子对象通过 void* 传进 C 层。
//

import Foundation
import CArchive

public enum ExtractPolicy: Int, CaseIterable, Identifiable, Sendable {
    case skip = 0
    case overwrite = 1
    case rename = 2
    case ask = 3

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .skip: return "跳过同名文件"
        case .overwrite: return "覆盖同名文件"
        case .rename: return "自动重命名"
        case .ask: return "逐项询问"
        }
    }
}

final class CallbackBox {
    var progress: ((Int64, Int64) -> Void)?
    var isCancelled: (() -> Bool)?
    var onExists: ((String) -> Int32)?
}

func bzProgressTrampoline(_ done: Int64, _ total: Int64, _ ctx: UnsafeMutableRawPointer?) {
    guard let ctx = ctx else { return }
    let box = Unmanaged<CallbackBox>.fromOpaque(ctx).takeUnretainedValue()
    box.progress?(done, total)
}

func bzCancelTrampoline(_ ctx: UnsafeMutableRawPointer?) -> Int32 {
    guard let ctx = ctx else { return 0 }
    let box = Unmanaged<CallbackBox>.fromOpaque(ctx).takeUnretainedValue()
    return (box.isCancelled?() ?? false) ? 1 : 0
}

func bzExistsTrampoline(_ path: UnsafePointer<CChar>?, _ ctx: UnsafeMutableRawPointer?) -> Int32 {
    guard let ctx = ctx, let path = path else { return 1 }
    let box = Unmanaged<CallbackBox>.fromOpaque(ctx).takeUnretainedValue()
    return box.onExists?(String(cString: path)) ?? 1
}

func withCStringOrNil<T>(_ value: String?, _ body: (UnsafePointer<CChar>?) -> T) -> T {
    guard let value = value, !value.isEmpty else {
        return body(nil)
    }
    return value.withCString { body($0) }
}

func takeError(_ pointer: inout UnsafeMutablePointer<CChar>?) -> String? {
    guard let raw = pointer else { return nil }
    let message = String(cString: raw)
    bz_free(raw)
    pointer = nil
    return message
}
