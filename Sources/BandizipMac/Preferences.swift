//
//  Preferences.swift
//  BandizipMac
//

import Foundation
import ArchiveKit

final class Preferences: ObservableObject {

    static let shared = Preferences()

    private enum Key {
        static let format = "pref.defaultFormat"
        static let level = "pref.defaultLevel"
        static let subfolder = "pref.extractToSubfolder"
        static let reveal = "pref.revealAfterExtract"
        static let policy = "pref.overwritePolicy"
        static let closeAfterOpen = "pref.closePreviousArchive"
    }

    @Published var defaultFormat: ArchiveFormat {
        didSet { UserDefaults.standard.set(defaultFormat.rawValue, forKey: Key.format) }
    }

    @Published var defaultLevel: Int {
        didSet { UserDefaults.standard.set(defaultLevel, forKey: Key.level) }
    }

    /// 解压到以压缩包命名的子文件夹
    @Published var extractToSubfolder: Bool {
        didSet { UserDefaults.standard.set(extractToSubfolder, forKey: Key.subfolder) }
    }

    /// 解压完成后在 Finder 中显示
    @Published var revealAfterExtract: Bool {
        didSet { UserDefaults.standard.set(revealAfterExtract, forKey: Key.reveal) }
    }

    @Published var overwritePolicy: ExtractPolicy {
        didSet { UserDefaults.standard.set(overwritePolicy.rawValue, forKey: Key.policy) }
    }

    private init() {
        let defaults = UserDefaults.standard

        let formatRaw = defaults.string(forKey: Key.format) ?? ArchiveFormat.zip.rawValue
        defaultFormat = ArchiveFormat(rawValue: formatRaw) ?? .zip

        let storedLevel = defaults.object(forKey: Key.level) as? Int
        defaultLevel = storedLevel ?? 5

        let storedSubfolder = defaults.object(forKey: Key.subfolder) as? Bool
        extractToSubfolder = storedSubfolder ?? true

        let storedReveal = defaults.object(forKey: Key.reveal) as? Bool
        revealAfterExtract = storedReveal ?? false

        let storedPolicy = defaults.object(forKey: Key.policy) as? Int
        overwritePolicy = ExtractPolicy(rawValue: storedPolicy ?? ExtractPolicy.ask.rawValue) ?? .ask
    }

    func levelLabel(_ level: Int) -> String {
        switch level {
        case 0...1: return "仅存储"
        case 2...3: return "最快"
        case 4...6: return "标准"
        case 7...8: return "较好"
        default: return "最大压缩"
        }
    }
}
