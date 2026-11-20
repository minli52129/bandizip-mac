//
//  ArchiveContentView.swift
//  BandizipMac
//

import SwiftUI
import AppKit
import ArchiveKit

struct ArchiveContentView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            AddressBar()
            Divider()

            HStack(spacing: 0) {
                HeaderCell(title: "名称",
                           sortable: true,
                           active: state.sortKey == .name,
                           ascending: state.sortAscending) {
                    state.toggleSort(.name)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HeaderCell(title: "大小",
                           width: 92,
                           trailing: true,
                           active: state.sortKey == .size,
                           ascending: state.sortAscending) {
                    state.toggleSort(.size)
                }

                HeaderCell(title: "压缩率", width: 76, trailing: true, sortable: false)

                HeaderCell(title: "修改日期",
                           width: 158,
                           active: state.sortKey == .date,
                           ascending: state.sortAscending) {
                    state.toggleSort(.date)
                }
            }
            .frame(height: Theme.headerHeight)
            .background(Theme.barBackground)

            Divider()

            if state.visibleEntries.isEmpty {
                emptyHint
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(state.visibleEntries) { entry in
                            EntryRow(entry: entry)
                        }
                    }
                    .padding(.bottom, 12)
                }
                .background(Theme.contentBackground)
            }
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 6) {
            Image(systemName: state.searchText.isEmpty ? "folder" : "magnifyingglass")
                .font(.system(size: 22))
                .foregroundStyle(Theme.tertiaryText)
            Text(state.searchText.isEmpty ? "这个文件夹是空的" : "没有匹配「\(state.searchText)」的项目")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.contentBackground)
    }
}

// MARK: - 地址栏

struct AddressBar: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 6) {
            Button {
                state.goUp()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(state.currentPrefix.isEmpty ? Theme.tertiaryText : Theme.secondaryText)
            .disabled(state.currentPrefix.isEmpty)
            .help("返回上一级")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(state.breadcrumb.indices), id: \.self) { index in
                        let item = state.breadcrumb[index]
                        let isLast = index == state.breadcrumb.count - 1

                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8))
                                .foregroundStyle(Theme.tertiaryText)
                        }
                        Button {
                            state.jump(to: item.prefix)
                        } label: {
                            HStack(spacing: 4) {
                                if index == 0 {
                                    Image(systemName: "doc.zipper")
                                        .font(.system(size: 9))
                                        .foregroundStyle(Theme.tertiaryText)
                                }
                                Text(item.title)
                                    .font(.system(size: 11, weight: isLast ? .semibold : .regular))
                                    .foregroundStyle(isLast ? Color.primary : Theme.secondaryText)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer(minLength: 8)

            if let archive = state.archive {
                Text("\(state.visibleEntries.count) 项")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiaryText)
                    .monospacedDigit()
                Button {
                    state.revealArchiveInFinder()
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.tertiaryText)
                .help("在 Finder 中显示「\(archive.url.lastPathComponent)」")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Theme.barBackground)
    }
}

// MARK: - 行

struct EntryRow: View {
    @EnvironmentObject private var state: AppState
    let entry: ArchiveEntry

    @State private var hovering = false

    private var isSelected: Bool {
        state.selectedIDs.contains(entry.id)
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: FileIcon.symbol(for: entry))
                    .font(.system(size: 11))
                    .foregroundStyle(FileIcon.tint(for: entry))
                    .frame(width: 14)

                Text(entry.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(Color.primary)

                if entry.isEncrypted {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.tertiaryText)
                }

                Spacer(minLength: 0)
            }
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(entry.isDirectory ? "—" : Fmt.bytes(entry.size))
                .frame(width: 92, alignment: .trailing)

            Text(Fmt.ratio(entry.ratio))
                .frame(width: 76, alignment: .trailing)

            Text(Fmt.date(entry.modified))
                .frame(width: 158, alignment: .leading)
                .padding(.leading, 6)
        }
        .font(.system(size: 12))
        .monospacedDigit()
        .foregroundStyle(Theme.secondaryText)
        .frame(height: Theme.rowHeight)
        .background(background)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            handleTap()
        }
        .onTapGesture(count: 2) {
            state.activate(entry)
        }
        .contextMenu {
            Button(entry.isDirectory ? "打开文件夹" : "打开文件") {
                state.activate(entry)
            }
            Button("解压所选…") {
                if !isSelected {
                    state.selectedIDs = [entry.id]
                }
                state.promptExtract(selectionOnly: true)
            }
            Divider()
            Button("复制路径") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(entry.path, forType: .string)
            }
        }
    }

    private var background: Color {
        if isSelected {
            return Theme.accent.opacity(0.16)
        }
        if hovering {
            return Color.primary.opacity(0.05)
        }
        return Color.clear
    }

    private func handleTap() {
        let flags = NSEvent.modifierFlags
        let entries = state.visibleEntries

        if flags.contains(.command) {
            if state.selectedIDs.contains(entry.id) {
                state.selectedIDs.remove(entry.id)
            } else {
                state.selectedIDs.insert(entry.id)
            }
            return
        }

        if flags.contains(.shift),
           let anchorID = state.selectedIDs.first,
           let anchorIndex = entries.firstIndex(where: { $0.id == anchorID }),
           let currentIndex = entries.firstIndex(where: { $0.id == entry.id }) {
            let range = min(anchorIndex, currentIndex)...max(anchorIndex, currentIndex)
            state.selectedIDs = Set(entries[range].map { $0.id })
            return
        }

        state.selectedIDs = [entry.id]
    }
}
