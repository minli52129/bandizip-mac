//
//  SettingsView.swift
//  BandizipMac
//

import SwiftUI
import ArchiveKit

struct SettingsView: View {
    @ObservedObject private var preferences = Preferences.shared

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return short ?? "1.0.0"
    }

    var body: some View {
        TabView {
            general
                .tabItem { Label("通用", systemImage: "gearshape") }

            about
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 360)
    }

    private var general: some View {
        Form {
            Section {
                Picker("默认压缩格式", selection: $preferences.defaultFormat) {
                    ForEach(ArchiveFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }

                Picker("默认压缩级别", selection: $preferences.defaultLevel) {
                    ForEach(1...9, id: \.self) { level in
                        Text("\(level) · \(preferences.levelLabel(level))").tag(level)
                    }
                }
            }

            Section {
                Toggle("解压到以压缩包命名的子文件夹", isOn: $preferences.extractToSubfolder)
                Toggle("解压完成后在 Finder 中显示结果", isOn: $preferences.revealAfterExtract)

                Picker("同名文件默认处理", selection: $preferences.overwritePolicy) {
                    ForEach(ExtractPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.bottom, 8)
    }

    private var about: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.accent.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "doc.zipper")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Theme.accent)
            }

            VStack(spacing: 3) {
                Text("Bandizip for Mac")
                    .font(.system(size: 15, weight: .semibold))
                Text("版本 \(version)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }

            Text("基于 libarchive 的 macOS 压缩软件，界面思路参考 Bandizip。\n完全由 GitHub Actions 构建，本机无需 Xcode 工程。")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            Text("MIT License · libarchive (BSD-2-Clause)")
                .font(.system(size: 10))
                .foregroundStyle(Theme.tertiaryText)
        }
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.windowBackground)
    }
}
