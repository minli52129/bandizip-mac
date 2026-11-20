//
//  MainView.swift
//  BandizipMac
//

import SwiftUI
import UniformTypeIdentifiers
import ArchiveKit

struct MainView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                SidebarView()
                    .frame(width: 212)
                Divider()
                VStack(spacing: 0) {
                    ToolbarBar()
                    Divider()
                    if state.archive == nil {
                        EmptyStateView()
                    } else {
                        ArchiveContentView()
                    }
                    Divider()
                    StatusBarView()
                }
            }

            if let progress = state.progress {
                ProgressOverlay(state: progress)
            }
        }
        .background(Theme.windowBackground)
        .navigationTitle(state.archive?.url.lastPathComponent ?? "Bandizip")
        .overlay {
            if state.isDropTarget {
                DropTargetOverlay()
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $state.isDropTarget) { providers in
            state.handleDrop(providers: providers)
            return true
        }
        .sheet(item: $state.compressDraft) { draft in
            CompressSheet(draft: draft)
                .environmentObject(state)
        }
        .sheet(item: $state.extractDraft) { draft in
            ExtractSheet(draft: draft)
                .environmentObject(state)
        }
        .alert("提示", isPresented: $state.showAlert) {
            Button("好", role: .cancel) { }
        } message: {
            Text(state.alertMessage)
        }
        .frame(minWidth: 940, minHeight: 600)
    }
}

// MARK: - 顶部工具条

struct ToolbarBar: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 2) {
            ToolButton(title: "打开", icon: "folder") {
                state.promptOpen()
            }
            ToolButton(title: "解压", icon: "square.and.arrow.down", disabled: state.archive == nil) {
                state.promptExtract(selectionOnly: false)
            }
            ToolButton(title: "解压所选", icon: "square.and.arrow.down.on.square", disabled: state.selectedIDs.isEmpty) {
                state.promptExtract(selectionOnly: true)
            }
            ToolButton(title: "新建", icon: "plus.square.on.square") {
                state.promptNewArchive()
            }
            ToolButton(title: "校验", icon: "checkmark.shield", disabled: state.archive == nil) {
                state.testCurrentArchive()
            }

            Divider()
                .frame(height: 30)
                .padding(.horizontal, 6)

            ToolButton(title: "位置", icon: "arrow.up.forward.square", disabled: state.archive == nil) {
                state.revealArchiveInFinder()
            }
            ToolButton(title: "关闭", icon: "xmark.circle", disabled: state.archive == nil) {
                state.closeArchive()
            }

            Spacer(minLength: 12)

            searchField
        }
        .padding(.horizontal, 10)
        .frame(height: 50)
        .background(Theme.barBackground)
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiaryText)

            TextField("搜索压缩包内容", text: $state.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))

            if !state.searchText.isEmpty {
                Button {
                    state.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(width: 216, height: 26)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.contentBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Theme.separator, lineWidth: 1)
        )
        .opacity(state.archive == nil ? 0.45 : 1)
        .disabled(state.archive == nil)
    }
}

// MARK: - 底部状态条

struct StatusBarView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 6) {
            if let archive = state.archive {
                Image(systemName: "doc.zipper")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.tertiaryText)

                Text("\(archive.listing.fileCount) 个文件 · \(archive.listing.directoryCount) 个文件夹")

                if !state.selectedIDs.isEmpty {
                    Text("·").foregroundStyle(Theme.tertiaryText)
                    Text("已选 \(state.selectedIDs.count) 项")
                        .foregroundStyle(Theme.accent)
                }

                Spacer(minLength: 8)

                Text("原始 \(Fmt.bytes(archive.totalSize))")
                Text("·").foregroundStyle(Theme.tertiaryText)
                Text("压缩包 \(Fmt.bytes(archive.compressedBytes))")
                Text("·").foregroundStyle(Theme.tertiaryText)
                Text("压缩率 \(Fmt.ratio(archive.overallRatio))")

                if archive.listing.isEncrypted {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.tertiaryText)
                        .help("该压缩包包含加密内容")
                }

                Chip(text: archive.formatLabel)
            } else {
                Text("未打开压缩包")
                Spacer()
            }
        }
        .font(.system(size: 11))
        .monospacedDigit()
        .foregroundStyle(Theme.secondaryText)
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(Theme.barBackground)
    }
}

// MARK: - 拖放高亮

struct DropTargetOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.06)

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [9, 6]))
                .padding(14)

            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.accent)
                Text("松开即可添加")
                    .font(.system(size: 15, weight: .semibold))
                Text("压缩包会直接打开，其他文件会进入「新建压缩包」")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: 1)
            )
        }
        .allowsHitTesting(false)
    }
}
