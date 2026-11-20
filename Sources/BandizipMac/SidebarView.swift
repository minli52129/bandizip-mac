//
//  SidebarView.swift
//  BandizipMac
//

import SwiftUI
import AppKit

private struct QuickLocation: Identifiable {
    let id: String
    let icon: String
    let url: URL
}

struct SidebarView: View {
    @EnvironmentObject private var state: AppState

    private var quickLocations: [QuickLocation] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates: [QuickLocation] = [
            QuickLocation(id: "个人文件夹", icon: "house", url: home),
            QuickLocation(id: "桌面", icon: "desktopcomputer", url: home.appendingPathComponent("Desktop")),
            QuickLocation(id: "下载", icon: "arrow.down.circle", url: home.appendingPathComponent("Downloads")),
            QuickLocation(id: "文稿", icon: "doc.text", url: home.appendingPathComponent("Documents"))
        ]
        return candidates.filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    SidebarSectionTitle(title: "快速访问")

                    ForEach(quickLocations) { location in
                        SidebarRow(title: location.id, icon: location.icon) {
                            NSWorkspace.shared.open(location.url)
                        }
                    }

                    SidebarSectionTitle(title: "最近打开")

                    if state.recentFiles.isEmpty {
                        Text("还没有打开过压缩包")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.tertiaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(state.recentFiles, id: \.self) { url in
                            SidebarRow(title: url.lastPathComponent,
                                       icon: "doc.zipper",
                                       subtitle: url.deletingLastPathComponent().path,
                                       selected: state.archive?.url == url) {
                                state.openArchive(url: url)
                            }
                        }
                    }

                    SidebarSectionTitle(title: "支持格式")

                    FlowChips()
                        .padding(.horizontal, 10)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 12)
            }

            Divider()

            HStack(spacing: 6) {
                Button {
                    state.promptNewArchive()
                } label: {
                    Label("新建压缩包", systemImage: "plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)

                Spacer()

                if !state.recentFiles.isEmpty {
                    Button {
                        state.clearRecent()
                    } label: {
                        Text("清空")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.tertiaryText)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
        }
        .background(Theme.barBackground.opacity(0.55))
    }
}

/// 简单的流式标签排版（格式列表）
struct FlowChips: View {
    private let formats = ["ZIP", "7Z", "RAR", "TAR", "GZ", "BZ2", "XZ", "ISO", "ALZ"]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { column in
                        let index = row * 3 + column
                        if index < formats.count {
                            Chip(text: formats[index], tint: Theme.secondaryText)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
